import Foundation
import SwiftUI

@MainActor
final class OnCallViewModel: ObservableObject {
    @Published var teams: [OpsTeam] = []
    @Published var allSchedules: [OpsSchedule] = []      // all schedules, keyed lookup by teamId
    @Published var onCallResults: [String: [OnCallParticipant]] = [:]  // scheduleId -> participants
    @Published var displayNames: [String: String] = [:]  // accountId -> displayName cache

    @Published var alerts: [OpsAlert] = []
    @Published var isLoadingAlerts = false
    @Published var alertFilter: AlertFilter = .open
    @Published var currentUserAccountId: String = ""    // for "Assigned to Me" filter

    @Published var isLoadingTeams = false
    @Published var isLoadingOnCall = false
    @Published var error: String?
    @Published var lastFetched: Date?

    enum AlertFilter: String, CaseIterable {
        case all            = "All"
        case open           = "Open"
        case unacknowledged = "Unacknowledged"
        case assignedToMe   = "Assigned to Me"
        case closed         = "Closed"
    }

    var filteredAlerts: [OpsAlert] {
        switch alertFilter {
        case .all:            return alerts
        case .open:           return alerts.filter { $0.status.lowercased() == "open" }
        case .unacknowledged: return alerts.filter { $0.status.lowercased() == "open" && !($0.acknowledged ?? false) }
        case .assignedToMe:   return alerts.filter { $0.owner == currentUserAccountId && !currentUserAccountId.isEmpty }
        case .closed:         return alerts.filter { $0.status.lowercased() == "closed" }
        }
    }

    private let service = JSMOpsService()

    var favoriteTeams: [OpsTeam] {
        []  // populated by caller from appState.favoriteJSMTeams
    }

    // MARK: - Load

    func load(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira not configured — add credentials in Settings → Jira"
            return
        }
        error = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTeams(appState: appState) }
            group.addTask { await self.loadAlerts(appState: appState) }
        }
        lastFetched = Date()
    }

    func loadAlerts(appState: AppState) async {
        let gk = appState.jsmOpsAPIKey
        guard !gk.isEmpty else {
            alerts = []   // no GenieKey — graceful degradation
            return
        }
        isLoadingAlerts = true
        do {
            alerts = try await service.listAlertsViaGenieKey(apiKey: gk, limit: 100)
        } catch {
            alerts = []   // silently fail — alerts are supplementary
        }
        isLoadingAlerts = false
    }

    func discoverTeams(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira not configured — add credentials in Settings → Jira"
            return
        }
        isLoadingTeams = true
        error = nil
        do {
            teams = try await service.listTeams(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingTeams = false
    }

    /// Load on-call for all schedules belonging to a given team.
    /// Uses schedule IDs (not team IDs) for the API call.
    func loadOnCallForTeam(teamId: String, appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isLoadingOnCall = true

        let teamSchedules = allSchedules.filter { $0.teamId == teamId }
        for schedule in teamSchedules {
            do {
                let participants = try await service.getOnCall(
                    baseURL: appState.jiraBaseURL,
                    email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken,
                    scheduleId: schedule.id      // ← schedule ID, not team ID
                )
                onCallResults[schedule.id] = participants

                // Resolve display names for any new accountIds
                for p in participants where displayNames[p.name] == nil {
                    if let name = try? await service.resolveDisplayName(
                        accountId: p.name,
                        baseURL: appState.jiraBaseURL,
                        email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken
                    ) {
                        displayNames[p.name] = name
                    }
                }
            } catch {
                // Individual schedule failure doesn't block others
            }
        }
        isLoadingOnCall = false
    }

    // Keep for backward compat — delegates to loadOnCallForTeam
    func loadOnCall(for teamId: String, appState: AppState) async {
        await loadOnCallForTeam(teamId: teamId, appState: appState)
    }

    // MARK: - Private

    private func loadTeams(appState: AppState) async {
        isLoadingTeams = true
        do {
            // Load all schedules first — needed for team→schedule ID mapping
            let scheduleList = try await service.listSchedules(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            allSchedules = scheduleList

            // Try to load teams; fall back to building pseudo-teams from schedules
            let teamList = (try? await service.listTeams(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )) ?? []

            if !teamList.isEmpty {
                teams = teamList
            } else {
                // Deduplicate: one pseudo-team per unique teamId in schedules
                var seen = Set<String>()
                teams = scheduleList.compactMap { s -> OpsTeam? in
                    guard let tid = s.teamId, !seen.contains(tid) else { return nil }
                    seen.insert(tid)
                    return OpsTeam(id: tid, name: s.name, description: nil)
                }
                // If no teamIds, treat each schedule as its own "team"
                if teams.isEmpty {
                    teams = scheduleList.map { OpsTeam(id: $0.id, name: $0.name, description: nil) }
                }
            }

            // Now load on-call for each favorited team (uses schedule IDs internally)
            for teamId in appState.favoriteJSMTeams {
                await loadOnCallForTeam(teamId: teamId, appState: appState)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingTeams = false
    }
}

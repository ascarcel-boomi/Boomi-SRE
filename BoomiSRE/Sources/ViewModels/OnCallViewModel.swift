import Foundation
import SwiftUI

@Observable
@MainActor
final class OnCallViewModel {
    var teams: [OpsTeam] = []
    var allSchedules: [OpsSchedule] = []      // all schedules, keyed lookup by teamId
    var onCallResults: [String: [OnCallParticipant]] = [:]  // scheduleId -> participants
    var displayNames: [String: String] = [:]  // accountId -> displayName cache

    var alerts: [OpsAlert] = []
    var isLoadingAlerts = false
    var alertFilter: AlertFilter = .open
    var actionInProgress: Set<String> = []
    var actionError: String?
    var actionSuccess: String?

    @ObservationIgnored private var actionSuccessClearTask: Task<Void, Never>?

    var isLoadingTeams = false
    var isLoadingOnCall = false
    var error: String?
    var lastFetched: Date?

    /// True if data has never been loaded or is older than 1 hour.
    var needsRefresh: Bool {
        guard let last = lastFetched else { return true }
        return Date().timeIntervalSince(last) > 3600
    }

    enum AlertFilter: String, CaseIterable {
        case all            = "All"
        case open           = "Open"
        case unacknowledged = "Unacknowledged"
        case assignedToMe   = "Assigned to Me"
        case closed         = "Closed"
    }

    /// Filter alerts by product context (JSM team IDs) then by status filter.
    /// When `activeJSMTeamIds` is non-empty, only alerts whose responders include
    /// one of those teams are shown. Pass empty to show all (no product filter).
    func filteredAlerts(userEmail: String = "", activeJSMTeamIds: [String] = []) -> [OpsAlert] {
        // Product-context filter: when teams are mapped, only show their alerts
        let productFiltered: [OpsAlert]
        if !activeJSMTeamIds.isEmpty {
            let teamIdSet = Set(activeJSMTeamIds)
            productFiltered = alerts.filter { alert in
                alert.responders.contains { teamIdSet.contains($0.id) }
            }
        } else {
            productFiltered = alerts
        }

        switch alertFilter {
        case .all:            return productFiltered
        case .open:           return productFiltered.filter { $0.status.lowercased() == "open" }
        case .unacknowledged: return productFiltered.filter { $0.status.lowercased() == "open" && !$0.acknowledged }
        case .assignedToMe:   return productFiltered.filter { !$0.owner.isEmpty && $0.owner.lowercased() == userEmail.lowercased() }
        case .closed:         return productFiltered.filter { $0.status.lowercased() == "closed" }
        }
    }

    @ObservationIgnored private let service = JSMOpsService()

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

    // MARK: - Alert Actions

    func acknowledgeAlert(_ alert: OpsAlert, note: String? = nil, appState: AppState) async {
        await performAction(alertId: alert.id, appState: appState, successMessage: "Alert acknowledged") {
            try await service.acknowledgeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                               apiToken: appState.jiraAPIToken, alertId: alert.id, note: note)
        }
        if self.actionError == nil { ProductivityTracker.shared.log(.alertAcknowledged, detail: alert.message, source: "On-Call") }
    }

    func closeAlert(_ alert: OpsAlert, note: String? = nil, appState: AppState) async {
        await performAction(alertId: alert.id, appState: appState, successMessage: "Alert closed") {
            try await service.closeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                         apiToken: appState.jiraAPIToken, alertId: alert.id, note: note)
        }
        if self.actionError == nil { ProductivityTracker.shared.log(.alertClosed, detail: alert.message, source: "On-Call") }
    }

    func unacknowledgeAlert(_ alert: OpsAlert, appState: AppState) async {
        await performAction(alertId: alert.id, appState: appState, successMessage: "Alert unacknowledged") {
            try await service.unacknowledgeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                                  apiToken: appState.jiraAPIToken, alertId: alert.id)
        }
    }

    func addNoteToAlert(_ alert: OpsAlert, note: String, appState: AppState) async {
        await performAction(alertId: alert.id, appState: appState, successMessage: "Note added") {
            try await service.addAlertNote(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                           apiToken: appState.jiraAPIToken, alertId: alert.id, note: note)
        }
        if self.actionError == nil { ProductivityTracker.shared.log(.alertNoteAdded, detail: alert.message, source: "On-Call") }
    }

    func snoozeAlert(_ alert: OpsAlert, until endTime: Date, appState: AppState) async {
        await performAction(alertId: alert.id, appState: appState, successMessage: "Alert snoozed") {
            try await service.snoozeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                          apiToken: appState.jiraAPIToken, alertId: alert.id, endTime: endTime)
        }
        if self.actionError == nil { ProductivityTracker.shared.log(.alertSnoozed, detail: alert.message, source: "On-Call") }
    }

    func bulkAcknowledge(alerts: [OpsAlert], appState: AppState) async {
        for alert in alerts { await acknowledgeAlert(alert, appState: appState) }
        ProductivityTracker.shared.log(.bulkAlertAcknowledge, detail: "Bulk ACK \(alerts.count) alerts", source: "On-Call")
    }

    func bulkClose(alerts: [OpsAlert], appState: AppState) async {
        for alert in alerts { await closeAlert(alert, appState: appState) }
        ProductivityTracker.shared.log(.bulkAlertClose, detail: "Bulk close \(alerts.count) alerts", source: "On-Call")
    }

    private func performAction(alertId: String, appState: AppState, successMessage: String,
                               action: () async throws -> Void) async {
        actionInProgress.insert(alertId)
        actionError = nil
        do {
            try await action()
            actionSuccess = successMessage
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await loadAlerts(appState: appState)
        } catch {
            actionError = error.localizedDescription
        }
        actionInProgress.remove(alertId)
        if actionSuccess != nil {
            actionSuccessClearTask?.cancel()
            actionSuccessClearTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                actionSuccess = nil
            }
        }
    }

    func loadAlerts(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isLoadingAlerts = true
        do {
            alerts = try await service.listAlerts(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                limit: 100
            )
        } catch {
            alerts = []
            // Don't overwrite primary error from loadTeams; only set if no other error
            if self.error == nil {
                self.error = "Alerts: \(error.localizedDescription)"
            }
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

            // Load on-call for product-mapped teams (primary) or legacy favorites (fallback)
            let effectiveTeamIds = appState.activeJSMTeamIds.isEmpty
                ? appState.favoriteJSMTeams
                : appState.activeJSMTeamIds
            for teamId in effectiveTeamIds {
                await loadOnCallForTeam(teamId: teamId, appState: appState)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingTeams = false
    }
}

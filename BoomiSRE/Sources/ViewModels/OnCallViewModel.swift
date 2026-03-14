import Foundation
import SwiftUI

@MainActor
final class OnCallViewModel: ObservableObject {
    @Published var teams: [OpsTeam] = []
    @Published var onCallResults: [String: [OnCallParticipant]] = [:]  // teamId -> participants
    @Published var alerts: [OpsAlert] = []
    @Published var schedules: [String: [OpsSchedule]] = [:]            // teamId -> schedules
    @Published var alertFilter: AlertFilter = .open

    @Published var isLoadingTeams = false
    @Published var isLoadingAlerts = false
    @Published var isLoadingOnCall = false
    @Published var error: String?
    @Published var alertMessage: String?
    @Published var lastFetched: Date?

    enum AlertFilter: String, CaseIterable {
        case open  = "Open"
        case acked = "Acknowledged"
        case all   = "All (24h)"
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

    func discoverTeams(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira not configured"
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

    func loadOnCall(for teamId: String, appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isLoadingOnCall = true
        do {
            let participants = try await service.getOnCall(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                teamId: teamId
            )
            onCallResults[teamId] = participants
        } catch {
            // Don't surface per-team errors; just leave empty
        }
        isLoadingOnCall = false
    }

    var filteredAlerts: [OpsAlert] {
        switch alertFilter {
        case .open:  return alerts.filter { $0.status == "open" }
        case .acked: return alerts.filter { $0.status == "acked" }
        case .all:   return alerts
        }
    }

    // MARK: - Private

    private func loadTeams(appState: AppState) async {
        isLoadingTeams = true
        do {
            teams = try await service.listTeams(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            // Load on-call for favorite teams
            for teamId in appState.favoriteJSMTeams {
                await loadOnCall(for: teamId, appState: appState)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingTeams = false
    }

    private func loadAlerts(appState: AppState) async {
        isLoadingAlerts = true
        do {
            alerts = try await service.listAlerts(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
        } catch {
            // Alert loading failure shouldn't block the whole view
        }
        isLoadingAlerts = false
    }
}

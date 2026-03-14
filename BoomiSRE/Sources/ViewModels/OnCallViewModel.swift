import Foundation
import SwiftUI

@MainActor
final class OnCallViewModel: ObservableObject {
    @Published var teams: [OpsTeam] = []
    @Published var onCallResults: [String: [OnCallParticipant]] = [:]  // scheduleId -> participants
    @Published var alerts: [OpsAlert] = []
    @Published var schedules: [String: [OpsSchedule]] = [:]
    @Published var alertFilter: AlertFilter = .open
    @Published var displayNames: [String: String] = [:]  // accountId -> displayName cache

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
            // Alerts are not available via the Jira-authenticated API
        }
        lastFetched = Date()
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

    func loadOnCall(for scheduleId: String, appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isLoadingOnCall = true
        do {
            let participants = try await service.getOnCall(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                scheduleId: scheduleId
            )
            onCallResults[scheduleId] = participants
            // Resolve accountIds to display names in the background
            for p in participants where !displayNames.keys.contains(p.name) {
                Task {
                    if let name = try? await service.resolveDisplayName(
                        accountId: p.name,
                        baseURL: appState.jiraBaseURL,
                        email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken
                    ) {
                        await MainActor.run { self.displayNames[p.name] = name }
                    }
                }
            }
        } catch {
            // Don't surface per-schedule errors; just leave empty
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
            // Load schedules as the primary entity (schedules = on-call rotations)
            let scheduleList = try await service.listSchedules(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            // Also try to load teams
            let teamList = (try? await service.listTeams(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )) ?? []

            // Use teams if available, fall back to schedules-as-teams
            if !teamList.isEmpty {
                teams = teamList
            } else {
                teams = scheduleList.map { OpsTeam(id: $0.id, name: $0.name, description: nil) }
            }

            // Load on-call for each favorited item
            for itemId in appState.favoriteJSMTeams {
                await loadOnCall(for: itemId, appState: appState)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingTeams = false
    }
}

import SwiftUI

// MARK: - Executive Assistant Settings
// Extracted from AISettingsContent to give briefing configuration its own tab.

struct ExecAssistantSettingsContent: View {
    @EnvironmentObject var appState: AppState

    private let allBriefingTypes: [(key: String, label: String, description: String)] = [
        ("morningBrief", "Morning Brief", "Daily status overview: incidents, PRs, on-call, and top Jira priorities."),
        ("emailTriage", "Email Triage", "Summarizes your Gmail inbox and flags action items."),
        ("preMeetingBrief", "Pre-Meeting Brief", "Pulls context for your next calendar event."),
        ("actionTracker", "Action Tracker", "Tracks open action items from past meetings and Jira."),
        ("eodDigest", "EOD Digest", "End-of-day summary of completed work and tomorrow's plan."),
        ("dailyTicketBrief", "Daily Ticket Brief", "Summarizes Jira ticket activity across your active products."),
        ("claudeUsage", "Claude Usage", "Reports AI Copilot usage and token consumption.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Executive Assistant").font(.title2.bold())
            Text("Configure which briefings the Executive Assistant generates and when.")
                .font(.callout).foregroundStyle(.secondary)

            SettingsSection("Auto-Generate") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Auto-generate briefings on app launch", isOn: Binding(
                        get: { appState.autoGenerateBriefingsOnLaunch },
                        set: { appState.autoGenerateBriefingsOnLaunch = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Text("Automatically generates the enabled briefing types below each time the app starts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SettingsSection("Briefing Types") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enable or disable individual briefing types. Disabled briefings will not appear in the Executive Assistant panel.")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(allBriefingTypes, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(item.label, isOn: Binding(
                                get: { appState.enabledBriefingTypes.contains(item.key) },
                                set: { on in
                                    if on { appState.enabledBriefingTypes.insert(item.key) }
                                    else  { appState.enabledBriefingTypes.remove(item.key) }
                                    appState.saveConfig()
                                }
                            )).toggleStyle(.switch)
                            Text(item.description)
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                    }
                }
            }

            SettingsSection("Data Sources") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Briefings pull data from the integrations below. Configure them in the Integrations section if not connected.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        dataSourceBadge("Jira", status: appState.jiraAuthStatus)
                        dataSourceBadge("GitHub", status: appState.githubAuthStatus)
                        dataSourceBadge("Gmail", status: appState.googleAuthStatus)
                        dataSourceBadge("Grafana", status: appState.grafanaAuthStatus)
                    }
                }
            }
        }
    }

    private func dataSourceBadge(_ name: String, status: AuthStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(name).font(.caption)
        }
    }
}

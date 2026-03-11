import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedReport) {
            // Home
            Button {
                appState.selectedReport = nil
                appState.showSettings = false
            } label: {
                Label("Home", systemImage: "house")
                    .font(.body.bold())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Active report sections
            ForEach(ReportCatalog.activeSections, id: \.self) { section in
                let reports = ReportCatalog.reports(for: section)
                Section {
                    ForEach(reports) { report in
                        NavigationLink(value: report) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title)
                                    .font(.body)
                                Text(report.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.headline)
                }
            }

            // Coming soon
            Section {
                Label("Jira reports via API — configure in Settings", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Label("Coming Soon", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Settings item
            Section {
                Button {
                    appState.selectedReport = nil
                    appState.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.showSettings ? .primary : .secondary)
            }

            // Auth status
            Section {
                authRow(label: "AWS", status: appState.awsAuthStatus)
                authRow(label: "Jira", status: appState.jiraAuthStatus)
                authRow(label: "Confluence", status: appState.confluenceAuthStatus)
                authRow(label: "Bitbucket", status: appState.bitbucketAuthStatus)
                authRow(label: "GitHub", status: appState.githubAuthStatus)
            } header: {
                Label("Services", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Boomi SRE")
        .onChange(of: appState.selectedReport) {
            // When a report is selected, leave settings
            if appState.selectedReport != nil {
                appState.showSettings = false
            }
        }
    }

    private func authRow(label: String, status: AuthStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
            Spacer()
            Text(statusSummary(status))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusSummary(_ status: AuthStatus) -> String {
        switch status {
        case .authenticated: return "Connected"
        case .expired: return "Expired"
        case .checking: return "Checking..."
        case .notConfigured: return "Not configured"
        case .error: return "Error"
        case .unknown: return "-"
        }
    }
}

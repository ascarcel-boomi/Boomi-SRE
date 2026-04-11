import SwiftUI

/// Settings > Integrations > Overview — shows all integrations with health status and quick actions.
struct IntegrationsOverviewContent: View {
    @EnvironmentObject var appState: AppState

    private struct IntegrationRow {
        let id: String
        let name: String
        let icon: String
        let status: AuthStatus
        let settingsTab: String
    }

    private var integrations: [IntegrationRow] {
        [
            .init(id: "jira",       name: "Jira",       icon: "ticket",                              status: appState.jiraAuthStatus,       settingsTab: "jira"),
            .init(id: "aws",        name: "AWS SSO",    icon: "cloud",                               status: appState.awsAuthStatus,        settingsTab: "aws"),
            .init(id: "grafana",    name: "Grafana",    icon: "chart.line.uptrend.xyaxis",           status: appState.grafanaAuthStatus,    settingsTab: "grafana"),
            .init(id: "github",     name: "GitHub",     icon: "chevron.left.forwardslash.chevron.right", status: appState.githubAuthStatus, settingsTab: "github"),
            .init(id: "bitbucket",  name: "Bitbucket",  icon: "externaldrive.connected.to.line.below", status: appState.bitbucketAuthStatus, settingsTab: "bitbucket"),
            .init(id: "jenkins",    name: "Jenkins",    icon: "hammer",                              status: appState.jenkinsAuthStatus,    settingsTab: "jenkins"),
            .init(id: "confluence", name: "Confluence", icon: "book.closed",                         status: appState.confluenceAuthStatus, settingsTab: "confluence"),
            .init(id: "google",     name: "Google",     icon: "envelope",                            status: appState.googleAuthStatus,     settingsTab: "google"),
        ]
    }

    private var connectedCount: Int {
        integrations.filter { if case .authenticated = $0.status { return true }; return false }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Integrations").font(.title2.bold())

            // Summary card
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(connectedCount) of \(integrations.count)")
                        .font(.title3.bold())
                        .foregroundStyle(appState.themeAccent)
                    Text("integrations connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { appState.checkAllServices() }
                } label: {
                    Label("Re-check All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .fill(appState.themeAccent.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .strokeBorder(appState.themeAccent.opacity(0.15)))

            // Health banners for services needing attention
            let unhealthy = integrations.filter { row in
                if case .error = row.status { return true }
                if case .expired = row.status { return true }
                return false
            }
            if !unhealthy.isEmpty {
                VStack(spacing: 6) {
                    ForEach(unhealthy, id: \.id) { row in
                        IntegrationHealthBanner(
                            service: row.name,
                            status: row.status,
                            settingsTab: row.settingsTab,
                            appState: appState
                        )
                    }
                }
            }

            // Per-integration rows
            SettingsSection("Status") {
                VStack(spacing: 0) {
                    ForEach(Array(integrations.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { Divider() }
                        integrationRow(row)
                    }
                }
            }
        }
    }

    private func integrationRow(_ row: IntegrationRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.callout)
                Text(row.status.label)
                    .font(.caption)
                    .foregroundStyle(statusLabelColor(row.status))
            }

            Spacer()

            statusDot(row.status)

            Button("Configure") {
                appState.selectedSettingsTab = row.settingsTab
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func statusDot(_ status: AuthStatus) -> some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
    }

    private func statusLabelColor(_ status: AuthStatus) -> Color {
        switch status {
        case .authenticated: return .green
        case .error, .expired: return .red
        case .checking: return .orange
        default: return .secondary
        }
    }
}

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

            // Auth status — clickable to retry or configure
            Section {
                authButton(label: "AWS", status: appState.awsAuthStatus) { retryService("aws") }
                authButton(label: "Jira", status: appState.jiraAuthStatus) { retryService("jira") }
                authButton(label: "Confluence", status: appState.confluenceAuthStatus) { retryService("confluence") }
                authButton(label: "Bitbucket", status: appState.bitbucketAuthStatus) { retryService("bitbucket") }
                authButton(label: "GitHub", status: appState.githubAuthStatus) { retryService("github") }
                authButton(label: "Jenkins", status: appState.jenkinsAuthStatus) { retryService("jenkins") }
                authButton(label: "Grafana", status: appState.grafanaAuthStatus) { retryService("grafana") }
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

    private func authButton(label: String, status: AuthStatus, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: 6) {
                if case .checking = status {
                    ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.caption)
                Spacer()
                Text(statusSummary(status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(status.isOK ? "Click to re-check" : "Click to retry or configure")
    }

    private let awsAuth = AWSAuthService()

    private func retryService(_ service: String) {
        // If not configured, go to settings
        switch service {
        case "aws":
            if appState.awsSSOProfile.isEmpty { goToSettings(); return }
            retryAWS()
            return
        case "jira":
            if !appState.isJiraConfigured { goToSettings(); return }
        case "confluence":
            if appState.confluenceAPIToken.isEmpty { goToSettings(); return }
        case "bitbucket":
            if appState.bitbucketAPIToken.isEmpty { goToSettings(); return }
        case "github":
            if appState.githubToken.isEmpty { goToSettings(); return }
        case "jenkins":
            if appState.jenkinsToken.isEmpty { goToSettings(); return }
        case "grafana":
            if appState.grafanaToken.isEmpty { goToSettings(); return }
        default: break
        }

        // Re-check all services
        appState.checkAllServices()
    }

    private func retryAWS() {
        appState.awsAuthStatus = .checking
        Task {
            do {
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
            } catch {
                // Expired — open SSO start page and run login
                await MainActor.run {
                    appState.awsAuthStatus = .expired
                    openSSOStartPage()
                }
                do {
                    _ = try await awsAuth.login(profile: appState.awsSSOProfile)
                    let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                    await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
                } catch {
                    await MainActor.run { appState.awsAuthStatus = .expired }
                }
            }
        }
    }

    private func openSSOStartPage() {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")
        if let content = try? String(contentsOf: configPath, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("sso_start_url") && trimmed.contains("=") {
                    let url = trimmed.components(separatedBy: "=")
                        .dropFirst().joined(separator: "=")
                        .trimmingCharacters(in: .whitespaces)
                    if let ssoURL = URL(string: url) {
                        NSWorkspace.shared.open(ssoURL)
                        return
                    }
                }
            }
        }
    }

    private func goToSettings() {
        appState.selectedReport = nil
        appState.showSettings = true
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

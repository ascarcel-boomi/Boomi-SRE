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

            // AI section
            Section {
                ForEach(ReportCatalog.reports(for: .ai)) { report in
                    NavigationLink(value: report) {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title)
                                    .font(.body)
                                Text(report.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            // Unread badge for Executive Assistant
                            if report.id == "exec_assistant" && appState.unreadBriefingCount > 0 {
                                Text("\(appState.unreadBriefingCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("AI", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Jira section (features + status)
            Section {
                ForEach(ReportCatalog.reports(for: .jira)) { report in
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
                sectionHeader(
                    title: "Jira", icon: "ticket",
                    status: appState.jiraAuthStatus,
                    retryAction: { retryService("jira") }
                )
            }

            // AWS section (features + status)
            Section {
                ForEach(ReportCatalog.reports(for: .aws)) { report in
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
                sectionHeader(
                    title: "AWS", icon: "cloud",
                    status: appState.awsAuthStatus,
                    retryAction: { retryService("aws") }
                )
            }

            // Google section (features + status)
            Section {
                ForEach(ReportCatalog.reports(for: .google)) { report in
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
                sectionHeader(
                    title: "Google", icon: "envelope",
                    status: appState.googleAuthStatus,
                    retryAction: { retryService("google") }
                )
            }

            // Services section (browsers with full UI)
            Section {
                ForEach(ReportCatalog.reports(for: .services)) { report in
                    NavigationLink(value: report) {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title).font(.body)
                                Text(report.description).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            // Auth status dot
                            let status = serviceStatus(for: report.id)
                            if case .checking = status {
                                ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                            } else {
                                Circle().fill(status.color).frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                // Bitbucket stays as a status-only item
                authButton(label: "Bitbucket", status: appState.bitbucketAuthStatus) { retryService("bitbucket") }
            } header: {
                Label("Services", systemImage: "network")
                    .font(.headline).foregroundStyle(.secondary)
            }

            // Settings
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
        }
        .listStyle(.sidebar)
        .navigationTitle("Boomi SRE")
        .onChange(of: appState.selectedReport) {
            if appState.selectedReport != nil {
                appState.showSettings = false
            }
        }
    }

    // MARK: - Section Header with Status

    private func sectionHeader(title: String, icon: String, status: AuthStatus, retryAction: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
            Spacer()
            if case .checking = status {
                ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { retryAction() } label: {
                Label("Re-check Connection", systemImage: "arrow.clockwise")
            }
            Button { goToSettings() } label: {
                Label("Open Settings", systemImage: "gear")
            }
        }
    }

    // MARK: - Auth button for services without features

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
        .contextMenu {
            Button { action() } label: {
                Label("Re-check Connection", systemImage: "arrow.clockwise")
            }
            Button { goToSettings() } label: {
                Label("Open Settings", systemImage: "gear")
            }
            Divider()
            Button(role: .destructive) {
                disconnect(label.lowercased())
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .disabled(status == .notConfigured)
        }
    }

    private let awsAuth = AWSAuthService()

    private func retryService(_ service: String) {
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
        case "google":
            if appState.googleCredentials == nil { goToSettings(); return }
        default: break
        }
        appState.checkAllServices()
    }

    private func retryAWS() {
        appState.awsAuthStatus = .checking
        Task {
            do {
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
            } catch {
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

    private func disconnect(_ service: String) {
        switch service {
        case "aws":
            appState.awsAuthStatus = .expired
            Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: AWSAuthService.resolvedAWSPath)
                process.arguments = ["sso", "logout", "--profile", appState.awsSSOProfile]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                try? process.run()
                process.waitUntilExit()
            }
        case "jira":
            appState.jiraAPIToken = ""
            appState.jiraAuthStatus = .notConfigured
        case "confluence":
            appState.confluenceAPIToken = ""
            appState.confluenceAuthStatus = .notConfigured
        case "bitbucket":
            appState.bitbucketAPIToken = ""
            appState.bitbucketAuthStatus = .notConfigured
        case "github":
            appState.githubToken = ""
            appState.githubAuthStatus = .notConfigured
        case "jenkins":
            appState.jenkinsToken = ""
            appState.jenkinsAuthStatus = .notConfigured
        case "grafana":
            appState.grafanaToken = ""
            appState.grafanaAuthStatus = .notConfigured
        default: break
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

    private func serviceStatus(for reportId: String) -> AuthStatus {
        switch reportId {
        case "github_browser":    return appState.githubAuthStatus
        case "jenkins_browser":   return appState.jenkinsAuthStatus
        case "grafana_browser":   return appState.grafanaAuthStatus
        case "confluence_browser": return appState.confluenceAuthStatus
        default: return .unknown
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

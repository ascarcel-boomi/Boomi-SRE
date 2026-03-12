import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    private let awsAuth = AWSAuthService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Boomi SRE Reports")
                .font(.largeTitle.bold())

            Text("Select a report from the sidebar to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "person.crop.rectangle.stack", color: .blue,
                           text: "Jira Dashboards — TODO list, saved filters, boards")
                FeatureRow(icon: "dollarsign.circle", color: .green,
                           text: "AWS Cost Reports — multi-account cost analysis and trends")
            }
            .padding(.top, 8)

            // Auth status cards — clickable
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                authCard(service: "AWS SSO", icon: "cloud", status: appState.awsAuthStatus,
                         settingsTab: "aws", canRetry: true) { retryAWS() }
                authCard(service: "Jira", icon: "ticket", status: appState.jiraAuthStatus,
                         settingsTab: "jira", canRetry: true) { retryJira() }
                authCard(service: "Confluence", icon: "book.closed", status: appState.confluenceAuthStatus,
                         settingsTab: "confluence", canRetry: true) { retryConfluence() }
                authCard(service: "Bitbucket", icon: "externaldrive.connected.to.line.below", status: appState.bitbucketAuthStatus,
                         settingsTab: "bitbucket", canRetry: true) { retryBitbucket() }
                authCard(service: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: appState.githubAuthStatus,
                         settingsTab: "github", canRetry: true) { retryGitHub() }
                authCard(service: "Jenkins", icon: "hammer", status: appState.jenkinsAuthStatus,
                         settingsTab: "jenkins", canRetry: false) { goToSettings("jenkins") }
                authCard(service: "Grafana", icon: "chart.line.uptrend.xyaxis", status: appState.grafanaAuthStatus,
                         settingsTab: "grafana", canRetry: false) { goToSettings("grafana") }
            }
            .padding(.top, 12)
            .frame(maxWidth: 700)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func authCard(service: String, icon: String, status: AuthStatus,
                          settingsTab: String, canRetry: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if status.isOK {
                // Already connected — re-check
                action()
            } else if status == .notConfigured {
                // Not configured — go to settings
                goToSettings(settingsTab)
            } else {
                // Expired/error — retry
                action()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(status.color)
                    Text(service)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if case .checking = status {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Circle()
                            .fill(status.color)
                            .frame(width: 10, height: 10)
                    }
                }
                Text(actionLabel(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(status.color.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func actionLabel(_ status: AuthStatus) -> String {
        switch status {
        case .authenticated(let detail): return "Connected: \(detail)\nClick to re-check"
        case .expired: return "Session expired — click to retry"
        case .error: return "Connection failed — click to retry"
        case .notConfigured: return "Not configured — click to set up"
        case .checking: return "Checking..."
        case .unknown: return "Click to check connection"
        }
    }

    // MARK: - Retry actions

    private func goToSettings(_ tab: String) {
        appState.selectedReport = nil
        appState.showSettings = true
    }

    private func retryAWS() {
        appState.awsAuthStatus = .checking
        Task {
            do {
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
            } catch is AWSAuthError {
                await MainActor.run { appState.awsAuthStatus = .expired }
            } catch {
                await MainActor.run { appState.awsAuthStatus = .error(error.localizedDescription) }
            }
        }
    }

    private func retryJira() {
        guard appState.isJiraConfigured else { goToSettings("jira"); return }
        appState.jiraAuthStatus = .checking
        let svc = JiraService()
        Task {
            do {
                let name = try await svc.checkAuth(baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: appState.jiraAPIToken)
                await MainActor.run { appState.jiraAuthStatus = .authenticated(detail: name) }
            } catch {
                await MainActor.run { appState.jiraAuthStatus = .error(error.localizedDescription) }
            }
        }
    }

    private func retryConfluence() {
        let token = appState.confluenceAPIToken
        guard !token.isEmpty && !appState.jiraEmail.isEmpty else { goToSettings("confluence"); return }
        appState.confluenceAuthStatus = .checking
        let svc = ConfluenceService()
        Task {
            do {
                let name = try await svc.checkAuth(baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: token)
                await MainActor.run { appState.confluenceAuthStatus = .authenticated(detail: name) }
            } catch {
                await MainActor.run { appState.confluenceAuthStatus = .error(error.localizedDescription) }
            }
        }
    }

    private func retryBitbucket() {
        let token = appState.bitbucketAPIToken
        guard !token.isEmpty && !appState.jiraEmail.isEmpty else { goToSettings("bitbucket"); return }
        appState.bitbucketAuthStatus = .checking
        let svc = BitbucketService()
        Task {
            do {
                let name = try await svc.checkAuth(email: appState.jiraEmail, apiToken: token)
                await MainActor.run { appState.bitbucketAuthStatus = .authenticated(detail: name) }
            } catch {
                await MainActor.run { appState.bitbucketAuthStatus = .error(error.localizedDescription) }
            }
        }
    }

    private func retryGitHub() {
        let token = appState.githubToken
        guard !token.isEmpty else { goToSettings("github"); return }
        appState.githubAuthStatus = .checking
        let svc = GitHubService()
        Task {
            do {
                let name = try await svc.checkAuth(token: token)
                await MainActor.run { appState.githubAuthStatus = .authenticated(detail: name) }
            } catch {
                await MainActor.run { appState.githubAuthStatus = .error(error.localizedDescription) }
            }
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

import SwiftUI

// MARK: - Service API Guide Definition

enum ServiceAPIGuide: Identifiable {
    var id: String { title }

    case jira
    case github
    case jenkins(jenkinsURL: String)
    case grafana(grafanaURL: String)
    case bitbucket
    case google

    var title: String {
        switch self {
        case .jira: return "Jira & Confluence"
        case .github: return "GitHub"
        case .jenkins: return "Jenkins"
        case .grafana: return "Grafana"
        case .bitbucket: return "Bitbucket"
        case .google: return "Google Workspace"
        }
    }

    var icon: String {
        switch self {
        case .jira: return "ticket"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .jenkins: return "hammer"
        case .grafana: return "chart.line.uptrend.xyaxis"
        case .bitbucket: return "externaldrive.connected.to.line.below"
        case .google: return "envelope"
        }
    }

    var tokenLabel: String {
        switch self {
        case .jira: return "Atlassian API Token"
        case .github: return "Personal Access Token"
        case .jenkins: return "Jenkins API Token"
        case .grafana: return "Service Account Token"
        case .bitbucket: return "Bitbucket API Token"
        case .google: return ""
        }
    }

    var tokenPlaceholder: String {
        switch self {
        case .jira: return "Your Atlassian API token…"
        case .github: return "ghp_..."
        case .jenkins: return "Your Jenkins API token"
        case .grafana: return "glsa_..."
        case .bitbucket: return "Your Bitbucket-scoped API token…"
        case .google: return ""
        }
    }

    var isOAuth: Bool {
        if case .google = self { return true }
        return false
    }

    struct GuideStep {
        let title: String
        let description: String
        let linkURL: URL?
        let linkLabel: String?
        let checkboxItems: [String]
    }

    var steps: [GuideStep] {
        switch self {
        case .jira:
            return [
                GuideStep(title: "Open your Atlassian API token page", description: "",
                          linkURL: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens"),
                          linkLabel: "Open Atlassian → API Tokens", checkboxItems: []),
                GuideStep(title: "Click \"Create API token\"",
                          description: "Label: \"Boomi SRE App\" (or anything you'll remember). Click \"Create\".",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Copy the token and paste it below",
                          description: "This same token works for both Jira AND Confluence — you only need one.\nYour token inherits your Atlassian account permissions. No special scopes needed.",
                          linkURL: nil, linkLabel: nil, checkboxItems: [])
            ]
        case .github:
            return [
                GuideStep(title: "Open GitHub token settings", description: "",
                          linkURL: URL(string: "https://github.com/settings/tokens"),
                          linkLabel: "Open GitHub → Settings → Tokens", checkboxItems: []),
                GuideStep(title: "Click \"Generate new token (classic)\"",
                          description: "Note: \"Boomi SRE App\"\nExpiration: 90 days (or No expiration for convenience)",
                          linkURL: nil, linkLabel: nil,
                          checkboxItems: ["repo — Full control of private repositories",
                                         "read:org — Read org and team membership",
                                         "workflow — Update GitHub Actions workflows",
                                         "read:user — Read user profile data"]),
                GuideStep(title: "Generate, copy, and paste below",
                          description: "After creating the token, if your org requires SSO, click \"Configure SSO\" next to it and authorize your organization (Mashery-Boomi).",
                          linkURL: nil, linkLabel: nil, checkboxItems: [])
            ]
        case .jenkins(let jenkinsURL):
            let normalized = jenkinsURL.hasSuffix("/") ? jenkinsURL : jenkinsURL + "/"
            let configURL = jenkinsURL.isEmpty ? nil : URL(string: normalized + "me/configure")
            return [
                GuideStep(title: "Open your Jenkins user settings",
                          description: jenkinsURL.isEmpty ? "Enter your Jenkins URL in settings first, then this link will work." : "",
                          linkURL: configURL,
                          linkLabel: configURL != nil ? "Open Jenkins → Configure" : nil,
                          checkboxItems: []),
                GuideStep(title: "Scroll to \"API Token\" section",
                          description: "Click \"Add new Token\"\nName: \"Boomi SRE App\"\nClick \"Generate\"",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Copy the token and paste below", description: "",
                          linkURL: nil, linkLabel: nil, checkboxItems: [])
            ]
        case .grafana(let grafanaURL):
            let normalized = grafanaURL.hasSuffix("/") ? grafanaURL : grafanaURL + "/"
            let saURL = grafanaURL.isEmpty ? nil : URL(string: normalized + "org/serviceaccounts")
            return [
                GuideStep(title: "Open Grafana Service Accounts",
                          description: grafanaURL.isEmpty ? "Enter your Grafana URL in settings first." : "",
                          linkURL: saURL,
                          linkLabel: saURL != nil ? "Open Grafana → Service Accounts" : nil,
                          checkboxItems: []),
                GuideStep(title: "Create a Service Account",
                          description: "Click \"Add service account\"\nDisplay name: \"Boomi SRE App\"\nRole: \"Viewer\" (reads dashboards and alerts)\nClick \"Create\"",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Add a token to the service account",
                          description: "Click \"Add service account token\"\nDisplay name: \"boomi-sre\"\nClick \"Generate token\"",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Copy the token and paste below",
                          description: "A Viewer-role token reads dashboards, panels, and alerts. Use Editor role if you also want to create annotations.",
                          linkURL: nil, linkLabel: nil, checkboxItems: [])
            ]
        case .bitbucket:
            return [
                GuideStep(
                    title: "Open your Atlassian Account security settings",
                    description: "Bitbucket App Passwords are deprecated (Sept 2025, disabled June 2026). Bitbucket now uses scoped API tokens — separate from your Jira/Confluence token.",
                    linkURL: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens"),
                    linkLabel: "Open Atlassian → API Tokens", checkboxItems: []),
                GuideStep(
                    title: "Click \"Create API token with scopes\"",
                    description: "Name: \"Boomi SRE App\"\nSet an expiry (up to 365 days)\nClick \"Next\"",
                    linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(
                    title: "Select \"Bitbucket\" as the target application, then choose scopes",
                    description: "Read-only (browsing repos, PRs, branches, pipelines):",
                    linkURL: nil, linkLabel: nil,
                    checkboxItems: ["read:repository:bitbucket  — View your repositories",
                                    "read:pullrequest:bitbucket — View your pull requests",
                                    "read:pipeline:bitbucket    — View your pipelines",
                                    "read:workspace:bitbucket   — View your workspaces",
                                    "read:project:bitbucket     — View your projects"]),
                GuideStep(
                    title: "Click \"Create\" — copy the token immediately",
                    description: "The token is shown ONCE and cannot be retrieved later. Copy it immediately and paste below.\n\nOptional — add Write scopes for merge/comment/trigger:\n• write:pullrequest:bitbucket\n• write:pipeline:bitbucket\n• write:repository:bitbucket",
                    linkURL: nil, linkLabel: nil, checkboxItems: [])
            ]
        case .google:
            return [
                GuideStep(title: "Try Auto-discover first",
                          description: "If you've already set up Google Workspace MCP credentials, click Auto-discover below to import them automatically. This is the easiest option.",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Authenticate via Google Workspace MCP server",
                          description: "The Google Workspace MCP server handles OAuth for you. Run it once to authenticate — it will create a credential JSON with your refresh token and scopes.",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Import credentials into the app",
                          description: "Click \"Import from MCP\" in Settings → Google → Credentials to copy the credential file into ~/.boomi-sre/credentials/.\n\nOr manually place a credential JSON (with refresh_token) in ~/.boomi-sre/credentials/ named as your email (e.g. adam@boomi.com.json).",
                          linkURL: nil, linkLabel: nil, checkboxItems: []),
                GuideStep(title: "Missing scopes? Re-authenticate the MCP server",
                          description: "If Gmail, Calendar, or Chat scopes are missing, delete the credential file and re-authenticate the Google Workspace MCP server with the needed scopes enabled. Then import again.",
                          linkURL: nil, linkLabel: nil, checkboxItems: [])
            ]
        }
    }

    var notes: [String] {
        switch self {
        case .jira:
            return ["This same token works for both Jira AND Confluence — saving here updates both."]
        case .github:
            return ["If your GitHub org requires SSO authorization, after creating the token click \"Configure SSO\" and authorize the Mashery-Boomi org."]
        case .jenkins:
            return ["Your Jenkins URL is typically https://jenkins-master.mashspud.com"]
        case .grafana:
            return ["Viewer-role token is sufficient for dashboards and alerts. Use Editor if you also want to create annotations."]
        case .bitbucket:
            return ["Bitbucket API tokens are SEPARATE from Jira/Confluence tokens. Create a new one at id.atlassian.com and select Bitbucket as the target app with the required scopes. The token is shown only once — copy it before closing."]
        case .google:
            return ["Gmail and Calendar AI features require OAuth credentials."]
        }
    }
}

// MARK: - API Key Guide View

struct APIKeyGuideView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let guide: ServiceAPIGuide

    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var testResult: GuideTestResult = .idle

    enum GuideTestResult {
        case idle, checking, success(String), failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: guide.icon).foregroundStyle(Color.accentColor)
                Text("Set Up \(guide.title)").font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Steps
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                        stepView(number: i + 1, step: step)
                    }

                    // Notes
                    if !guide.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(guide.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.blue).font(.caption)
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.blue.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.blue.opacity(0.15)))
                    }

                    Divider()

                    // Token input or OAuth flow
                    if guide.isOAuth {
                        oauthSection
                    } else {
                        tokenSection
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Link("Need help? Open GitHub Issues",
                     destination: URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE/issues")!)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear { loadExistingToken() }
    }

    // MARK: - Step View

    private func stepView(number: Int, step: ServiceAPIGuide.GuideStep) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 28, height: 28)
                Text("\(number)").font(.callout.bold()).foregroundStyle(.white)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title).font(.callout.bold())

                if !step.description.isEmpty {
                    Text(step.description).font(.callout).foregroundStyle(.secondary)
                }

                if let linkURL = step.linkURL, let linkLabel = step.linkLabel {
                    Button {
                        NSWorkspace.shared.open(linkURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text(linkLabel)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if !step.checkboxItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(step.checkboxItems, id: \.self) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.square.fill")
                                    .foregroundStyle(Color.accentColor).font(.callout)
                                Text(item).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                }
            }
        }
    }

    // MARK: - Token Section

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.tokenLabel).font(.callout.bold())

            HStack(spacing: 8) {
                SecureField(guide.tokenPlaceholder, text: $tokenField)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        tokenField = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            // Show last 4 chars if already saved
            if tokenField.isEmpty, !existingToken.isEmpty {
                Text("Current: ••••\(existingToken.suffix(4))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await testAndSave() }
                } label: {
                    if isTesting {
                        HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Testing…") }
                    } else {
                        Label("Test & Save", systemImage: "checkmark.shield")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenField.isEmpty || isTesting)

                switch testResult {
                case .idle: EmptyView()
                case .checking: EmptyView()
                case .success(let name):
                    Label("Connected as \(name)", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .success = testResult {
                Text("Token saved successfully. You can close this guide.")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }

    // MARK: - OAuth Section

    private var oauthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Option A: Auto-discover (Recommended)").font(.callout.bold())
            Text("If you have Google Workspace MCP credentials, click below to import them automatically.")
                .font(.callout).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    appState.importDiscoveredCredentials()
                    if appState.googleCredentials != nil {
                        testResult = .success(appState.googleEmail.isEmpty ? "Credentials imported" : appState.googleEmail)
                    } else {
                        testResult = .failure("No credentials found. Import from MCP or place in ~/.boomi-sre/credentials/")
                    }
                } label: {
                    Label("Auto-discover", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)

                switch testResult {
                case .success(let name):
                    Label(name, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                default: EmptyView()
                }
            }

            Divider()

            Text("Option B: Manual placement")
                .font(.callout.bold())
            Text("Place a credential JSON (with refresh_token) in:")
                .font(.callout).foregroundStyle(.secondary)
            Text("~/.boomi-sre/credentials/<your-email>.json")
                .font(.caption.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            Text("Then click Auto-discover above to import it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }

    // MARK: - Helpers

    private var existingToken: String {
        switch guide {
        case .jira: return appState.jiraAPIToken
        case .github: return appState.githubToken
        case .jenkins: return appState.jenkinsToken
        case .grafana: return appState.grafanaToken
        case .bitbucket: return appState.bitbucketAPIToken
        case .google: return ""
        }
    }

    private func loadExistingToken() {
        // Don't pre-fill for security; just show the hint
    }

    private func testAndSave() async {
        guard !tokenField.isEmpty else { return }
        isTesting = true
        testResult = .checking
        saveToken()
        do {
            let name = try await validateToken()
            testResult = .success(name.isEmpty ? "OK" : name)
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }

    private func saveToken() {
        let t = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        switch guide {
        case .jira:
            appState.jiraAPIToken = t
            appState.confluenceAPIToken = t  // same Atlassian token
        case .github: appState.githubToken = t
        case .jenkins: appState.jenkinsToken = t
        case .grafana: appState.grafanaToken = t
        case .bitbucket: appState.bitbucketAPIToken = t
        case .google: break
        }
    }

    private func validateToken() async throws -> String {
        let t = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        switch guide {
        case .jira:
            return try await JiraService().checkAuth(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: t)
        case .github:
            return try await GitHubService().checkAuth(token: t)
        case .jenkins:
            let url = appState.jenkinsURL.hasSuffix("/") ? appState.jenkinsURL : appState.jenkinsURL + "/"
            guard let testURL = URL(string: "\(url)api/json") else { throw URLError(.badURL) }
            var request = URLRequest(url: testURL, timeoutInterval: 15)
            let creds = "\(appState.jenkinsUsername):\(t)"
            if let data = creds.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
            let (_, response) = try await ZscalerTrustURLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw NSError(domain: "Jenkins", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) — check credentials"])
            }
            return appState.jenkinsUsername.isEmpty ? "Connected" : appState.jenkinsUsername
        case .grafana:
            return try await GrafanaService().checkAuth(baseURL: appState.grafanaURL, token: t)
        case .bitbucket:
            return try await BitbucketService().checkAuth(email: appState.bitbucketAuthUser, apiToken: t)
        case .google:
            return ""
        }
    }
}

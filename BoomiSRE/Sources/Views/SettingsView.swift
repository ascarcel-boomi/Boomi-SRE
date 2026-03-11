import SwiftUI

/// Inline settings panel displayed in the main content area.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = "aws"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 0) {
                // Left tab bar
                VStack(alignment: .leading, spacing: 2) {
                    settingsTab("aws", label: "AWS SSO", icon: "cloud", status: appState.awsAuthStatus)
                    settingsTab("jira", label: "Jira", icon: "ticket", status: appState.jiraAuthStatus)
                    settingsTab("confluence", label: "Confluence", icon: "book.closed", status: appState.confluenceAuthStatus)
                    settingsTab("bitbucket", label: "Bitbucket", icon: "externaldrive.connected.to.line.below", status: appState.bitbucketAuthStatus)
                    settingsTab("github", label: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: appState.githubAuthStatus)
                    Spacer()
                }
                .frame(width: 180)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Right content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "aws": AWSSettingsContent()
                        case "jira": JiraSettingsContent()
                        case "confluence": ConfluenceSettingsContent()
                        case "bitbucket": BitbucketSettingsContent()
                        case "github": GitHubSettingsContent()
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsTab(_ id: String, label: String, icon: String, status: AuthStatus?) -> some View {
        Button {
            selectedTab = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                    .font(.body)
                Spacer()
                if let status = status {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == id ? Color.accentColor.opacity(0.15) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable field components

struct SettingsSection: View {
    let title: String
    let content: AnyView

    init(_ title: String, @ViewBuilder content: () -> some View) {
        self.title = title
        self.content = AnyView(content())
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isSecure {
                SecureField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct StatusBadge: View {
    let status: AuthStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(status.color).frame(width: 10, height: 10)
            Text(status.label)
                .font(.callout)
                .foregroundStyle(status.color)
        }
    }
}

struct TokenStatus: View {
    let token: String
    let name: String

    var body: some View {
        if token.isEmpty {
            Label("No \(name) token saved", systemImage: "xmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Label("\(name) token saved (\(token.count) chars)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        }
    }
}

// MARK: - AWS

struct AWSSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var profiles: [String] = []
    @State private var isLoggingIn = false

    private let awsAuth = AWSAuthService()

    var body: some View {
        SettingsSection("SSO Profile") {
            Picker("Profile", selection: $appState.awsSSOProfile) {
                ForEach(profiles, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 400)
            .onAppear { profiles = awsAuth.listProfiles() }
            .onChange(of: appState.awsSSOProfile) { appState.saveConfig() }
        }

        SettingsSection("Authentication") {
            StatusBadge(status: appState.awsAuthStatus)

            HStack(spacing: 12) {
                Button("Login with SSO") { loginSSO() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoggingIn)
                Button("Check Status") { checkAWS() }
                    .disabled(isLoggingIn)
                if isLoggingIn { ProgressView().scaleEffect(0.7) }
            }

            Text("SSO login opens your browser for device authorization. After approving, click \"Check Status\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loginSSO() {
        isLoggingIn = true; appState.awsAuthStatus = .checking
        Task {
            do {
                _ = try await awsAuth.login(profile: appState.awsSSOProfile)
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail); isLoggingIn = false }
            } catch {
                await MainActor.run { appState.awsAuthStatus = .error(error.localizedDescription); isLoggingIn = false }
            }
        }
    }

    private func checkAWS() {
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
}

// MARK: - Jira

struct JiraSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var projectKeysField = ""
    @State private var isTesting = false
    @State private var saved = false

    private let jiraService = JiraService()

    var body: some View {
        SettingsSection("Connection") {
            FieldRow(label: "Base URL", text: $appState.jiraBaseURL)
            FieldRow(label: "Email", text: $appState.jiraEmail)
            FieldRow(label: "API Token", text: $tokenField, isSecure: true)
            Link("Get a token from Atlassian",
                 destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
        }

        SettingsSection("Projects") {
            FieldRow(label: "Project keys (comma-separated)", text: $projectKeysField,
                     placeholder: "CAMSRE, SRE")
        }

        SettingsSection("Authentication") {
            StatusBadge(status: appState.jiraAuthStatus)

            HStack(spacing: 12) {
                Button("Test Connection") { testJira() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                Button("Save") { saveJira() }
                if isTesting { ProgressView().scaleEffect(0.7) }
                if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
            }
        }
    }

    private func saveJira() {
        appState.jiraAPIToken = tokenField
        appState.jiraProjectKeys = projectKeysField
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        appState.saveConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testJira() {
        isTesting = true; appState.jiraAuthStatus = .checking
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, tokenField)
        Task {
            do {
                let name = try await jiraService.checkAuth(baseURL: baseURL, email: email, apiToken: token)
                await MainActor.run { appState.jiraAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.jiraAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Confluence

struct ConfluenceSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false

    private let service = ConfluenceService()

    var body: some View {
        SettingsSection("Connection") {
            Text("Confluence uses the same base URL and email as Jira.")
                .font(.caption).foregroundStyle(.secondary)
            FieldRow(label: "Base URL (from Jira)", text: .constant(appState.jiraBaseURL))
            FieldRow(label: "Email (from Jira)", text: .constant(appState.jiraEmail))
            FieldRow(label: "Confluence API Token", text: $tokenField, isSecure: true)
            Link("Get a token from Atlassian",
                 destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
        }

        SettingsSection("Authentication") {
            StatusBadge(status: appState.confluenceAuthStatus)

            HStack(spacing: 12) {
                Button("Test Connection") { testConnection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                Button("Save") { saveToken() }
                if isTesting { ProgressView().scaleEffect(0.7) }
                if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
            }
        }
    }

    private func saveToken() {
        appState.confluenceAPIToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.confluenceAuthStatus = .checking
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, tokenField)
        Task {
            do {
                let name = try await service.checkAuth(baseURL: baseURL, email: email, apiToken: token)
                await MainActor.run { appState.confluenceAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.confluenceAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Bitbucket

struct BitbucketSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false

    private let service = BitbucketService()

    var body: some View {
        SettingsSection("Connection") {
            Text("Bitbucket workspace: boomii")
                .font(.caption).foregroundStyle(.secondary)
            FieldRow(label: "Email (from Jira)", text: .constant(appState.jiraEmail))
            FieldRow(label: "Bitbucket API Token", text: $tokenField, isSecure: true)
            Link("Manage Atlassian API tokens",
                 destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
        }

        SettingsSection("Authentication") {
            StatusBadge(status: appState.bitbucketAuthStatus)

            HStack(spacing: 12) {
                Button("Test Connection") { testConnection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                Button("Save") { saveToken() }
                if isTesting { ProgressView().scaleEffect(0.7) }
                if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
            }
        }
    }

    private func saveToken() {
        appState.bitbucketAPIToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.bitbucketAuthStatus = .checking
        let (email, token) = (appState.jiraEmail, tokenField)
        Task {
            do {
                let name = try await service.checkAuth(email: email, apiToken: token)
                await MainActor.run { appState.bitbucketAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.bitbucketAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - GitHub

struct GitHubSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false

    private let service = GitHubService()

    var body: some View {
        SettingsSection("Connection") {
            FieldRow(label: "Personal Access Token", text: $tokenField, isSecure: true,
                     placeholder: "ghp_...")
            Link("Create a token at github.com",
                 destination: URL(string: "https://github.com/settings/tokens")!)
                .font(.caption)
            Text("Needs repo and read:org scopes for Mashery-Boomi org access.")
                .font(.caption).foregroundStyle(.secondary)
        }

        SettingsSection("Authentication") {
            StatusBadge(status: appState.githubAuthStatus)

            HStack(spacing: 12) {
                Button("Test Connection") { testConnection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || tokenField.isEmpty)
                Button("Save") { saveToken() }
                if isTesting { ProgressView().scaleEffect(0.7) }
                if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
            }
        }
    }

    private func saveToken() {
        appState.githubToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.githubAuthStatus = .checking
        let token = tokenField
        Task {
            do {
                let name = try await service.checkAuth(token: token)
                await MainActor.run { appState.githubAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.githubAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

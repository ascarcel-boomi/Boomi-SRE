import SwiftUI

/// Inline settings panel displayed in the main content area (not a popup).
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
                // Tab sidebar
                VStack(alignment: .leading, spacing: 2) {
                    settingsTab("aws", label: "AWS SSO", icon: "cloud", status: appState.awsAuthStatus)
                    settingsTab("jira", label: "Jira", icon: "ticket", status: appState.jiraAuthStatus)
                    settingsTab("confluence", label: "Confluence", icon: "book.closed", status: nil)
                    settingsTab("bitbucket", label: "Bitbucket", icon: "externaldrive.connected.to.line.below", status: nil)
                    settingsTab("github", label: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: nil)
                    Spacer()
                }
                .frame(width: 180)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Tab content
                ScrollView {
                    switch selectedTab {
                    case "aws": AWSSettingsSection()
                    case "jira": JiraSettingsSection()
                    case "confluence": ConfluenceSettingsSection()
                    case "bitbucket": BitbucketSettingsSection()
                    case "github": GitHubSettingsSection()
                    default: EmptyView()
                    }
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

// MARK: - AWS

struct AWSSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var profiles: [String] = []
    @State private var isLoggingIn = false

    private let awsAuth = AWSAuthService()

    var body: some View {
        Form {
            Section("SSO Profile") {
                Picker("Profile", selection: $appState.awsSSOProfile) {
                    ForEach(profiles, id: \.self) { Text($0).tag($0) }
                }
                .onAppear { profiles = awsAuth.listProfiles() }
                .onChange(of: appState.awsSSOProfile) { appState.saveConfig() }
            }

            Section("Authentication") {
                statusRow(appState.awsAuthStatus)

                HStack {
                    Button("Login with SSO") { loginSSO() }
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
        .formStyle(.grouped)
        .padding(20)
        .onAppear { checkAWS() }
    }

    private func loginSSO() {
        isLoggingIn = true
        appState.awsAuthStatus = .checking
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

struct JiraSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var projectKeysField = ""
    @State private var isTesting = false
    @State private var saved = false

    private let jiraService = JiraService()

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Base URL", text: $appState.jiraBaseURL)
                TextField("Email", text: $appState.jiraEmail)
                SecureField("API Token", text: $tokenField)
                Link("Get a token from Atlassian",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
            }

            Section("Projects") {
                TextField("Project keys (comma-separated)", text: $projectKeysField)
                Text("e.g. CAMSRE, SRE")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Section("Authentication") {
                statusRow(appState.jiraAuthStatus)
                HStack {
                    Button("Test Connection") { testJira() }
                        .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                    Button("Save") { saveJira() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            tokenField = appState.jiraAPIToken
            projectKeysField = appState.jiraProjectKeys.joined(separator: ", ")
            if appState.isJiraConfigured { testJira() }
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

struct ConfluenceSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Connection") {
                Text("Confluence shares the same base URL and email as Jira.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Confluence API Token", text: $tokenField)
                Link("Get a token from Atlassian",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
            }
            Section {
                HStack {
                    Button("Save") { saveToken() }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
                if !appState.confluenceAPIToken.isEmpty {
                    Label("Token saved (\(appState.confluenceAPIToken.count) chars)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { tokenField = appState.confluenceAPIToken }
    }

    private func saveToken() {
        appState.confluenceAPIToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}

// MARK: - Bitbucket

struct BitbucketSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Connection") {
                Text("Bitbucket workspace: boomii")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Bitbucket API Token", text: $tokenField)
                Link("Manage Atlassian API tokens",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
            }
            Section {
                HStack {
                    Button("Save") { saveToken() }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
                if !appState.bitbucketAPIToken.isEmpty {
                    Label("Token saved (\(appState.bitbucketAPIToken.count) chars)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { tokenField = appState.bitbucketAPIToken }
    }

    private func saveToken() {
        appState.bitbucketAPIToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}

// MARK: - GitHub

struct GitHubSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Connection") {
                SecureField("GitHub Personal Access Token", text: $tokenField)
                Link("Create a token at github.com",
                     destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.caption)
                Text("Needs repo and read:org scopes for Mashery-Boomi org access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Save") { saveToken() }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
                if !appState.githubToken.isEmpty {
                    Label("Token saved (\(appState.githubToken.count) chars)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { tokenField = appState.githubToken }
    }

    private func saveToken() {
        appState.githubToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}

// MARK: - Shared

func statusRow(_ status: AuthStatus) -> some View {
    HStack(spacing: 8) {
        Circle().fill(status.color).frame(width: 10, height: 10)
        Text(status.label).font(.callout).foregroundStyle(status.color)
        Spacer()
    }
}

import SwiftUI

/// Inline settings panel displayed in the main content area.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = "preferences"
    @State private var discoveryResult: String?
    @State private var discoveryIsError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with auto-discover button
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button {
                    runDiscovery()
                } label: {
                    Label("Auto-discover Credentials", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Discovery result banner
            if let result = discoveryResult {
                HStack(spacing: 8) {
                    Image(systemName: discoveryIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    Text(result)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button { discoveryResult = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(discoveryIsError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .foregroundStyle(discoveryIsError ? .red : .green)
            }

            Divider()

            HStack(spacing: 0) {
                // Left tab bar
                VStack(alignment: .leading, spacing: 2) {
                    settingsTab("preferences", label: "Preferences", icon: "star", status: nil)
                    Divider().padding(.vertical, 4)
                    settingsTab("aws", label: "AWS SSO", icon: "cloud", status: appState.awsAuthStatus)
                    settingsTab("jira", label: "Jira", icon: "ticket", status: appState.jiraAuthStatus)
                    settingsTab("confluence", label: "Confluence", icon: "book.closed", status: appState.confluenceAuthStatus)
                    settingsTab("bitbucket", label: "Bitbucket", icon: "externaldrive.connected.to.line.below", status: appState.bitbucketAuthStatus)
                    settingsTab("github", label: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: appState.githubAuthStatus)
                    settingsTab("jenkins", label: "Jenkins", icon: "hammer", status: appState.jenkinsAuthStatus)
                    settingsTab("grafana", label: "Grafana", icon: "chart.line.uptrend.xyaxis", status: appState.grafanaAuthStatus)
                    settingsTab("google", label: "Google", icon: "envelope", status: appState.googleAuthStatus)
                    Spacer()
                }
                .frame(width: 180)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Right content — .id forces fresh @State when switching tabs
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "preferences": PreferencesSettingsContent()
                        case "aws": AWSSettingsContent()
                        case "jira": JiraSettingsContent()
                        case "confluence": ConfluenceSettingsContent()
                        case "bitbucket": BitbucketSettingsContent()
                        case "github": GitHubSettingsContent()
                        case "jenkins": JenkinsSettingsContent()
                        case "grafana": GrafanaSettingsContent()
                        case "google": GoogleSettingsContent()
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(selectedTab)
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

    private func runDiscovery() {
        let creds = CredentialDiscovery.discover()
        let count = CredentialDiscovery.discoveredCount(creds)

        if count == 0 && creds.atlassianEmail == nil {
            discoveryResult = "No credentials found in ~/.kiro/, ~/.amazonq/, ~/.aws/, or ~/.config/"
            discoveryIsError = true
            return
        }

        appState.importDiscoveredCredentials()

        discoveryResult = "Imported \(creds.sources.count) items: \(creds.sources.joined(separator: ", "))"
        discoveryIsError = false

        appState.checkAllServices()
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
                .textSelection(.enabled)
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

// MARK: - Preferences / Favorites

struct PreferencesSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var awsProfiles: [AWSProfile] = []
    @State private var jiraProjects: [JiraProjectSummary] = []
    @State private var confluenceSpaces: [ConfluenceSpaceSummary] = []
    @State private var isLoadingJira = false
    @State private var isLoadingConfluence = false
    @State private var jiraError: String?
    @State private var confluenceError: String?

    private let awsAuth = AWSAuthService()
    private let jiraService = JiraService()
    private let confluenceService = ConfluenceService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mark your most-used accounts, projects, and spaces as favorites. Favorites appear in the menu bar for quick access.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Favorite AWS Profiles
            SettingsSection("Favorite AWS Profiles") {
                if awsProfiles.isEmpty {
                    Text("No AWS profiles found in ~/.aws/config or ~/.aws/credentials")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Select profiles to appear in the Favorites menu and report pickers.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(awsProfiles) { profile in
                            Toggle(isOn: awsProfileBinding(profile.name)) {
                                HStack(spacing: 8) {
                                    Text(profile.displayName)
                                        .font(.body)
                                    if profile.source == .sso {
                                        Text("SSO")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Text("Portal")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }

            // Favorite Jira Projects
            SettingsSection("Favorite Jira Projects") {
                if !appState.isJiraConfigured {
                    Text("Configure Jira credentials first.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if isLoadingJira {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading projects...")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error = jiraError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { fetchJiraProjects() }
                } else if jiraProjects.isEmpty {
                    HStack(spacing: 8) {
                        Text("No projects loaded.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Fetch Projects") { fetchJiraProjects() }
                    }
                } else {
                    Text("Select projects to filter boards and dashboards.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(jiraProjects) { project in
                            Toggle(isOn: jiraProjectBinding(project.key)) {
                                HStack(spacing: 8) {
                                    Text(project.key)
                                        .font(.body.monospaced())
                                        .frame(width: 80, alignment: .leading)
                                    Text(project.name)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }

            // Favorite Confluence Spaces
            SettingsSection("Favorite Confluence Spaces") {
                if appState.confluenceAPIToken.isEmpty {
                    Text("Configure Confluence credentials first.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if isLoadingConfluence {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading spaces...")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error = confluenceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { fetchConfluenceSpaces() }
                } else if confluenceSpaces.isEmpty {
                    HStack(spacing: 8) {
                        Text("No spaces loaded.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Fetch Spaces") { fetchConfluenceSpaces() }
                    }
                } else {
                    Text("Select spaces for future Confluence browsing.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(confluenceSpaces) { space in
                            Toggle(isOn: confluenceSpaceBinding(space.key)) {
                                HStack(spacing: 8) {
                                    Text(space.key)
                                        .font(.body.monospaced())
                                        .frame(width: 80, alignment: .leading)
                                    Text(space.name)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadAWSProfiles()
            if appState.isJiraConfigured { fetchJiraProjects() }
            if !appState.confluenceAPIToken.isEmpty { fetchConfluenceSpaces() }
        }
    }

    // MARK: - Bindings

    private func awsProfileBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { appState.favoriteAWSProfiles.contains(name) },
            set: { isOn in
                if isOn {
                    appState.favoriteAWSProfiles.append(name)
                } else {
                    appState.favoriteAWSProfiles.removeAll { $0 == name }
                }
                appState.saveConfig()
            }
        )
    }

    private func jiraProjectBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { appState.favoriteJiraProjects.contains(key) },
            set: { isOn in
                if isOn {
                    appState.favoriteJiraProjects.append(key)
                } else {
                    appState.favoriteJiraProjects.removeAll { $0 == key }
                }
                appState.saveConfig()
            }
        )
    }

    private func confluenceSpaceBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { appState.favoriteConfluenceSpaces.contains(key) },
            set: { isOn in
                if isOn {
                    appState.favoriteConfluenceSpaces.append(key)
                } else {
                    appState.favoriteConfluenceSpaces.removeAll { $0 == key }
                }
                appState.saveConfig()
            }
        )
    }

    // MARK: - Data Loading

    private func loadAWSProfiles() {
        var list = awsAuth.listProfiles()
        for i in list.indices {
            if !list[i].accountId.isEmpty,
               let name = appState.awsAccountNames[list[i].accountId] {
                list[i].friendlyName = name
            }
        }
        awsProfiles = list
    }

    private func fetchJiraProjects() {
        isLoadingJira = true
        jiraError = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)
        Task {
            do {
                let projects = try await jiraService.fetchProjects(baseURL: baseURL, email: email, apiToken: token)
                await MainActor.run {
                    jiraProjects = projects
                    isLoadingJira = false
                    // Seed defaults if favorites list is empty
                    if appState.favoriteJiraProjects.isEmpty {
                        let defaults = appState.jiraProjectKeys
                        appState.favoriteJiraProjects = projects.map(\.key).filter { defaults.contains($0) }
                        appState.saveConfig()
                    }
                }
            } catch {
                await MainActor.run {
                    jiraError = error.localizedDescription
                    isLoadingJira = false
                }
            }
        }
    }

    private func fetchConfluenceSpaces() {
        isLoadingConfluence = true
        confluenceError = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.confluenceAPIToken)
        Task {
            do {
                let spaces = try await confluenceService.fetchSpaces(baseURL: baseURL, email: email, apiToken: token)
                await MainActor.run {
                    confluenceSpaces = spaces
                    isLoadingConfluence = false
                }
            } catch {
                await MainActor.run {
                    confluenceError = error.localizedDescription
                    isLoadingConfluence = false
                }
            }
        }
    }
}

/// Lightweight model for Jira project list in Preferences.
struct JiraProjectSummary: Identifiable, Codable {
    let id: String
    let key: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, key, name
    }
}

/// Lightweight model for Confluence space list in Preferences.
struct ConfluenceSpaceSummary: Identifiable, Codable {
    let id: String  // actually "id" from API or we derive from key
    let key: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, key, name
    }
}

// MARK: - AWS

struct AWSSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var profiles: [AWSProfile] = []
    @State private var isLoggingIn = false
    @State private var pasteText = ""
    @State private var pasteMessage = ""
    @State private var pasteIsError = false

    private let awsAuth = AWSAuthService()

    private var selectedProfile: AWSProfile? {
        profiles.first { $0.name == appState.awsSSOProfile }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Active Profile") {
                Picker("Profile", selection: $appState.awsSSOProfile) {
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(profile.name)
                    }
                }
                .frame(maxWidth: 500)
                .onAppear { profiles = loadProfilesWithNames() }
                .onChange(of: appState.awsSSOProfile) { appState.saveConfig() }

                Text("Profiles are loaded from ~/.aws/config (SSO) and ~/.aws/credentials (portal).")
                    .font(.caption).foregroundStyle(.secondary)

                Button("Refresh Profiles") {
                    profiles = loadProfilesWithNames()
                }
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.awsAuthStatus)

                HStack(spacing: 12) {
                    if selectedProfile?.source == .sso {
                        Button("Login with SSO") { loginSSO() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoggingIn)
                    }
                    Button("Check Status") { checkAWS() }
                        .disabled(isLoggingIn)
                    if isLoggingIn { ProgressView().scaleEffect(0.7) }
                }

                if selectedProfile?.source == .sso {
                    Text("SSO login opens your browser for device authorization. After approving, click \"Check Status\".")
                        .font(.caption).foregroundStyle(.secondary)
                } else if selectedProfile?.source == .credentials {
                    Text("This profile uses temporary credentials from the AWS portal. Paste new credentials below when they expire.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SettingsSection("Add Credentials from AWS Portal") {
                Text("Paste the credential block from the AWS access portal (\"Option 2: Add a profile to your AWS credentials file\"). This writes directly to ~/.aws/credentials.")
                    .font(.caption).foregroundStyle(.secondary)

                TextEditor(text: $pasteText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 200)
                    .border(Color.secondary.opacity(0.3))
                    .overlay(alignment: .topLeading) {
                        if pasteText.isEmpty {
                            Text("[123456789012_ReadOnlyAccess]\naws_access_key_id=ASIA...\naws_secret_access_key=...\naws_session_token=...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 12) {
                    Button("Add Profile") { addCredentials() }
                        .buttonStyle(.borderedProminent)
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !pasteMessage.isEmpty {
                        Text(pasteMessage)
                            .font(.caption)
                            .foregroundStyle(pasteIsError ? .red : .green)
                    }
                }
            }
        }
        .onAppear {
            profiles = loadProfilesWithNames()
            resolveUnknownNames()
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

    private func addCredentials() {
        do {
            let profileName = try awsAuth.addPortalCredentials(pasteText)
            pasteMessage = "Added profile: \(profileName) — resolving account name..."
            pasteIsError = false
            pasteText = ""
            profiles = loadProfilesWithNames()
            appState.awsSSOProfile = profileName
            appState.saveConfig()

            // Resolve the account's friendly name in the background
            Task {
                if let alias = await awsAuth.resolveAccountName(profile: profileName) {
                    await MainActor.run {
                        // Extract account ID from profile name
                        let parts = profileName.split(separator: "_", maxSplits: 1)
                        let accountId = parts.first.map(String.init) ?? profileName
                        appState.awsAccountNames[accountId] = alias.uppercased()
                        appState.saveConfig()
                        profiles = loadProfilesWithNames()
                        pasteMessage = "Added: \(alias.uppercased()) (\(accountId))"
                    }
                } else {
                    await MainActor.run {
                        pasteMessage = "Added profile: \(profileName) (couldn't resolve account name)"
                    }
                }
            }
        } catch {
            pasteMessage = error.localizedDescription
            pasteIsError = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { pasteMessage = "" }
    }

    private func loadProfilesWithNames() -> [AWSProfile] {
        var list = awsAuth.listProfiles()
        for i in list.indices {
            if !list[i].accountId.isEmpty,
               let name = appState.awsAccountNames[list[i].accountId] {
                list[i].friendlyName = name
            }
        }
        return list
    }

    /// Resolve friendly names for profiles that don't have one cached yet.
    private func resolveUnknownNames() {
        let unknowns = profiles.filter { !$0.accountId.isEmpty && $0.friendlyName.isEmpty }
        guard !unknowns.isEmpty else { return }

        for profile in unknowns {
            Task {
                if let alias = await awsAuth.resolveAccountName(profile: profile.name, accountId: profile.accountId) {
                    await MainActor.run {
                        appState.awsAccountNames[profile.accountId] = alias.uppercased()
                        appState.saveConfig()
                        profiles = loadProfilesWithNames()
                    }
                }
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
        VStack(alignment: .leading, spacing: 16) {
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
        .onAppear {
            tokenField = appState.jiraAPIToken
            projectKeysField = appState.jiraProjectKeys.joined(separator: ", ")
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
        VStack(alignment: .leading, spacing: 16) {
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
        .onAppear { tokenField = appState.confluenceAPIToken }
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
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Connection") {
                Text("Bitbucket workspace: boomii")
                    .font(.caption).foregroundStyle(.secondary)
                FieldRow(label: "Email (from Jira)", text: .constant(appState.jiraEmail))
                FieldRow(label: "Bitbucket API Token", text: $tokenField, isSecure: true)
                Link("Create API token with Bitbucket scopes",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
                Text("Important: When creating the token, select \"Bitbucket\" as the app and grant Bitbucket read scopes. Tokens without Bitbucket scopes will return 401.")
                    .font(.caption).foregroundStyle(.orange)
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
        .onAppear { tokenField = appState.bitbucketAPIToken }
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
        VStack(alignment: .leading, spacing: 16) {
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
        .onAppear { tokenField = appState.githubToken }
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

// MARK: - Jenkins

struct JenkinsSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var urlField = ""
    @State private var usernameField = ""
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Connection") {
                FieldRow(label: "Jenkins URL", text: $urlField,
                         placeholder: "https://jenkins-master.mashspud.com")
                FieldRow(label: "Username", text: $usernameField)
                FieldRow(label: "API Token", text: $tokenField, isSecure: true)
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.jenkinsAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || urlField.isEmpty)
                    Button("Save") { saveAll() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear {
            urlField = appState.jenkinsURL
            usernameField = appState.jenkinsUsername
            tokenField = appState.jenkinsToken
        }
    }

    private func saveAll() {
        appState.jenkinsURL = urlField
        appState.jenkinsUsername = usernameField
        appState.jenkinsToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveAll()
        isTesting = true
        appState.jenkinsAuthStatus = .checking
        let url = urlField.hasSuffix("/") ? urlField : urlField + "/"
        let username = usernameField
        let token = tokenField

        Task {
            do {
                let testURL = URL(string: "\(url)api/json")!
                var request = URLRequest(url: testURL, timeoutInterval: 15)
                if let data = "\(username):\(token)".data(using: .utf8) {
                    request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                if let http, (200...299).contains(http.statusCode) {
                    let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "OK"
                    await MainActor.run { appState.jenkinsAuthStatus = .authenticated(detail: desc); isTesting = false }
                } else {
                    let code = http?.statusCode ?? 0
                    await MainActor.run { appState.jenkinsAuthStatus = .error("HTTP \(code)"); isTesting = false }
                }
            } catch {
                await MainActor.run { appState.jenkinsAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Grafana

struct GrafanaSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var urlField = ""
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Connection") {
                FieldRow(label: "Grafana URL", text: $urlField,
                         placeholder: "https://grafana.mashery.com")
                FieldRow(label: "Service Account Token", text: $tokenField, isSecure: true,
                         placeholder: "glsa_...")
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.grafanaAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || urlField.isEmpty)
                    Button("Save") { saveAll() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear {
            urlField = appState.grafanaURL
            tokenField = appState.grafanaToken
        }
    }

    private func saveAll() {
        appState.grafanaURL = urlField
        appState.grafanaToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveAll()
        isTesting = true
        appState.grafanaAuthStatus = .checking
        let url = urlField.hasSuffix("/") ? urlField : urlField + "/"
        let token = tokenField

        Task {
            do {
                let testURL = URL(string: "\(url)api/org")!
                var request = URLRequest(url: testURL, timeoutInterval: 15)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                if let http, (200...299).contains(http.statusCode) {
                    let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String ?? "OK"
                    await MainActor.run { appState.grafanaAuthStatus = .authenticated(detail: name); isTesting = false }
                } else {
                    let code = http?.statusCode ?? 0
                    await MainActor.run { appState.grafanaAuthStatus = .error("HTTP \(code)"); isTesting = false }
                }
            } catch {
                await MainActor.run { appState.grafanaAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Google

struct GoogleSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    @State private var discoveredSource = ""
    @State private var discoveredEmail = ""
    @State private var scopes: [String] = []
    @State private var isInstallingMCP = false
    @State private var setupMessage = ""
    @State private var setupIsError = false

    private let googleService = GoogleService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Account") {
                StatusBadge(status: appState.googleAuthStatus)

                if !appState.googleEmail.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.blue)
                        Text(appState.googleEmail)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                if !discoveredSource.isEmpty {
                    Text("Credentials loaded from: \(discoveredSource)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Auto-discover") { discover() }
                        .buttonStyle(.borderedProminent)
                    Button("Test Connection") { testConnection() }
                        .disabled(isTesting || appState.googleCredentials == nil)
                    if isTesting { ProgressView().scaleEffect(0.7) }
                }
            }

            SettingsSection("OAuth Scopes") {
                if scopes.isEmpty {
                    Text("Click Auto-discover to load credential details.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(scopes.count) scopes authorized:")
                        .font(.caption).foregroundStyle(.secondary)

                    let gmailScopes = scopes.filter { $0.contains("gmail") }
                    let calendarScopes = scopes.filter { $0.contains("calendar") }
                    let chatScopes = scopes.filter { $0.contains("chat") }
                    let driveScopes = scopes.filter { $0.contains("drive") }
                    let otherScopes = scopes.filter { !$0.contains("gmail") && !$0.contains("calendar") && !$0.contains("chat") && !$0.contains("drive") }

                    scopeGroup("Gmail", scopes: gmailScopes, icon: "envelope")
                    scopeGroup("Calendar", scopes: calendarScopes, icon: "calendar")
                    scopeGroup("Chat", scopes: chatScopes, icon: "bubble.left.and.bubble.right")
                    scopeGroup("Drive", scopes: driveScopes, icon: "folder")
                    if !otherScopes.isEmpty {
                        scopeGroup("Other", scopes: otherScopes, icon: "ellipsis.circle")
                    }
                }
            }

            SettingsSection("Setup & MCP Server") {
                let credPath = "~/.google_workspace_mcp/credentials/"
                let hasCredentials = appState.googleCredentials != nil

                if hasCredentials {
                    Label("Credentials found at \(credPath)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("No credentials found", systemImage: "xmark.circle")
                        .font(.caption).foregroundStyle(.red)
                }

                Text("To set up Google Workspace credentials:")
                    .font(.caption.bold()).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    setupStep("1", text: "Install the MCP package: npm install -g mcp-google")
                    setupStep("2", text: "Run the auth flow: npx mcp-google auth")
                    setupStep("3", text: "Copy the credential file to \(credPath)")
                    setupStep("4", text: "Click Auto-discover above to load credentials")
                }

                HStack(spacing: 12) {
                    Button("Install MCP Package") { installMCPPackage() }
                        .disabled(isInstallingMCP)
                    Button("Run OAuth Flow") { runOAuthFlow() }
                        .disabled(isInstallingMCP)
                    Button("Open Credentials Folder") {
                        let home = FileManager.default.homeDirectoryForCurrentUser
                        let dir = home.appendingPathComponent(".google_workspace_mcp/credentials")
                        NSWorkspace.shared.open(dir)
                    }
                    if isInstallingMCP { ProgressView().scaleEffect(0.7) }
                }

                if !setupMessage.isEmpty {
                    Text(setupMessage)
                        .font(.caption)
                        .foregroundStyle(setupIsError ? .red : .green)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear { discover() }
    }

    private func discover() {
        if let result = GoogleCredentials.discover() {
            discoveredSource = result.source
            discoveredEmail = result.email
            scopes = result.credentials.scopes ?? []
            appState.googleEmail = result.email
            testConnection()
        } else {
            appState.googleAuthStatus = .notConfigured
            discoveredSource = ""
            scopes = []
        }
    }

    private func testConnection() {
        guard let creds = appState.googleCredentials else {
            appState.googleAuthStatus = .notConfigured
            return
        }
        isTesting = true
        appState.googleAuthStatus = .checking
        Task {
            do {
                let email = try await googleService.checkAuth(credentials: creds)
                await MainActor.run {
                    appState.googleAuthStatus = .authenticated(detail: email)
                    appState.googleEmail = email
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    appState.googleAuthStatus = .error(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func scopeGroup(_ title: String, scopes: [String], icon: String) -> some View {
        DisclosureGroup {
            ForEach(scopes, id: \.self) { scope in
                Text(scope)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .font(.callout)
                Text("(\(scopes.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setupStep(_ num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.caption.bold())
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func installMCPPackage() {
        isInstallingMCP = true
        setupMessage = ""
        Task {
            let (output, exitCode) = await runShell("/usr/bin/env", args: ["npm", "install", "-g", "mcp-google"])
            await MainActor.run {
                isInstallingMCP = false
                if exitCode == 0 {
                    setupMessage = "mcp-google installed successfully. Run OAuth Flow next."
                    setupIsError = false
                } else {
                    setupMessage = "Install failed: \(String(output.prefix(300)))"
                    setupIsError = true
                }
            }
        }
    }

    private func runOAuthFlow() {
        isInstallingMCP = true
        setupMessage = "Opening browser for Google OAuth consent..."
        setupIsError = false

        // Ensure credential directory exists
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credDir = home.appendingPathComponent(".google_workspace_mcp/credentials")
        try? FileManager.default.createDirectory(at: credDir, withIntermediateDirectories: true)

        Task {
            let (output, exitCode) = await runShell("/usr/bin/env", args: ["npx", "mcp-google", "auth"])
            await MainActor.run {
                isInstallingMCP = false
                if exitCode == 0 {
                    setupMessage = "OAuth complete. Click Auto-discover to load credentials."
                    setupIsError = false
                    discover()
                } else {
                    setupMessage = "OAuth flow failed: \(String(output.prefix(300)))"
                    setupIsError = true
                }
            }
        }
    }

    private func runShell(_ executable: String, args: [String]) async -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return (error.localizedDescription, -1)
        }
    }
}

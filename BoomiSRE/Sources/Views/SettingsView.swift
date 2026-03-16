import SwiftUI

/// Inline settings panel displayed in the main content area.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    // Backed by appState so the menu item "Check for Updates..." can deep-link here
    private var selectedTab: String {
        get { appState.selectedSettingsTab }
        nonmutating set { appState.selectedSettingsTab = newValue }
    }
    @State private var discoveryResult: String?
    @State private var discoveryIsError = false
    @State private var showResetConfirm = false
    @State private var showFeatureRequest = false

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

            // Corporate identity card — shown when an email is known
            if !appState.jiraEmail.isEmpty || !appState.userProfile.email.isEmpty {
                let email = appState.jiraEmail.isEmpty ? appState.userProfile.email : appState.jiraEmail
                HStack(spacing: 12) {
                    Image(systemName: "key.fill").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Corporate Identity").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(email).font(.callout).textSelection(.enabled)
                        Text("SSO services (Confluence, Grafana, Google Chat) use your Okta session — sign in once, stay signed in. API services need a personal token (see each tab).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        selectedTab = "profile"
                    } label: {
                        Label("Edit Profile", systemImage: "person.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.05))

                Divider()
            }

            HStack(spacing: 0) {
                // Left tab bar
                VStack(alignment: .leading, spacing: 2) {
                    // GENERAL
                    sectionHeader("GENERAL")
                    settingsTab("profile", label: "Profile", icon: "person.circle", status: nil)
                    settingsTab("appearance", label: "Appearance", icon: "paintpalette", status: nil)

                    Divider().padding(.vertical, 4)

                    // INTEGRATIONS
                    sectionHeader("INTEGRATIONS")
                    settingsTab("jira", label: "Jira", icon: "ticket", status: appState.jiraAuthStatus)
                    settingsTab("aws", label: "AWS SSO", icon: "cloud", status: appState.awsAuthStatus)
                    settingsTab("grafana", label: "Grafana", icon: "chart.line.uptrend.xyaxis", status: appState.grafanaAuthStatus)
                    settingsTab("github", label: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: appState.githubAuthStatus)
                    settingsTab("bitbucket", label: "Bitbucket", icon: "externaldrive.connected.to.line.below", status: appState.bitbucketAuthStatus)
                    settingsTab("jenkins", label: "Jenkins", icon: "hammer", status: appState.jenkinsAuthStatus)
                    settingsTab("confluence", label: "Confluence", icon: "book.closed", status: appState.confluenceAuthStatus)
                    settingsTab("google", label: "Google", icon: "envelope", status: appState.googleAuthStatus)

                    Divider().padding(.vertical, 4)

                    // FEATURES
                    sectionHeader("FEATURES")
                    settingsTab("products", label: "Products", icon: "square.grid.2x2", status: nil)
                    settingsTab("favorites", label: "Favorites", icon: "star.fill", status: nil)
                    settingsTab("notifications", label: "Notifications", icon: "bell.badge", status: nil)

                    Divider().padding(.vertical, 4)

                    // ABOUT
                    sectionHeader("ABOUT")
                    settingsTab("productivity", label: "Productivity", icon: "chart.line.uptrend.xyaxis", status: nil)
                    settingsTab("advanced", label: "Advanced", icon: "gearshape.2", status: nil)
                    settingsTab("about", label: "About", icon: "info.circle", status: nil)

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
                        case "profile": ProfileView()
                        case "appearance": AppearanceSettingsContent()
                        case "favorites": FavoritesSettingsContent()
                        case "notifications": NotificationsSettingsContent()
                        case "aws": AWSSettingsContent()
                        case "jira": JiraSettingsContent()
                        case "confluence": ConfluenceSettingsContent()
                        case "bitbucket": BitbucketSettingsContent()
                        case "github": GitHubSettingsContent()
                        case "jenkins": JenkinsSettingsContent()
                        case "grafana": GrafanaSettingsContent()
                        case "google": GoogleSettingsContent()
                        case "jsm": JiraSettingsContent()  // redirect to Jira tab
                        case "incidents": JiraSettingsContent()  // redirect to Jira tab
                        case "products": ProductSettingsContent()
                        case "productivity": ProductivityView()
                        case "advanced": AdvancedSettingsContent(showFeatureRequest: $showFeatureRequest)
                        case "about": AboutSettingsContent()
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
        .alert("Factory Reset", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                appState.factoryReset()
            }
        } message: {
            Text("This will reset all app settings, clear notifications, incidents, chat history, and saved credentials. Your AWS config (~/.aws/), MCP credentials (~/.kiro/), and Git config are NOT affected.\n\nThe app will restart with the Onboarding Wizard.")
        }
        .sheet(isPresented: $showFeatureRequest) {
            FeatureRequestView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsProfileTab)) { _ in
            selectedTab = "profile"
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutTab)) { _ in
            selectedTab = "about"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
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

// MARK: - Connection Explanation

struct ConnectionExplanationView: View {
    let serviceName: String
    let apiDescription: String
    var webDescription: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How Boomi SRE connects to \(serviceName)", systemImage: "info.circle")
                .font(.subheadline.bold())

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("API Connection").font(.caption.bold())
                    Text(apiDescription).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let webDesc = webDescription {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Web View").font(.caption.bold())
                        Text(webDesc).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.blue.opacity(0.15)))
    }
}

// MARK: - Favorites

struct FavoritesSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var awsProfiles: [AWSProfile] = []
    @State private var jiraProjects: [JiraProjectSummary] = []
    @State private var confluenceSpaces: [ConfluenceSpaceSummary] = []
    @State private var githubRepos: [GitHubRepo] = []
    @State private var jenkinsJobs: [JenkinsJob] = []
    @State private var grafanaDashboards: [GrafanaDashboard] = []
    @State private var isLoadingJira = false
    @State private var isLoadingConfluence = false
    @State private var isLoadingGitHub = false
    @State private var isLoadingJenkins = false
    @State private var isLoadingGrafana = false
    @State private var jiraError: String?
    @State private var confluenceError: String?
    @State private var githubError: String?
    @State private var jenkinsError: String?
    @State private var grafanaError: String?

    private let awsAuth = AWSAuthService()
    private let jiraService = JiraService()
    private let confluenceService = ConfluenceService()
    private let githubService = GitHubService()
    private let jenkinsService = JenkinsService()
    private let grafanaService = GrafanaService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Favorites").font(.title2.bold())
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

            // Favorite GitHub Repos
            SettingsSection("Favorite GitHub Repos") {
                if appState.githubToken.isEmpty {
                    Text("Configure GitHub credentials first.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if isLoadingGitHub {
                    HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Loading repos…").font(.caption).foregroundStyle(.secondary) }
                } else if let error = githubError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { fetchGitHubRepos() }
                } else if githubRepos.isEmpty {
                    HStack(spacing: 8) { Text("No repos loaded.").font(.caption).foregroundStyle(.secondary); Button("Fetch Repos") { fetchGitHubRepos() } }
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(githubRepos) { repo in
                            Toggle(isOn: Binding(
                                get: { appState.favoriteGitHubRepos.contains(repo.fullName) },
                                set: { on in
                                    if on { appState.favoriteGitHubRepos.append(repo.fullName) }
                                    else  { appState.favoriteGitHubRepos.removeAll { $0 == repo.fullName } }
                                    appState.saveConfig()
                                })) {
                                Text(repo.fullName).font(.body)
                            }.toggleStyle(.checkbox)
                        }
                    }
                }
            }

            // Favorite Jenkins Jobs
            SettingsSection("Favorite Jenkins Jobs") {
                if appState.jenkinsToken.isEmpty {
                    Text("Configure Jenkins credentials first.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if isLoadingJenkins {
                    HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Loading jobs…").font(.caption).foregroundStyle(.secondary) }
                } else if let error = jenkinsError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { fetchJenkinsJobs() }
                } else if jenkinsJobs.isEmpty {
                    HStack(spacing: 8) { Text("No jobs loaded.").font(.caption).foregroundStyle(.secondary); Button("Fetch Jobs") { fetchJenkinsJobs() } }
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(jenkinsJobs) { job in
                            Toggle(isOn: Binding(
                                get: { appState.favoriteJenkinsJobs.contains(job.name) },
                                set: { on in
                                    if on { appState.favoriteJenkinsJobs.append(job.name) }
                                    else  { appState.favoriteJenkinsJobs.removeAll { $0 == job.name } }
                                    appState.saveConfig()
                                })) {
                                Text(job.name).font(.body)
                            }.toggleStyle(.checkbox)
                        }
                    }
                }
            }

            // Favorite Grafana Dashboards
            SettingsSection("Favorite Grafana Dashboards") {
                if appState.grafanaToken.isEmpty {
                    Text("Configure Grafana credentials first.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if isLoadingGrafana {
                    HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Loading dashboards…").font(.caption).foregroundStyle(.secondary) }
                } else if let error = grafanaError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { fetchGrafanaDashboards() }
                } else if grafanaDashboards.isEmpty {
                    HStack(spacing: 8) { Text("No dashboards loaded.").font(.caption).foregroundStyle(.secondary); Button("Fetch Dashboards") { fetchGrafanaDashboards() } }
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(grafanaDashboards) { dash in
                            Toggle(isOn: Binding(
                                get: { appState.favoriteGrafanaDashboards.contains(dash.uid) },
                                set: { on in
                                    if on { appState.favoriteGrafanaDashboards.append(dash.uid) }
                                    else  { appState.favoriteGrafanaDashboards.removeAll { $0 == dash.uid } }
                                    appState.saveConfig()
                                })) {
                                Text(dash.title).font(.body)
                            }.toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadAWSProfiles()
            if appState.isJiraConfigured { fetchJiraProjects() }
            if !appState.confluenceAPIToken.isEmpty { fetchConfluenceSpaces() }
            if !appState.githubToken.isEmpty { fetchGitHubRepos() }
            if !appState.jenkinsToken.isEmpty { fetchJenkinsJobs() }
            if !appState.grafanaToken.isEmpty { fetchGrafanaDashboards() }
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

    private func fetchGitHubRepos() {
        isLoadingGitHub = true; githubError = nil
        let token = appState.githubToken
        Task {
            do {
                async let orgTask  = githubService.listOrgRepos(org: "Mashery-Boomi", token: token)
                async let userTask = githubService.listUserRepos(token: token)
                var all = try await orgTask
                let personal = (try? await userTask) ?? []
                let orgNames = Set(all.map(\.fullName))
                all += personal.filter { !orgNames.contains($0.fullName) }
                await MainActor.run { githubRepos = all.sorted { $0.fullName < $1.fullName }; isLoadingGitHub = false }
            } catch {
                await MainActor.run { githubError = error.localizedDescription; isLoadingGitHub = false }
            }
        }
    }

    private func fetchJenkinsJobs() {
        isLoadingJenkins = true; jenkinsError = nil
        let (url, user, tok) = (appState.jenkinsURL, appState.jenkinsUsername, appState.jenkinsToken)
        Task {
            do {
                let jobs = try await jenkinsService.listJobs(baseURL: url, username: user, token: tok)
                await MainActor.run { jenkinsJobs = jobs.sorted { $0.name < $1.name }; isLoadingJenkins = false }
            } catch {
                await MainActor.run { jenkinsError = error.localizedDescription; isLoadingJenkins = false }
            }
        }
    }

    private func fetchGrafanaDashboards() {
        isLoadingGrafana = true; grafanaError = nil
        let (url, tok) = (appState.grafanaURL, appState.grafanaToken)
        Task {
            do {
                let dashes = try await grafanaService.searchDashboards(baseURL: url, token: tok)
                await MainActor.run { grafanaDashboards = dashes.sorted { $0.title < $1.title }; isLoadingGrafana = false }
            } catch {
                await MainActor.run { grafanaError = error.localizedDescription; isLoadingGrafana = false }
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

// MARK: - Notifications

struct NotificationsSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Notifications").font(.title2.bold())
            Text("Configure background polling and notification preferences.")
                .font(.callout).foregroundStyle(.secondary)

            SettingsSection("Background Polling") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("macOS system notifications (high-priority items)", isOn: Binding(
                        get: { appState.systemNotificationsEnabled },
                        set: { appState.systemNotificationsEnabled = $0; notificationVM.systemNotificationsEnabled = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Toggle("Jira ticket assignments & status changes", isOn: Binding(
                        get: { appState.pollJiraEnabled },
                        set: { appState.pollJiraEnabled = $0; notificationVM.pollJira = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Toggle("Jenkins build failures", isOn: Binding(
                        get: { appState.pollJenkinsEnabled },
                        set: { appState.pollJenkinsEnabled = $0; notificationVM.pollJenkins = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Toggle("Grafana alert firing", isOn: Binding(
                        get: { appState.pollGrafanaEnabled },
                        set: { appState.pollGrafanaEnabled = $0; notificationVM.pollGrafana = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Toggle("GitHub PR review requests", isOn: Binding(
                        get: { appState.pollGitHubEnabled },
                        set: { appState.pollGitHubEnabled = $0; notificationVM.pollGitHub = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                }
            }

            SettingsSection("Refresh Interval") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Every \(Int(appState.refreshInterval / 60)) minutes").font(.subheadline).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { appState.refreshInterval },
                        set: { appState.refreshInterval = $0; notificationVM.refreshInterval = $0; appState.saveConfig() }
                    ), in: 60...1800, step: 60)
                    Text("Range: 1–30 minutes").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            SettingsSection("Archive Retention") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How long to keep read notifications in the archive:")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { appState.archiveRetention },
                        set: { appState.archiveRetention = $0; notificationVM.archiveRetention = $0; appState.saveConfig() }
                    )) {
                        ForEach(ArchiveRetention.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
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
struct ConfluenceSpaceSummary: Identifiable, Codable, Hashable, Equatable {
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
    @State private var detectedProfileName: String = ""   // live preview of parsed profile name

    private let awsAuth = AWSAuthService()

    private var selectedProfile: AWSProfile? {
        profiles.first { $0.name == appState.awsSSOProfile }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "AWS",
                apiDescription: "AWS SSO or portal credentials are used to run AWS CLI commands for Cost Explorer, EC2, RDS, and other infrastructure queries."
            )

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
                    .onChange(of: pasteText) { updateDetectedProfile() }

                // Live preview of detected profile name
                if !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !detectedProfileName.isEmpty && !detectedProfileName.hasPrefix("portal-") {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            Text("Detected profile: \(detectedProfileName)").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if detectedProfileName.hasPrefix("portal-") {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            Text("Could not detect profile name. The header line should look like: [AccountId_RoleName]")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // Session token expiry note
                Text("Portal credentials are temporary session tokens. They expire after the session timeout configured by your organization (typically 1–12 hours). You'll need to paste new credentials when they expire.")
                    .font(.caption).foregroundStyle(.tertiary)

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

    private func updateDetectedProfile() {
        let normalized = pasteText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") && l.hasSuffix("]") {
                let name = String(l.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                detectedProfileName = name.isEmpty ? "portal-fallback" : name
                return
            }
        }
        detectedProfileName = pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "portal-fallback"
    }

    private func addCredentials() {
        do {
            let profileName = try awsAuth.addPortalCredentials(pasteText)
            pasteMessage = "Added profile: \(profileName) — resolving account name..."
            pasteIsError = false
            pasteText = ""
            detectedProfileName = ""
            profiles = loadProfilesWithNames()
            appState.awsSSOProfile = profileName
            appState.saveConfig()

            // Immediately check status so user gets confirmation it works
            Task {
                appState.awsAuthStatus = .checking
                do {
                    let detail = try await awsAuth.checkStatus(profile: profileName)
                    await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
                } catch {
                    await MainActor.run { appState.awsAuthStatus = .error(error.localizedDescription) }
                }
            }

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
            .filter { $0.name != "pasted" }   // filter out bug-artifact profiles
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
    @State private var showGuide = false
    @State private var jiraSubTab = 0

    private let jiraService = JiraService()

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("", selection: $jiraSubTab) {
                Text("Credentials").tag(0)
                Text("Incidents").tag(1)
                Text("On-Call").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            ScrollView {
                switch jiraSubTab {
                case 0:
                    jiraCredentialsContent
                        .padding(24)
                case 1:
                    IncidentSettingsContent()
                        .padding(24)
                case 2:
                    JSMSettingsContent()
                        .padding(24)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jiraCredentialsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Jira",
                apiDescription: "Your personal API token is used to fetch tickets, filters, boards, and post comments. Generate one at id.atlassian.com."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Base URL", text: $appState.jiraBaseURL)
                FieldRow(label: "Email", text: $appState.jiraEmail)
                FieldRow(label: "API Token", text: $tokenField, isSecure: true)
                HStack {
                    Link("Get a token from Atlassian",
                         destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        .font(.caption)
                    Spacer()
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .jira)
                .environmentObject(appState)
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
            ConnectionExplanationView(
                serviceName: "Confluence",
                apiDescription: "Your API token fetches spaces, pages, and search results.",
                webDescription: "Some pages with complex macros or embedded content are rendered in an embedded browser view. If you see a login page, sign in once — the session persists."
            )

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
    @State private var workspaceField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false

    private let service = BitbucketService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Bitbucket",
                apiDescription: "A Bitbucket-scoped API token is used to list repositories, PRs, branches, and pipelines. This is a separate token from Jira/Confluence — create it at id.atlassian.com and select Bitbucket as the target app."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Workspace", text: $workspaceField)
                FieldRow(label: "Email (from Jira)", text: .constant(appState.jiraEmail))
                FieldRow(label: "Bitbucket API Token", text: $tokenField, isSecure: true)

                HStack {
                    Link("Create a Bitbucket-scoped token",
                         destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        .font(.caption)
                    Spacer()
                    Button { showGuide = true } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Text("Bitbucket API tokens are separate from Jira tokens. Create one at id.atlassian.com → select Bitbucket as the target → choose Repository/PR/Pipeline scopes. App passwords are deprecated (Sept 2025, disabled June 2026).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.bitbucketAuthStatus)
                if appState.jiraEmail.isEmpty {
                    Label("Email not set — configure Jira email first", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
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
        .onAppear {
            tokenField = appState.bitbucketAPIToken
            workspaceField = appState.bitbucketWorkspace
        }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .bitbucket)
                .environmentObject(appState)
        }
    }

    private func saveToken() {
        appState.bitbucketAPIToken = tokenField
        appState.bitbucketWorkspace = workspaceField.isEmpty ? "boomii" : workspaceField
        appState.saveConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.bitbucketAuthStatus = .checking
        let (email, token, workspace) = (appState.jiraEmail, tokenField, appState.bitbucketWorkspace)
        Task {
            do {
                let name = try await service.checkAuth(email: email, apiToken: token, workspace: workspace)
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
    @State private var showGuide = false
    @State private var newOrgField = ""
    @State private var isDiscovering = false
    @State private var discoveredOrgs: [String] = []

    private let service = GitHubService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "GitHub",
                apiDescription: "Your personal access token (classic or fine-grained) is used to list repos, PRs, files, workflow runs, and create issues. Generate one at github.com/settings/tokens."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Personal Access Token", text: $tokenField, isSecure: true,
                         placeholder: "ghp_...")
                HStack {
                    Link("Create a token at github.com",
                         destination: URL(string: "https://github.com/settings/tokens")!)
                        .font(.caption)
                    Spacer()
                    Button { showGuide = true } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Text("Needs repo and read:org scopes for Mashery-Boomi org access.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsSection("GitHub Organizations") {
                Text("Repos from these orgs will appear in the GitHub browser.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(appState.githubOrgs, id: \.self) { org in
                    HStack {
                        Text(org).font(.callout)
                        Spacer()
                        Button { appState.githubOrgs.removeAll { $0 == org }; appState.saveConfig() } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add org (e.g. my-company)", text: $newOrgField)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newOrgField.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !appState.githubOrgs.contains(trimmed) {
                            appState.githubOrgs.append(trimmed); appState.saveConfig()
                        }
                        newOrgField = ""
                    }.buttonStyle(.bordered).disabled(newOrgField.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack(spacing: 10) {
                    Button {
                        isDiscovering = true
                        let token = tokenField.isEmpty ? appState.githubToken : tokenField
                        Task {
                            discoveredOrgs = (try? await service.listUserOrgs(token: token)) ?? []
                            await MainActor.run { isDiscovering = false }
                        }
                    } label: {
                        if isDiscovering { HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Discovering…") } }
                        else { Label("Discover My Orgs", systemImage: "magnifyingglass") }
                    }
                    .buttonStyle(.bordered).disabled(isDiscovering || (tokenField.isEmpty && appState.githubToken.isEmpty))
                }

                if !discoveredOrgs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Discovered orgs — tap to add:").font(.caption).foregroundStyle(.secondary)
                        ForEach(discoveredOrgs, id: \.self) { org in
                            HStack {
                                Text(org).font(.callout)
                                Spacer()
                                if appState.githubOrgs.contains(org) {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                } else {
                                    Button("Add") {
                                        appState.githubOrgs.append(org); appState.saveConfig()
                                    }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                }
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
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .github).environmentObject(appState)
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

// MARK: - Jenkins

struct JenkinsSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var urlField = ""
    @State private var usernameField = ""
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Jenkins",
                apiDescription: "Your Jenkins API token is used to list jobs, fetch build history, and read console output. Find it in Jenkins \u{2192} Your Name \u{2192} Configure \u{2192} API Token."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Jenkins URL", text: $urlField,
                         placeholder: "https://jenkins-master.mashspud.com")
                FieldRow(label: "Username", text: $usernameField)
                FieldRow(label: "API Token", text: $tokenField, isSecure: true)
                HStack {
                    Spacer()
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .jenkins(jenkinsURL: appState.jenkinsURL))
                .environmentObject(appState)
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
    @State private var webUsernameField = ""
    @State private var webPasswordField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Grafana",
                apiDescription: "Your Service Account token is used to fetch dashboards, panels, queries, and alert rules via the Grafana API.",
                webDescription: "Dashboard views are rendered in an embedded browser using your Grafana web session. If you see a login screen, sign in once — the session persists."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Grafana URL", text: $urlField,
                         placeholder: "https://grafana.mashery.com")
                FieldRow(label: "Service Account Token", text: $tokenField, isSecure: true,
                         placeholder: "glsa_...")
                HStack {
                    Spacer()
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection("Web View Credentials (Optional)") {
                Text("Used to auto-fill the Grafana login form in embedded browser views.")
                    .font(.caption).foregroundStyle(.secondary)
                FieldRow(label: "Grafana Web Username", text: $webUsernameField)
                FieldRow(label: "Grafana Web Password", text: $webPasswordField, isSecure: true)
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
            webUsernameField = KeychainHelper.load(key: "grafana-web-username") ?? ""
            webPasswordField = KeychainHelper.load(key: "grafana-web-password") ?? ""
        }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .grafana(grafanaURL: appState.grafanaURL))
                .environmentObject(appState)
        }
    }

    private func saveAll() {
        appState.grafanaURL = urlField
        appState.grafanaToken = tokenField
        if !webUsernameField.isEmpty {
            try? KeychainHelper.save(key: "grafana-web-username", value: webUsernameField)
        }
        if !webPasswordField.isEmpty {
            try? KeychainHelper.save(key: "grafana-web-password", value: webPasswordField)
        }
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
    @State private var showGuide = false

    private let googleService = GoogleService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Google",
                apiDescription: "Google Workspace integration uses OAuth credentials for Gmail and Calendar.",
                webDescription: "Google Chat and some Gmail features use an embedded browser. Sign in to your Google account once within the app — the session persists across launches."
            )

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
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide / OAuth Help", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .google)
                .environmentObject(appState)
        }
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

// MARK: - Advanced Settings

private struct AdvancedSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var showFeatureRequest: Bool
    @State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Advanced").font(.title3.bold())

            // Feedback section
            VStack(alignment: .leading, spacing: 12) {
                Text("Feedback").font(.headline)
                Text("Found a bug or have a feature idea? Submit it directly from the app.")
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    showFeatureRequest = true
                } label: {
                    Label("Submit Feature Request or Bug Report", systemImage: "questionmark.bubble")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))

            Divider()

            // Factory Reset section
            VStack(alignment: .leading, spacing: 12) {
                Text("Danger Zone").font(.headline).foregroundStyle(.red)
                Text("Factory Reset clears all app settings, saved credentials, notifications, incidents, and chat history. Your AWS CLI config, MCP credentials, and Git config are NOT affected.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Factory Reset…", systemImage: "exclamationmark.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.2)))

            Spacer()
        }
        .alert("Factory Reset", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                appState.factoryReset()
            }
        } message: {
            Text("This will reset all app settings, clear notifications, incidents, chat history, and saved credentials. Your AWS config (~/.aws/), MCP credentials (~/.kiro/), and Git config are NOT affected.\n\nThe app will restart with the Onboarding Wizard.")
        }
    }
}

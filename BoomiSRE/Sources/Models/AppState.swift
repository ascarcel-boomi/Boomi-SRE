import Foundation
import SwiftUI

/// Central app state shared across all views.
final class AppState: ObservableObject {
    // Navigation
    @Published var selectedReport: ReportItem?
    @Published var showSettings = false
    @Published var selectedSettingsTab: String = "preferences"   // deep-link into a specific tab
    @Published var selectedTicketKey: String?  // opens ticket detail view
    @Published var sidebarCollapsed = false
    @Published var viewMode: ViewMode = .chart

    // Report results
    @Published var results: [String: ReportResult] = [:]
    @Published var runningReports: Set<String> = []

    // Config (persisted)
    @Published var csvFolder: String
    @Published var awsSSOProfile: String
    @Published var jiraEmail: String
    @Published var jiraBaseURL: String
    @Published var jiraProjectKeys: [String]

    // AWS account name cache: accountId -> friendly name (persisted)
    @Published var awsAccountNames: [String: String] = [:]

    // Favorites (persisted)
    @Published var favoriteAWSProfiles: [String] = []
    @Published var favoriteJiraProjects: [String] = []
    @Published var favoriteConfluenceSpaces: [String] = []
    @Published var favoriteGitHubRepos: [String] = []       // "owner/repo"
    @Published var favoriteJenkinsJobs: [String] = []
    @Published var favoriteGrafanaDashboards: [String] = [] // UIDs

    // AI Settings (persisted)
    @Published var claudeModel: String = "claude-sonnet-4-6"
    @Published var chatMaxTokens: Int = 4096
    @Published var autoContextEnabled: Bool = true
    @Published var analysisDepth: String = "standard"  // "brief" | "standard" | "thorough"

    // Notification preferences (persisted)
    @Published var pollJiraEnabled: Bool = true
    @Published var pollJenkinsEnabled: Bool = true
    @Published var pollGrafanaEnabled: Bool = true
    @Published var pollGitHubEnabled: Bool = true
    @Published var pollConfluenceEnabled: Bool = true
    @Published var pollAWSCostsEnabled: Bool = true
    @Published var systemNotificationsEnabled: Bool = true
    @Published var archiveRetention: ArchiveRetention = .hours24

    // Executive Assistant preferences (persisted)
    @Published var enabledBriefingTypes: Set<String> = []
    @Published var autoGenerateBriefingsOnLaunch: Bool = false

    // User Profile (persisted)
    @Published var userProfile: UserProfile = .empty

    // Incident settings (persisted)
    @Published var incidentProductElementFieldId: String = ""   // e.g., "customfield_10456"
    @Published var availableProductElements: [String] = []      // all discovered values
    @Published var favoriteProductElements: [String] = []       // user's selected favorites
    @Published var useCustomIncidentJQL: Bool = false
    @Published var customIncidentJQL: String = ""

    // Onboarding
    @Published var hasCompletedOnboarding: Bool = false

    // Dashboard
    @Published var dashboardWidgets: [DashboardWidget] = DashboardWidget.defaults
    @Published var dashboardMode: String = "auto"

    // Bitbucket workspace
    @Published var bitbucketWorkspace: String = "boomii"

    // GitHub Orgs (multi-org; githubOrg kept for backward compat)
    @Published var githubOrg: String = "Mashery-Boomi"
    @Published var githubOrgs: [String] = ["Mashery-Boomi"]

    // Knowledge Base repo
    @Published var kbRepoOwner: String = "ascarcel-boomi"
    @Published var kbRepoName: String  = "mashery-sre-kb"

    // JSM On-Call
    @Published var favoriteJSMTeams: [String] = []
    @Published var jsmCloudId: String = ""
    @Published var discoveredJSMTeams: [OpsTeam] = []

    // Refresh trigger — views observe this to re-fetch data
    @Published var refreshTrigger = UUID()

    // Executive Assistant unread badge count (updated by ExecAssistantViewModel)
    @Published var unreadBriefingCount: Int = 0

    // Incident Command — active P1/P2 count for sidebar badge (updated by IncidentViewModel)
    @Published var activeIncidentCount: Int = 0

    // Background Refresh
    @Published var refreshInterval: TimeInterval = 300   // 5 minutes
    private var refreshTimer: Timer?

    func startBackgroundRefresh() {
        stopBackgroundRefresh()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval, repeats: true
        ) { [weak self] _ in
            self?.refreshTrigger = UUID()
        }
    }

    func stopBackgroundRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // Auth status (transient)
    @Published var awsAuthStatus: AuthStatus = .unknown
    @Published var jiraAuthStatus: AuthStatus = .unknown
    @Published var confluenceAuthStatus: AuthStatus = .unknown
    @Published var bitbucketAuthStatus: AuthStatus = .unknown
    @Published var githubAuthStatus: AuthStatus = .unknown
    @Published var jenkinsAuthStatus: AuthStatus = .unknown
    @Published var grafanaAuthStatus: AuthStatus = .unknown
    @Published var googleAuthStatus: AuthStatus = .unknown
    @Published var jsmOpsAuthStatus: AuthStatus = .unknown
    @Published var googleEmail: String = ""

    private let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configURL = home.appendingPathComponent(".boomi_sre_config.json")
        self.csvFolder = home.appendingPathComponent("Downloads").path
        self.awsSSOProfile = "cam-prod-ro-json"
        self.jiraEmail = ""
        self.jiraBaseURL = "https://boomii.atlassian.net"
        self.jiraProjectKeys = ["CAMSRE", "SRE"]

        loadConfig()
        // Seed defaults that can't be set at property declaration time
        if enabledBriefingTypes.isEmpty {
            enabledBriefingTypes = Set(["morningBrief","emailTriage","preMeetingBrief",
                                        "actionTracker","eodDigest","dailyTicketBrief","claudeUsage"])
        }
    }

    // MARK: - Config persistence

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
        if let v = config.csvFolder { csvFolder = v }
        if let v = config.awsSSOProfile { awsSSOProfile = v }
        if let v = config.jiraEmail { jiraEmail = v }
        if let v = config.jiraBaseURL { jiraBaseURL = v }
        if let v = config.jiraProjectKeys { jiraProjectKeys = v }
        if let v = config.awsAccountNames { awsAccountNames = v }
        if let v = config.favoriteAWSProfiles { favoriteAWSProfiles = v }
        if let v = config.favoriteJiraProjects { favoriteJiraProjects = v }
        if let v = config.favoriteConfluenceSpaces { favoriteConfluenceSpaces = v }
        if let v = config.favoriteGitHubRepos { favoriteGitHubRepos = v }
        if let v = config.favoriteJenkinsJobs { favoriteJenkinsJobs = v }
        if let v = config.favoriteGrafanaDashboards { favoriteGrafanaDashboards = v }
        if let v = config.claudeModel { claudeModel = v }
        if let v = config.chatMaxTokens { chatMaxTokens = v }
        if let v = config.autoContextEnabled { autoContextEnabled = v }
        if let v = config.analysisDepth { analysisDepth = v }
        if let v = config.pollJiraEnabled { pollJiraEnabled = v }
        if let v = config.pollJenkinsEnabled { pollJenkinsEnabled = v }
        if let v = config.pollGrafanaEnabled { pollGrafanaEnabled = v }
        if let v = config.pollGitHubEnabled { pollGitHubEnabled = v }
        if let v = config.pollConfluenceEnabled { pollConfluenceEnabled = v }
        if let v = config.pollAWSCostsEnabled { pollAWSCostsEnabled = v }
        if let v = config.systemNotificationsEnabled { systemNotificationsEnabled = v }
        if let v = config.archiveRetention, let r = ArchiveRetention(rawValue: v) { archiveRetention = r }
        if let v = config.enabledBriefingTypes {
            enabledBriefingTypes = Set(v)
        } else {
            // Default: all briefings enabled
            enabledBriefingTypes = Set(["morningBrief","emailTriage","preMeetingBrief",
                                        "actionTracker","eodDigest","dailyTicketBrief","claudeUsage"])
        }
        if let v = config.autoGenerateBriefingsOnLaunch { autoGenerateBriefingsOnLaunch = v }
        if let v = config.hasCompletedOnboarding { hasCompletedOnboarding = v }
        if let v = config.dashboardWidgets { dashboardWidgets = v }
        if let v = config.dashboardMode { dashboardMode = v }
        if let v = config.bitbucketWorkspace { bitbucketWorkspace = v }
        if let v = config.githubOrg { githubOrg = v }
        if let v = config.githubOrgs {
            githubOrgs = v
        } else if let v = config.githubOrg, !v.isEmpty {
            githubOrgs = [v]   // migrate single-org config to array
        }
        if let v = config.kbRepoOwner { kbRepoOwner = v }
        if let v = config.kbRepoName { kbRepoName = v }
        if let v = config.favoriteJSMTeams { favoriteJSMTeams = v }
        if let v = config.jsmCloudId { jsmCloudId = v }
        if let v = config.userProfile { userProfile = v }
        if let v = config.incidentProductElementFieldId { incidentProductElementFieldId = v }
        if let v = config.availableProductElements { availableProductElements = v }
        if let v = config.favoriteProductElements { favoriteProductElements = v }
        if let v = config.useCustomIncidentJQL { useCustomIncidentJQL = v }
        if let v = config.customIncidentJQL { customIncidentJQL = v }
    }

    func saveConfig() {
        let config = AppConfig(
            csvFolder: csvFolder,
            awsSSOProfile: awsSSOProfile,
            jiraEmail: jiraEmail,
            jiraBaseURL: jiraBaseURL,
            jiraProjectKeys: jiraProjectKeys,
            awsAccountNames: awsAccountNames,
            favoriteAWSProfiles: favoriteAWSProfiles,
            favoriteJiraProjects: favoriteJiraProjects,
            favoriteConfluenceSpaces: favoriteConfluenceSpaces,
            favoriteGitHubRepos: favoriteGitHubRepos,
            favoriteJenkinsJobs: favoriteJenkinsJobs,
            favoriteGrafanaDashboards: favoriteGrafanaDashboards,
            claudeModel: claudeModel,
            chatMaxTokens: chatMaxTokens,
            autoContextEnabled: autoContextEnabled,
            analysisDepth: analysisDepth,
            pollJiraEnabled: pollJiraEnabled,
            pollJenkinsEnabled: pollJenkinsEnabled,
            pollGrafanaEnabled: pollGrafanaEnabled,
            pollGitHubEnabled: pollGitHubEnabled,
            pollConfluenceEnabled: pollConfluenceEnabled,
            pollAWSCostsEnabled: pollAWSCostsEnabled,
            systemNotificationsEnabled: systemNotificationsEnabled,
            archiveRetention: archiveRetention.rawValue,
            enabledBriefingTypes: Array(enabledBriefingTypes),
            autoGenerateBriefingsOnLaunch: autoGenerateBriefingsOnLaunch,
            hasCompletedOnboarding: hasCompletedOnboarding,
            dashboardWidgets: dashboardWidgets,
            dashboardMode: dashboardMode,
            bitbucketWorkspace: bitbucketWorkspace.isEmpty ? nil : bitbucketWorkspace,
            githubOrg: githubOrg,
            githubOrgs: githubOrgs.isEmpty ? nil : githubOrgs,
            kbRepoOwner: kbRepoOwner.isEmpty ? nil : kbRepoOwner,
            kbRepoName: kbRepoName.isEmpty ? nil : kbRepoName,
            favoriteJSMTeams: favoriteJSMTeams.isEmpty ? nil : favoriteJSMTeams,
            jsmCloudId: jsmCloudId.isEmpty ? nil : jsmCloudId,
            userProfile: userProfile,
            incidentProductElementFieldId: incidentProductElementFieldId.isEmpty ? nil : incidentProductElementFieldId,
            availableProductElements: availableProductElements.isEmpty ? nil : availableProductElements,
            favoriteProductElements: favoriteProductElements.isEmpty ? nil : favoriteProductElements,
            useCustomIncidentJQL: useCustomIncidentJQL,
            customIncidentJQL: customIncidentJQL.isEmpty ? nil : customIncidentJQL
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    // MARK: - Keychain-backed tokens

    var jiraAPIToken: String {
        get { KeychainHelper.load(key: "jira-api-token") ?? "" }
        set { try? KeychainHelper.save(key: "jira-api-token", value: newValue); objectWillChange.send() }
    }

    var confluenceAPIToken: String {
        get { KeychainHelper.load(key: "confluence-api-token") ?? "" }
        set { try? KeychainHelper.save(key: "confluence-api-token", value: newValue); objectWillChange.send() }
    }

    var bitbucketAPIToken: String {
        get { KeychainHelper.load(key: "bitbucket-api-token") ?? "" }
        set { try? KeychainHelper.save(key: "bitbucket-api-token", value: newValue); objectWillChange.send() }
    }

    var githubToken: String {
        get { KeychainHelper.load(key: "github-token") ?? "" }
        set { try? KeychainHelper.save(key: "github-token", value: newValue); objectWillChange.send() }
    }

    var jenkinsURL: String {
        get { KeychainHelper.load(key: "jenkins-url") ?? "" }
        set { try? KeychainHelper.save(key: "jenkins-url", value: newValue); objectWillChange.send() }
    }

    var jenkinsUsername: String {
        get { KeychainHelper.load(key: "jenkins-username") ?? "" }
        set { try? KeychainHelper.save(key: "jenkins-username", value: newValue); objectWillChange.send() }
    }

    var jenkinsToken: String {
        get { KeychainHelper.load(key: "jenkins-token") ?? "" }
        set { try? KeychainHelper.save(key: "jenkins-token", value: newValue); objectWillChange.send() }
    }

    var grafanaURL: String {
        get { KeychainHelper.load(key: "grafana-url") ?? "" }
        set { try? KeychainHelper.save(key: "grafana-url", value: newValue); objectWillChange.send() }
    }

    var grafanaToken: String {
        get { KeychainHelper.load(key: "grafana-token") ?? "" }
        set { try? KeychainHelper.save(key: "grafana-token", value: newValue); objectWillChange.send() }
    }

    /// OpsGenie / JSM Operations API key — separate from the Jira token.
    /// Auth: `Authorization: GenieKey {jsmOpsAPIKey}`
    var jsmOpsAPIKey: String {
        get { KeychainHelper.load(key: "jsm-ops-api-key") ?? "" }
        set { try? KeychainHelper.save(key: "jsm-ops-api-key", value: newValue); objectWillChange.send() }
    }

    /// Import credentials from auto-discovery into the app state.
    /// Only fills in tokens that are not already saved — never overwrites a
    /// user-configured credential. This prevents stale tokens in MCP credential
    /// files from clobbering valid tokens the user has already set up.
    func importDiscoveredCredentials() {
        let creds = CredentialDiscovery.discover()
        if let email = creds.atlassianEmail,   jiraEmail.isEmpty       { jiraEmail = email }
        if let url   = creds.atlassianBaseURL, jiraBaseURL.isEmpty      { jiraBaseURL = url }
        if let t     = creds.jiraToken,        jiraAPIToken.isEmpty     { jiraAPIToken = t }
        if let t     = creds.confluenceToken,  confluenceAPIToken.isEmpty { confluenceAPIToken = t }
        if let t     = creds.bitbucketToken,   bitbucketAPIToken.isEmpty { bitbucketAPIToken = t }
        if let t     = creds.githubToken,      githubToken.isEmpty      { githubToken = t }
        if let v     = creds.jenkinsURL,       jenkinsURL.isEmpty       { jenkinsURL = v }
        if let v     = creds.jenkinsUsername,  jenkinsUsername.isEmpty  { jenkinsUsername = v }
        if let t     = creds.jenkinsToken,     jenkinsToken.isEmpty     { jenkinsToken = t }
        if let v     = creds.grafanaURL,       grafanaURL.isEmpty       { grafanaURL = v }
        if let t     = creds.grafanaToken,     grafanaToken.isEmpty     { grafanaToken = t }
        if let t     = creds.jsmOpsAPIKey,   jsmOpsAPIKey.isEmpty   { jsmOpsAPIKey = t }
        if let t     = creds.anthropicAPIKey,
           (KeychainHelper.load(key: "anthropic-api-key") ?? "").isEmpty {
            try? KeychainHelper.save(key: "anthropic-api-key", value: t)
        }
        saveConfig()
    }

    var isJiraConfigured: Bool {
        !jiraEmail.isEmpty && !jiraAPIToken.isEmpty && !jiraBaseURL.isEmpty
    }

    var isAWSConfigured: Bool {
        !awsSSOProfile.isEmpty
    }

    // MARK: - Startup health checks

    /// Check all configured services in parallel on app launch.
    /// On first run, auto-discovers credentials from known locations.
    func checkAllServices() {
        // Auto-discover on first run if no tokens are saved
        if jiraAPIToken.isEmpty && confluenceAPIToken.isEmpty && githubToken.isEmpty {
            importDiscoveredCredentials()
        }
        let awsService = AWSAuthService()
        let jiraService = JiraService()
        let confluenceService = ConfluenceService()
        let bitbucketService = BitbucketService()
        let githubService = GitHubService()

        // AWS
        if !awsSSOProfile.isEmpty {
            awsAuthStatus = .checking
            let profile = awsSSOProfile
            Task {
                do {
                    let detail = try await awsService.checkStatus(profile: profile)
                    await MainActor.run { self.awsAuthStatus = .authenticated(detail: detail) }
                } catch is AWSAuthError {
                    await MainActor.run { self.awsAuthStatus = .expired }
                } catch {
                    await MainActor.run { self.awsAuthStatus = .error(error.localizedDescription) }
                }
            }
        }

        // Jira
        if isJiraConfigured {
            jiraAuthStatus = .checking
            let (baseURL, email, token) = (jiraBaseURL, jiraEmail, jiraAPIToken)
            Task {
                do {
                    let name = try await jiraService.checkAuth(baseURL: baseURL, email: email, apiToken: token)
                    await MainActor.run { self.jiraAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.jiraAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            jiraAuthStatus = .notConfigured
        }

        // Confluence
        let confToken = confluenceAPIToken
        if !confToken.isEmpty && !jiraEmail.isEmpty {
            confluenceAuthStatus = .checking
            let (baseURL, email) = (jiraBaseURL, jiraEmail)
            Task {
                do {
                    let name = try await confluenceService.checkAuth(baseURL: baseURL, email: email, apiToken: confToken)
                    await MainActor.run { self.confluenceAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.confluenceAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            confluenceAuthStatus = confToken.isEmpty ? .notConfigured : .notConfigured
        }

        // Bitbucket
        let bbToken = bitbucketAPIToken
        let bbEmail = jiraEmail
        let bbWorkspace = bitbucketWorkspace
        if !bbToken.isEmpty && !bbEmail.isEmpty {
            bitbucketAuthStatus = .checking
            Task {
                do {
                    let name = try await bitbucketService.checkAuth(email: bbEmail, apiToken: bbToken, workspace: bbWorkspace)
                    await MainActor.run { self.bitbucketAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.bitbucketAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else if bbToken.isEmpty {
            bitbucketAuthStatus = .notConfigured
        } else {
            // Token set but email missing
            bitbucketAuthStatus = .error("Email not configured — set Jira email first")
        }

        // GitHub
        let ghToken = githubToken
        if !ghToken.isEmpty {
            githubAuthStatus = .checking
            Task {
                do {
                    let name = try await githubService.checkAuth(token: ghToken)
                    await MainActor.run { self.githubAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.githubAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            githubAuthStatus = .notConfigured
        }

        // Jenkins
        let jkURL = jenkinsURL
        let jkUser = jenkinsUsername
        let jkToken = jenkinsToken
        if !jkToken.isEmpty && !jkURL.isEmpty {
            jenkinsAuthStatus = .checking
            Task {
                do {
                    let url = jkURL.hasSuffix("/") ? jkURL : jkURL + "/"
                    let testURL = URL(string: "\(url)api/json")!
                    var request = URLRequest(url: testURL, timeoutInterval: 15)
                    if let data = "\(jkUser):\(jkToken)".data(using: .utf8) {
                        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                    }
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let http = response as? HTTPURLResponse
                    if let http, (200...299).contains(http.statusCode) {
                        let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "OK"
                        await MainActor.run { self.jenkinsAuthStatus = .authenticated(detail: desc) }
                    } else {
                        await MainActor.run { self.jenkinsAuthStatus = .error("HTTP \(http?.statusCode ?? 0)") }
                    }
                } catch {
                    await MainActor.run { self.jenkinsAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            jenkinsAuthStatus = .notConfigured
        }

        // Grafana
        let gfURL = grafanaURL
        let gfToken = grafanaToken
        if !gfToken.isEmpty && !gfURL.isEmpty {
            grafanaAuthStatus = .checking
            Task {
                do {
                    let url = gfURL.hasSuffix("/") ? gfURL : gfURL + "/"
                    let testURL = URL(string: "\(url)api/org")!
                    var request = URLRequest(url: testURL, timeoutInterval: 15)
                    request.setValue("Bearer \(gfToken)", forHTTPHeaderField: "Authorization")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let http = response as? HTTPURLResponse
                    if let http, (200...299).contains(http.statusCode) {
                        let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String ?? "OK"
                        await MainActor.run { self.grafanaAuthStatus = .authenticated(detail: name) }
                    } else {
                        await MainActor.run { self.grafanaAuthStatus = .error("HTTP \(http?.statusCode ?? 0)") }
                    }
                } catch {
                    await MainActor.run { self.grafanaAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            grafanaAuthStatus = .notConfigured
        }

        // Google Workspace
        if let discovered = GoogleCredentials.discover() {
            googleAuthStatus = .checking
            googleEmail = discovered.email
            let creds = discovered.credentials
            let googleService = GoogleService()
            Task {
                do {
                    let email = try await googleService.checkAuth(credentials: creds)
                    await MainActor.run {
                        self.googleAuthStatus = .authenticated(detail: email)
                        self.googleEmail = email
                    }
                } catch {
                    await MainActor.run { self.googleAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            googleAuthStatus = .notConfigured
        }

        // JSM Operations (OpsGenie)
        let opsKey = jsmOpsAPIKey
        if !opsKey.isEmpty {
            jsmOpsAuthStatus = .checking
            let jsmService = JSMOpsService()
            Task {
                do {
                    let schedules = try await jsmService.listSchedules(apiKey: opsKey)
                    await MainActor.run { self.jsmOpsAuthStatus = .authenticated(detail: "\(schedules.count) schedules") }
                } catch {
                    await MainActor.run { self.jsmOpsAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            jsmOpsAuthStatus = .notConfigured
        }
    }

    /// Load Google credentials from auto-discovered location.
    var googleCredentials: GoogleCredentials? {
        GoogleCredentials.discover()?.credentials
    }

    // MARK: - Factory Reset

    /// Deletes all `.boomi_sre_*` files and resets in-memory state to init defaults.
    /// Does NOT touch ~/.aws, ~/.kiro, ~/.amazonq, or ~/.gitconfig.
    func factoryReset() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let filesToDelete = [
            ".boomi_sre_config.json",
            ".boomi_sre_secrets.json",
            ".boomi_sre_notifications.json",
            ".boomi_sre_chat_history.json",
            ".boomi_sre_briefings.json",
        ]
        for file in filesToDelete {
            try? FileManager.default.removeItem(at: home.appendingPathComponent(file))
        }

        // Reset navigation
        selectedReport = nil
        showSettings = false
        selectedTicketKey = nil
        sidebarCollapsed = false
        viewMode = .chart

        // Reset config
        csvFolder = home.appendingPathComponent("Downloads").path
        awsSSOProfile = "cam-prod-ro-json"
        jiraEmail = ""
        jiraBaseURL = "https://boomii.atlassian.net"
        jiraProjectKeys = ["CAMSRE", "SRE"]
        awsAccountNames = [:]
        githubOrg = "Mashery-Boomi"
        kbRepoOwner = "ascarcel-boomi"
        kbRepoName = "mashery-sre-kb"
        favoriteJSMTeams = []
        jsmCloudId = ""

        // Reset favorites
        favoriteAWSProfiles = []
        favoriteJiraProjects = []
        favoriteConfluenceSpaces = []
        favoriteGitHubRepos = []
        favoriteJenkinsJobs = []
        favoriteGrafanaDashboards = []

        // Reset AI settings
        claudeModel = "claude-sonnet-4-6"
        chatMaxTokens = 4096
        autoContextEnabled = true
        analysisDepth = "standard"

        // Reset poll settings
        pollJiraEnabled = true
        pollJenkinsEnabled = true
        pollGrafanaEnabled = true
        pollGitHubEnabled = true
        pollConfluenceEnabled = true
        pollAWSCostsEnabled = true
        systemNotificationsEnabled = true
        archiveRetention = .hours24
        refreshInterval = 300

        // Reset EA prefs
        enabledBriefingTypes = Set(["morningBrief","emailTriage","preMeetingBrief",
                                    "actionTracker","eodDigest","dailyTicketBrief","claudeUsage"])
        autoGenerateBriefingsOnLaunch = false
        unreadBriefingCount = 0

        // Reset dashboard
        dashboardWidgets = DashboardWidget.defaults
        dashboardMode = "auto"

        // Reset auth statuses
        awsAuthStatus = .unknown
        jiraAuthStatus = .unknown
        confluenceAuthStatus = .unknown
        bitbucketAuthStatus = .unknown
        githubAuthStatus = .unknown
        jenkinsAuthStatus = .unknown
        grafanaAuthStatus = .unknown
        googleAuthStatus = .unknown
        googleEmail = ""

        // Reset counters
        activeIncidentCount = 0
        results = [:]
        runningReports = []

        // Reset profile
        userProfile = .empty

        // Reset incident settings
        incidentProductElementFieldId = ""
        availableProductElements = []
        favoriteProductElements = []
        useCustomIncidentJQL = false
        customIncidentJQL = ""

        // Trigger onboarding wizard
        hasCompletedOnboarding = false
    }

    // MARK: - Profile Discovery

    /// Populates `userProfile` from configured services. Only fills empty fields.
    func discoverProfile() async {
        var profile = await MainActor.run { userProfile }

        // From Git config (~/.gitconfig)
        if let gitName = readGitConfig("user.name"), profile.displayName.isEmpty {
            profile.displayName = gitName
        }
        if let gitEmail = readGitConfig("user.email"), profile.email.isEmpty {
            profile.email = gitEmail
        }

        let (jiraStatus, ghStatus, currentEmail) = await MainActor.run {
            (jiraAuthStatus, githubAuthStatus, jiraEmail)
        }

        // From Jira auth
        if case .authenticated(let detail) = jiraStatus, profile.displayName.isEmpty {
            profile.displayName = detail
        }
        if !currentEmail.isEmpty && profile.email.isEmpty {
            profile.email = currentEmail
        }

        // From GitHub auth — detail is "Name (@login)"
        if case .authenticated(let detail) = ghStatus {
            if let range = detail.range(of: #"\(@([^)]+)\)"#, options: .regularExpression) {
                let match = String(detail[range])
                let handle = String(match.dropFirst(2).dropLast())
                if profile.githubHandle == nil { profile.githubHandle = handle }
            }
            if profile.displayName.isEmpty {
                profile.displayName = detail.components(separatedBy: " (").first ?? detail
            }
        }

        // Avatar from GitHub
        if let handle = profile.githubHandle, profile.avatarURL == nil {
            profile.avatarURL = "https://github.com/\(handle).png?size=128"
        }

        // Time zone: always from system
        profile.timeZone = TimeZone.current.identifier

        await MainActor.run {
            userProfile = profile
            saveConfig()
        }
    }

    private func readGitConfig(_ key: String) -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gitconfig")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return nil }

        // Simple INI parser: find [user] section then look for key = value
        let lines = content.components(separatedBy: .newlines)
        var inUserSection = false
        let sectionKey = key.components(separatedBy: ".").last ?? key

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inUserSection = trimmed.lowercased().hasPrefix("[user]") ||
                                trimmed.lowercased().hasPrefix("[user ")
                continue
            }
            guard inUserSection else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            if k == sectionKey.lowercased() {
                let v = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes if present
                if v.hasPrefix("\"") && v.hasSuffix("\"") {
                    return String(v.dropFirst().dropLast())
                }
                return v
            }
        }
        return nil
    }
}

// MARK: - Supporting types

struct AppConfig: Codable {
    // Core
    var csvFolder: String?
    var awsSSOProfile: String?
    var jiraEmail: String?
    var jiraBaseURL: String?
    var jiraProjectKeys: [String]?
    var awsAccountNames: [String: String]?
    // Favorites
    var favoriteAWSProfiles: [String]?
    var favoriteJiraProjects: [String]?
    var favoriteConfluenceSpaces: [String]?
    var favoriteGitHubRepos: [String]?
    var favoriteJenkinsJobs: [String]?
    var favoriteGrafanaDashboards: [String]?
    // AI Settings
    var claudeModel: String?
    var chatMaxTokens: Int?
    var autoContextEnabled: Bool?
    var analysisDepth: String?
    // Notification prefs
    var pollJiraEnabled: Bool?
    var pollJenkinsEnabled: Bool?
    var pollGrafanaEnabled: Bool?
    var pollGitHubEnabled: Bool?
    var pollConfluenceEnabled: Bool?
    var pollAWSCostsEnabled: Bool?
    var systemNotificationsEnabled: Bool?
    var archiveRetention: String?
    // EA prefs
    var enabledBriefingTypes: [String]?
    var autoGenerateBriefingsOnLaunch: Bool?
    // Onboarding
    var hasCompletedOnboarding: Bool?
    // Dashboard
    var dashboardWidgets: [DashboardWidget]?
    var dashboardMode: String?
    // Bitbucket workspace
    var bitbucketWorkspace: String?
    // GitHub Org
    var githubOrg: String?
    var githubOrgs: [String]?
    // Knowledge Base repo
    var kbRepoOwner: String?
    var kbRepoName: String?
    // JSM On-Call
    var favoriteJSMTeams: [String]?
    var jsmCloudId: String?
    // User Profile
    var userProfile: UserProfile?
    // Incident settings
    var incidentProductElementFieldId: String?
    var availableProductElements: [String]?
    var favoriteProductElements: [String]?
    var useCustomIncidentJQL: Bool?
    var customIncidentJQL: String?
}

enum ViewMode: String, CaseIterable {
    case table = "Table"
    case chart = "Chart"
}

enum AuthStatus: Equatable {
    case unknown
    case checking
    case authenticated(detail: String)
    case expired
    case notConfigured
    case error(String)

    var isOK: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking..."
        case .authenticated(let detail): return "Connected: \(detail)"
        case .expired: return "Session expired"
        case .notConfigured: return "Not configured"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .authenticated: return .green
        case .expired, .error: return .red
        case .checking: return .orange
        default: return .secondary
        }
    }
}

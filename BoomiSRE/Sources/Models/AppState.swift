import Foundation
import SwiftUI

/// Central app state shared across all views.
final class AppState: ObservableObject {
    // Navigation
    @Published var selectedReport: ReportItem?
    @Published var showSettings = false
    @Published var selectedSettingsTab: String = "profile"   // deep-link into a specific tab
    @Published var selectedTicketKey: String?  // opens ticket detail view
    @Published var pendingCopilotPrompt: String? // pre-fill Copilot from feed actions
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
    @Published var copilotAutoSummaryOnLaunch: Bool = false

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
    @Published var storyPointsFieldId: String = "customfield_10008"  // configurable per Jira instance
    @Published var availableProductElements: [String] = []      // all discovered values
    @Published var favoriteProductElements: [String] = []       // user's selected favorites
    @Published var useCustomIncidentJQL: Bool = false
    @Published var customIncidentJQL: String = ""

    // Onboarding
    @Published var hasCompletedOnboarding: Bool = false

    // Dashboard
    @Published var dashboardWidgets: [DashboardWidget] = DashboardWidget.defaults
    @Published var dashboardMode: String = "feed"
    @Published var dashboardColumns: Int = 3           // grid columns: 1, 2, 3, or 4
    @Published var appTheme: String = "system"         // "system" or "boomi"

    // Jenkins (multi-server)
    @Published var jenkinsServers: [JenkinsServer] = []

    // Team Presence (P2P)
    @Published var peerPresenceEnabled: Bool = false

    // SLOs
    @Published var sloDefinitions: [SLODefinition] = []
    @Published var prometheusDataSourceUID: String = ""

    // Product Context (definition / metadata — name, icon, description, escalation, runbooks)
    @Published var products: [ProductContext] = ProductContext.defaults

    // Product Resource Maps — split into team template + user additions
    @Published var teamResourceMaps: [ProductResourceMap] = []
    @Published var userResourceAdditions: [ProductResourceMap] = []

    /// Merged view: team resources (marked `isTeamDefault = true`) + user additions (marked `isTeamDefault = false`).
    /// Duplicate user additions (same id + type as a team resource) are skipped.
    var productResourceMaps: [ProductResourceMap] {
        get {
            let userById = Dictionary(uniqueKeysWithValues: userResourceAdditions.map { ($0.id, $0) })
            return teamResourceMaps.map { teamMap in
                var merged = teamMap
                // Mark all team resources
                for i in merged.resources.indices {
                    merged.resources[i].isTeamDefault = true
                }
                // Append non-duplicate user additions
                if let userMap = userById[teamMap.id] {
                    let teamKeys = Set(teamMap.resources.map { $0.id + "|" + $0.type.rawValue })
                    for var res in userMap.resources {
                        let key = res.id + "|" + res.type.rawValue
                        if !teamKeys.contains(key) {
                            res.isTeamDefault = false
                            merged.resources.append(res)
                        }
                    }
                }
                return merged
            }
        }
        set {
            // Backward-compat setter — routes to teamResourceMaps
            teamResourceMaps = newValue
        }
    }

    // Active product filter — multi-select; empty = "All Products" (no filter)
    // Replaces selectedProductId for multi-product support.
    @Published var activeProductIds: Set<String> = []

    // Legacy single-select (kept for backward compat — derived from activeProductIds)
    var selectedProductId: String {
        get { activeProductIds.count == 1 ? (activeProductIds.first ?? "all") : "all" }
    }

    // Sidebar selection (flat 7-item sidebar — persisted across sessions)
    @Published var selectedSidebarItem: String = "home"

    /// Deep-link tab within the target panel. Panels observe this in onAppear/onChange
    /// and consume it (set to nil) after applying. Format: the reportId string.
    @Published var pendingTabId: String?

    /// Current sub-tab label within the active panel (for breadcrumb display).
    @Published var currentSubTab: String?

    // MARK: - Navigation Stack

    struct NavigationEntry: Equatable {
        let sidebarItem: String
        let subTab: String?
        let ticketKey: String?
    }

    @Published var navigationStack: [NavigationEntry] = []
    private let maxHistorySize = 20

    var canGoBack: Bool { !navigationStack.isEmpty }

    func pushNavigation() {
        let entry = NavigationEntry(
            sidebarItem: selectedSidebarItem,
            subTab: currentSubTab,
            ticketKey: selectedTicketKey
        )
        guard navigationStack.last != entry else { return }
        navigationStack.append(entry)
        if navigationStack.count > maxHistorySize { navigationStack.removeFirst() }
    }

    func popNavigation() {
        guard let entry = navigationStack.popLast() else { return }
        selectedTicketKey = nil
        showSettings = false
        selectedSidebarItem = entry.sidebarItem
        currentSubTab = entry.subTab
        if let tab = entry.subTab { pendingTabId = tab }
    }

    // Current screen context for AI (transient — not persisted)
    @Published var currentScreenContext: String = ""

    var selectedProduct: ProductContext? {
        guard activeProductIds.count == 1, let id = activeProductIds.first else { return nil }
        return products.first { $0.id == id }
    }

    var isAllProducts: Bool { activeProductIds.isEmpty }

    // MARK: - Product Resource Map helpers

    /// Resource maps for the currently active products (all maps if no filter set).
    var activeProductMaps: [ProductResourceMap] {
        if activeProductIds.isEmpty {
            return productResourceMaps
        }
        return productResourceMaps.filter { activeProductIds.contains($0.id) }
    }

    /// Resource map for a specific product by ID (creates an empty one if missing).
    func resourceMap(for productId: String) -> ProductResourceMap {
        productResourceMaps.first { $0.id == productId } ?? .empty(for: productId)
    }

    /// Union of all confirmed Jira project keys across active products.
    /// Falls back to `jiraProjectKeys` if no maps are configured yet.
    var activeJiraProjectKeys: [String] {
        let mapped = activeProductMaps.flatMap { $0.confirmedIds(.jiraProject) }
        return mapped.isEmpty ? jiraProjectKeys : Array(Set(mapped))
    }

    /// Union of all confirmed GitHub repos across active products.
    var activeGitHubRepos: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.githubRepo) }))
    }

    /// Union of all confirmed Bitbucket repos across active products.
    var activeBitbucketRepos: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.bitbucketRepo) }))
    }

    /// Union of all confirmed Jenkins jobs across active products.
    var activeJenkinsJobs: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.jenkinsJob) }))
    }

    /// Union of all confirmed Jenkins view names across active products.
    var activeJenkinsViews: [String] {
        activeProductMaps.flatMap { $0.confirmed(.jenkinsView) }.map { $0.name }
    }

    /// Union of all confirmed Grafana dashboard UIDs across active products.
    var activeGrafanaDashboards: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.grafanaDashboard) }))
    }

    /// Union of all confirmed Grafana folder UIDs across active products.
    var activeGrafanaFolderUIDs: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.grafanaFolder) }))
    }

    /// Union of all confirmed Confluence spaces across active products.
    var activeConfluenceSpaces: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.confluenceSpace) }))
    }

    /// Union of all confirmed AWS accounts across active products.
    var activeAWSAccounts: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.awsAccount) }))
    }

    /// Union of all confirmed JSM team IDs across active products.
    var activeJSMTeamIds: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.jsmTeam) }))
    }

    /// Union of all confirmed incident product elements across active products.
    var activeIncidentProductElements: [String] {
        Array(Set(activeProductMaps.flatMap { $0.confirmedIds(.incidentProductElement) }))
    }

    /// Total pending (unreviewed AI suggestion) count across all product maps.
    var totalPendingResourceCount: Int {
        productResourceMaps.reduce(0) { $0 + $1.pendingCount }
    }

    /// Mutate a product resource map and persist immediately.
    @MainActor
    func updateResourceMap(_ map: ProductResourceMap) {
        if let idx = productResourceMaps.firstIndex(where: { $0.id == map.id }) {
            productResourceMaps[idx] = map
        } else {
            productResourceMaps.append(map)
        }
        saveConfig()
    }

    /// Ensure a resource map exists for every product (creates empty ones if needed).
    func ensureResourceMapsExist() {
        // If no maps at all, try to load from the bundled default template
        if teamResourceMaps.isEmpty, let defaults = Self.loadBundledDefaultMaps() {
            teamResourceMaps = defaults
        }
        // Ensure every product has a map (fills gaps for any products not in template)
        for product in products where product.id != "all" {
            if !teamResourceMaps.contains(where: { $0.id == product.id }) {
                teamResourceMaps.append(.migrated(from: product))
            }
        }
    }

    /// Load the bundled default resource maps template (shipped with the app).
    private static func loadBundledDefaultMaps() -> [ProductResourceMap]? {
        guard let url = Bundle.module.url(forResource: "default_product_maps", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let maps = try? decoder.decode([ProductResourceMap].self, from: data),
              !maps.isEmpty else { return nil }
        return maps
    }

    /// Save the current confirmed resource maps as the bundled default template.
    /// Writes to the repo's Resources directory so it ships with future builds.
    @Published var lastTemplateError: String?
    @Published var saveError: String?

    func saveAsDefaultTemplate() -> Bool {
        lastTemplateError = nil
        // Strip pending/unconfirmed resources — only export confirmed mappings
        var templateMaps: [ProductResourceMap] = []
        for var map in teamResourceMaps {
            map.resources = map.resources.filter { $0.isConfirmed }
            for i in map.resources.indices {
                map.resources[i].aiSuggested = false
                map.resources[i].confidence = nil
            }
            map.lastDiscoveredAt = nil  // transient — don't bundle
            templateMaps.append(map)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(templateMaps)
        } catch {
            lastTemplateError = "Encode failed: \(error.localizedDescription)"
            return false
        }

        // Write to the repo source — will be picked up by the next build
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirPath = "\(home)/github/Boomi-SRE/BoomiSRE/Sources/Resources"
        let filePath = "\(dirPath)/default_product_maps.json"

        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        do {
            try data.write(to: URL(fileURLWithPath: filePath))
            return true
        } catch {
            lastTemplateError = "Write failed: \(error.localizedDescription)"
            return false
        }
    }

    // Bitbucket
    @Published var bitbucketWorkspace: String = "boomii"
    @Published var bitbucketUsername: String = ""

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

    // Per-widget filters — [widgetTypeRawValue: [filterKey: filterValue]]
    @Published var widgetFilters: [String: [String: String]] = [:]

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
    @Published var gmailSavedQueries: [GmailSavedQuery] = GmailSavedQuery.defaults

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
        CredentialDiscovery.ensureCredentialDir()
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
        if let v = config.copilotAutoSummaryOnLaunch { copilotAutoSummaryOnLaunch = v }
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
        if let v = config.dashboardWidgets {
            dashboardWidgets = v
        } else {
            dashboardWidgets = DashboardWidget.defaults
        }
        // Ensure all widget types present (handles app upgrades adding new widget types)
        let existing = Set(dashboardWidgets.map(\.type))
        var nextPos = (dashboardWidgets.map(\.position).max() ?? -1) + 1
        for def in DashboardWidget.defaults where !existing.contains(def.type) {
            dashboardWidgets.append(DashboardWidget(type: def.type, position: nextPos))
            nextPos += 1
        }
        if let v = config.dashboardMode { dashboardMode = v }
        if let v = config.dashboardColumns { dashboardColumns = v }
        if let v = config.bitbucketWorkspace { bitbucketWorkspace = v }
        if let v = config.bitbucketUsername { bitbucketUsername = v }
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
        if let v = config.storyPointsFieldId { storyPointsFieldId = v }
        if let v = config.availableProductElements { availableProductElements = v }
        if let v = config.favoriteProductElements { favoriteProductElements = v }
        if let v = config.useCustomIncidentJQL { useCustomIncidentJQL = v }
        if let v = config.customIncidentJQL { customIncidentJQL = v }
        // Products: always use built-in defaults for names/icons/metadata.
        // Saved product definitions are ignored — only the team template and user
        // additions carry resource mappings forward.
        products = ProductContext.defaults

        // Resource maps: team defaults ALWAYS come from the bundled template.
        // The config's productResourceMaps (if present and no userResourceAdditions yet)
        // are treated as a legacy migration — they become user additions so the bundled
        // team template isn't overridden.
        if let v = config.userResourceAdditions {
            userResourceAdditions = v
        } else if let v = config.productResourceMaps {
            // Legacy migration: old config had a single productResourceMaps.
            // Load as user additions — team maps come from the bundle.
            userResourceAdditions = v
        }
        if let v = config.activeProductIds { activeProductIds = Set(v) }
        else if let v = config.selectedProductId, v != "all" { activeProductIds = [v] }
        if let v = config.jenkinsServers { jenkinsServers = v }
        if let v = config.peerPresenceEnabled { peerPresenceEnabled = v }
        if let v = config.sloDefinitions { sloDefinitions = v }
        if let v = config.prometheusDataSourceUID { prometheusDataSourceUID = v }
        if let v = config.gmailSavedQueries { gmailSavedQueries = v }
        // Migrate single Jenkins server to multi-server if needed
        if jenkinsServers.isEmpty && !jenkinsURL.isEmpty {
            jenkinsServers = [JenkinsServer(
                id: UUID().uuidString, name: "Jenkins Primary",
                url: jenkinsURL, username: jenkinsUsername, token: jenkinsToken
            )]
        }
        if let v = config.selectedSidebarItem { selectedSidebarItem = v }
        if let v = config.appTheme { appTheme = v }
        ensureResourceMapsExist()
        // Seed active filter from user's "My Products" if nothing is persisted yet
        if activeProductIds.isEmpty && !userProfile.myProducts.isEmpty {
            activeProductIds = userProfile.myProducts
        }
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
            copilotAutoSummaryOnLaunch: copilotAutoSummaryOnLaunch ? true : nil,
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
            dashboardColumns: dashboardColumns,
            bitbucketWorkspace: bitbucketWorkspace.isEmpty ? nil : bitbucketWorkspace,
            bitbucketUsername: bitbucketUsername.isEmpty ? nil : bitbucketUsername,
            githubOrg: githubOrg,
            githubOrgs: githubOrgs.isEmpty ? nil : githubOrgs,
            kbRepoOwner: kbRepoOwner.isEmpty ? nil : kbRepoOwner,
            kbRepoName: kbRepoName.isEmpty ? nil : kbRepoName,
            favoriteJSMTeams: favoriteJSMTeams.isEmpty ? nil : favoriteJSMTeams,
            jsmCloudId: jsmCloudId.isEmpty ? nil : jsmCloudId,
            userProfile: userProfile,
            incidentProductElementFieldId: incidentProductElementFieldId.isEmpty ? nil : incidentProductElementFieldId,
            storyPointsFieldId: storyPointsFieldId == "customfield_10008" ? nil : storyPointsFieldId,
            availableProductElements: availableProductElements.isEmpty ? nil : availableProductElements,
            favoriteProductElements: favoriteProductElements.isEmpty ? nil : favoriteProductElements,
            useCustomIncidentJQL: useCustomIncidentJQL,
            customIncidentJQL: customIncidentJQL.isEmpty ? nil : customIncidentJQL,
            products: nil,  // Always use built-in defaults — don't persist product metadata
            productResourceMaps: nil,  // Team maps come from bundled template, not config
            userResourceAdditions: userResourceAdditions.isEmpty ? nil : userResourceAdditions,
            activeProductIds: activeProductIds.isEmpty ? nil : Array(activeProductIds),
            selectedProductId: nil,
            selectedSidebarItem: selectedSidebarItem == "home" ? nil : selectedSidebarItem,
            appTheme: appTheme == "system" ? nil : appTheme,
            jenkinsServers: jenkinsServers.isEmpty ? nil : jenkinsServers,
            peerPresenceEnabled: peerPresenceEnabled ? true : nil,
            sloDefinitions: sloDefinitions.isEmpty ? nil : sloDefinitions,
            prometheusDataSourceUID: prometheusDataSourceUID.isEmpty ? nil : prometheusDataSourceUID,
            gmailSavedQueries: gmailSavedQueries == GmailSavedQuery.defaults ? nil : gmailSavedQueries
        )
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            saveError = nil
        } catch {
            saveError = "Failed to save config: \(error.localizedDescription)"
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

    /// Bitbucket Cloud uses scoped API tokens with email:token Basic auth.
    /// Falls back to jiraEmail if bitbucketUsername is not set.
    var bitbucketAuthUser: String {
        bitbucketUsername.isEmpty ? jiraEmail : bitbucketUsername
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

    /// Optional JSM Ops GenieKey (reserved for future use).
    /// Alerts and schedules now use the Atlassian API with standard Jira Basic auth — no separate key needed.
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
        if let v     = creds.bitbucketUsername, bitbucketUsername.isEmpty { bitbucketUsername = v }
        if let t     = creds.githubToken,      githubToken.isEmpty      { githubToken = t }
        if let v     = creds.jenkinsURL,       jenkinsURL.isEmpty       { jenkinsURL = v }
        if let v     = creds.jenkinsUsername,  jenkinsUsername.isEmpty  { jenkinsUsername = v }
        if let t     = creds.jenkinsToken,     jenkinsToken.isEmpty     { jenkinsToken = t }
        if let v     = creds.grafanaURL,       grafanaURL.isEmpty       { grafanaURL = v }
        if let t     = creds.grafanaToken,     grafanaToken.isEmpty     { grafanaToken = t }
        if let t     = creds.anthropicAPIKey,
           (KeychainHelper.load(key: "anthropic-api-key") ?? "").isEmpty {
            try? KeychainHelper.save(key: "anthropic-api-key", value: t)
        }

        // Copy discovered credentials into ~/.boomi-sre/credentials/
        CredentialDiscovery.persistDiscovered(creds)
        CredentialDiscovery.importGoogleCredentialsFromMCP()

        saveConfig()
    }

    var isJiraConfigured: Bool {
        !jiraEmail.isEmpty && !jiraAPIToken.isEmpty && !jiraBaseURL.isEmpty
    }

    var isAWSConfigured: Bool {
        !awsSSOProfile.isEmpty
    }

    // MARK: - Unified Navigation

    /// Navigate to a feature by its report ID, mapping to the correct sidebar panel.
    /// All navigation (widgets, feed, toolbar, keyboard shortcuts) should go through here.
    func navigate(to reportId: String) {
        pushNavigation()
        showSettings = false
        selectedTicketKey = nil
        selectedReport = nil   // clear so detailContent routes via selectedSidebarItem
        currentSubTab = nil    // panels will set this when their tab activates
        pendingTabId = reportId  // panels consume this to select the right tab

        switch reportId {
        case "oncall", "notifications", "grafana_browser", "slo_dashboard":
            selectedSidebarItem = "alerts"
        case "incidents":
            selectedSidebarItem = "incidents"
        case "jira_todo", "jira_filters", "jira_boards", "jenkins_browser":
            selectedSidebarItem = "mywork"
        case "github_browser", "aws_health", "aws_cost_explorer", "bitbucket_browser":
            selectedSidebarItem = "infra"
        case "knowledge_base", "confluence_browser", "copilot_chat", "exec_assistant", "skills":
            selectedSidebarItem = "knowledge"
        case "google_gmail", "google_calendar":
            selectedSidebarItem = "communicate"
        case "settings_integrations":
            pendingTabId = nil
            showSettings = true
            selectedSettingsTab = "jira"  // first integration tab
        default:
            pendingTabId = nil
            if let report = ReportCatalog.all.first(where: { $0.id == reportId }) {
                selectedReport = report
            }
        }
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

        // Bitbucket — scoped API tokens use Atlassian email (same as Jira)
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
            bitbucketAuthStatus = .error("Jira email not configured — needed for Bitbucket auth")
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
                    guard let testURL = URL(string: "\(url)api/json") else {
                        await MainActor.run { self.jenkinsAuthStatus = .error("Invalid Jenkins URL") }
                        return
                    }
                    var request = URLRequest(url: testURL, timeoutInterval: 15)
                    if let data = "\(jkUser):\(jkToken)".data(using: .utf8) {
                        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                    }
                    let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
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
                    guard let testURL = URL(string: "\(url)api/org") else {
                        await MainActor.run { self.grafanaAuthStatus = .error("Invalid Grafana URL") }
                        return
                    }
                    var request = URLRequest(url: testURL, timeoutInterval: 15)
                    request.setValue("Bearer \(gfToken)", forHTTPHeaderField: "Authorization")
                    let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
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

        // JSM Operations (uses Jira credentials — no separate API key needed for schedules)
        let jsmService = JSMOpsService()
        if isJiraConfigured {
            jsmOpsAuthStatus = .checking
            let jsmURL = jiraBaseURL; let jsmEmail = jiraEmail; let jsmToken = jiraAPIToken
            Task {
                do {
                    let schedules = try await jsmService.listSchedules(baseURL: jsmURL, email: jsmEmail, apiToken: jsmToken)
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
            ".boomi_sre_productivity.json",
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
        dashboardMode = "feed"
        dashboardColumns = 3

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
        storyPointsFieldId = "customfield_10008"
        availableProductElements = []
        favoriteProductElements = []
        useCustomIncidentJQL = false
        customIncidentJQL = ""
        products = ProductContext.defaults
        // Reload resource maps from the bundled team template (not stubs)
        if let bundled = Self.loadBundledDefaultMaps() {
            teamResourceMaps = bundled
        } else {
            teamResourceMaps = ProductContext.defaults
                .filter { $0.id != "all" }
                .map { .migrated(from: $0) }
        }
        userResourceAdditions = []
        activeProductIds = []
        selectedSidebarItem = "home"
        appTheme = "system"

        // Clear productivity tracker in-memory
        Task { await ProductivityTracker.shared.resetAll() }

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

        let finalProfile = profile
        await MainActor.run {
            userProfile = finalProfile
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
    var copilotAutoSummaryOnLaunch: Bool?
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
    var dashboardColumns: Int?
    // Bitbucket workspace
    var bitbucketWorkspace: String?
    var bitbucketUsername: String?
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
    var storyPointsFieldId: String?
    var availableProductElements: [String]?
    var favoriteProductElements: [String]?
    var useCustomIncidentJQL: Bool?
    var customIncidentJQL: String?
    var products: [ProductContext]?
    var productResourceMaps: [ProductResourceMap]?
    var userResourceAdditions: [ProductResourceMap]?
    var activeProductIds: [String]?
    var selectedProductId: String?   // legacy — migrated to activeProductIds on load
    var selectedSidebarItem: String?
    var appTheme: String?
    var jenkinsServers: [JenkinsServer]?
    var peerPresenceEnabled: Bool?
    var sloDefinitions: [SLODefinition]?
    var prometheusDataSourceUID: String?
    var gmailSavedQueries: [GmailSavedQuery]?
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

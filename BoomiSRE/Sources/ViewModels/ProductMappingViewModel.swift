import Foundation
import SwiftUI

// MARK: - ProductMappingViewModel

@MainActor
final class ProductMappingViewModel: ObservableObject {

    // MARK: UI State

    @Published var selectedProductId: String = ""
    @Published var selectedIntegration: String = "Jira"

    // Discovery state
    @Published var isDiscovering = false
    @Published var discoveryProgress: String = ""
    @Published var discoveryError: String?

    /// Resources fetched from live APIs — backed by a singleton in-memory cache.
    /// Key: integration name (e.g. "Jira", "GitHub")
    @Published var discoveredByIntegration: [String: [MappedResource]] = [:] {
        didSet { DiscoveryCache.shared.update(discoveredByIntegration) }
    }

    // Manual add state
    @Published var manualAddId: String = ""
    @Published var manualAddName: String = ""
    @Published var manualAddType: MappedResourceType = .jiraProject

    // AI Chat state
    @Published var chatInput: String = ""
    @Published var chatHistory: [(role: String, text: String)] = []
    @Published var isProcessingChat = false
    @Published var chatError: String?

    // Pending AI operations (from chat) — shown for user review before applying
    @Published var pendingOps: [ResourceDiscoveryService.AIResourceOperation] = []

    init() {
        discoveredByIntegration = DiscoveryCache.shared.data
    }

    // MARK: Computed

    /// All discovered resources for the currently selected integration (flat list).
    func discovered(for integration: String) -> [MappedResource] {
        discoveredByIntegration[integration] ?? []
    }

    /// Available resources: discovered but not yet in the product's confirmed/pending list.
    /// Uses a pre-built Set for O(1) lookup instead of scanning on every call.
    func available(for integration: String, in map: ProductResourceMap) -> [MappedResource] {
        let existingIds = Set(map.resources.map { $0.id + "|" + $0.type.rawValue })
        return discovered(for: integration).filter { r in
            !existingIds.contains(r.id + "|" + r.type.rawValue)
        }
    }

    var hasDiscoveredAnything: Bool {
        discoveredByIntegration.values.contains { !$0.isEmpty }
    }

    var allDiscovered: [MappedResource] {
        discoveredByIntegration.values.flatMap { $0 }
    }

    // MARK: - Discovery (per-integration)

    /// Discover resources for a single integration (API fetch only — no AI).
    func discoverIntegration(_ integration: String, for productId: String, appState: AppState) async {
        isDiscovering = true
        discoveryError = nil
        discoveryProgress = "Fetching \(integration) resources..."

        var resources: [MappedResource] = []
        do {
            resources = try await fetchResources(for: integration, appState: appState)
        } catch {
            discoveryError = "\(integration): \(error.localizedDescription)"
        }

        if resources.isEmpty && discoveryError == nil {
            discoveryError = "No \(integration) resources found (check credentials in Settings)."
        }

        if !resources.isEmpty {
            discoveredByIntegration[integration] = resources
        }

        var map = appState.resourceMap(for: productId)
        map.lastDiscoveredAt = Date()
        appState.updateResourceMap(map)

        isDiscovering = false
        discoveryProgress = ""
    }

    // MARK: - AI Suggest (separate from discovery)

    @Published var isAnalyzing = false

    /// Run AI analysis on already-discovered resources for a given integration.
    func suggestMappings(integration: String, for productId: String, appState: AppState) async {
        let resources = discoveredByIntegration[integration] ?? []
        guard !resources.isEmpty else {
            discoveryError = "Discover \(integration) resources first."
            return
        }
        guard let product = appState.products.first(where: { $0.id == productId }) else { return }

        isAnalyzing = true
        discoveryError = nil
        discoveryProgress = "AI analyzing \(resources.count) \(integration) resources..."

        do {
            let suggestions = try await ResourceDiscoveryService.suggestMappings(
                discovered: resources,
                for: product,
                modelOverride: appState.claudeModel
            )
            var map = appState.resourceMap(for: productId)
            for suggestion in suggestions {
                if !map.resources.contains(where: { $0.id == suggestion.id && $0.type == suggestion.type && $0.isConfirmed }) {
                    map.upsert(suggestion)
                }
            }
            appState.updateResourceMap(map)
            discoveryProgress = suggestions.isEmpty ? "No suggestions for this product." : "\(suggestions.count) suggestions added."
        } catch {
            discoveryError = "AI: \(error.localizedDescription.prefix(300))"
        }

        isAnalyzing = false
    }

    /// Discover ALL integrations in parallel (no AI step — just fetches resources).
    func discoverAll(for productId: String, appState: AppState) async {
        isDiscovering = true
        discoveryError = nil
        // Don't clear cache — discovered resources are global, shared across all products

        let integrations = ["Jira", "Confluence", "GitHub", "Bitbucket", "Jenkins", "Grafana", "AWS"]

        await withTaskGroup(of: (String, [MappedResource])?.self) { group in
            for integration in integrations {
                group.addTask { [self] in
                    do {
                        let resources = try await self.fetchResources(for: integration, appState: appState)
                        return resources.isEmpty ? nil : (integration, resources)
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let (integration, resources) = result {
                    discoveredByIntegration[integration] = resources
                    discoveryProgress = "Discovered \(discoveredByIntegration.values.flatMap { $0 }.count) resources (\(discoveredByIntegration.count) integrations)..."
                }
            }
        }

        var map = appState.resourceMap(for: productId)
        map.lastDiscoveredAt = Date()
        appState.updateResourceMap(map)

        isDiscovering = false
        discoveryProgress = ""
    }

    // MARK: - Per-Integration Fetch

    private func fetchResources(for integration: String, appState: AppState) async throws -> [MappedResource] {
        switch integration {
        case "Jira":
            guard appState.isJiraConfigured else { return [] }
            var all: [MappedResource] = []
            // Projects
            all += (try? await ResourceDiscoveryService.fetchJiraProjects(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken)) ?? []
            // Filters
            all += (try? await ResourceDiscoveryService.fetchJiraFilters(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken)) ?? []
            // Boards
            all += (try? await ResourceDiscoveryService.fetchJiraBoards(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken)) ?? []
            // JSM Teams
            all += (try? await ResourceDiscoveryService.fetchJSMTeams(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken)) ?? []
            // Incident Product Elements
            all += (try? await ResourceDiscoveryService.fetchIncidentProductElements(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken,
                fieldId: appState.incidentProductElementFieldId)) ?? []
            return all
        case "Confluence":
            guard !appState.confluenceAPIToken.isEmpty && appState.isJiraConfigured else { return [] }
            return try await ResourceDiscoveryService.fetchConfluenceSpaces(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.confluenceAPIToken)
        case "GitHub":
            guard !appState.githubToken.isEmpty && !appState.githubOrgs.isEmpty else { return [] }
            return try await ResourceDiscoveryService.fetchGitHubRepos(
                token: appState.githubToken, orgs: appState.githubOrgs)
        case "Bitbucket":
            guard !appState.bitbucketAPIToken.isEmpty && !appState.jiraEmail.isEmpty else { return [] }
            return try await ResourceDiscoveryService.fetchBitbucketRepos(
                workspace: appState.bitbucketWorkspace, email: appState.jiraEmail, token: appState.bitbucketAPIToken)
        case "Jenkins":
            guard !appState.jenkinsServers.isEmpty else {
                // Fallback to legacy single-server
                guard !appState.jenkinsToken.isEmpty && !appState.jenkinsURL.isEmpty else { return [] }
                return try await ResourceDiscoveryService.fetchJenkinsResources(
                    servers: [JenkinsServer(id: "legacy", name: "Jenkins", url: appState.jenkinsURL,
                                           username: appState.jenkinsUsername, token: appState.jenkinsToken)])
            }
            return try await ResourceDiscoveryService.fetchJenkinsResources(servers: appState.jenkinsServers)
        case "Grafana":
            guard !appState.grafanaToken.isEmpty && !appState.grafanaURL.isEmpty else { return [] }
            return try await ResourceDiscoveryService.fetchGrafanaResources(
                baseURL: appState.grafanaURL, token: appState.grafanaToken)
        case "AWS":
            // Try IAM Identity Center (SSO) first — shows ALL accounts with friendly names
            let authService = AWSAuthService()
            if let ssoAccounts = try? await authService.listSSOAccounts(), !ssoAccounts.isEmpty {
                return ssoAccounts.map { a in
                    MappedResource(
                        id: a.accountId,
                        name: a.accountName,
                        type: .awsAccount,
                        isConfirmed: false, aiSuggested: false,
                        url: nil,
                        description: "Account ID: \(a.accountId)",
                        addedAt: Date()
                    )
                }
            }
            // Fallback: local ~/.aws/config profiles
            let profiles = authService.listProfiles()
            guard !profiles.isEmpty else { return [] }
            return profiles.compactMap { p in
                guard !p.accountId.isEmpty else { return nil }
                let name = p.friendlyName.isEmpty ? p.name : p.friendlyName
                return MappedResource(
                    id: p.accountId,
                    name: name,
                    type: .awsAccount,
                    isConfirmed: false, aiSuggested: false,
                    url: nil,
                    description: "Account ID: \(p.accountId) · \(p.region)",
                    addedAt: Date()
                )
            }
        default:
            return []
        }
    }

    // MARK: - AI Chat

    func submitChat(for productId: String, appState: AppState) async {
        let input = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        chatInput = ""
        chatHistory.append((role: "user", text: input))
        isProcessingChat = true
        chatError = nil
        pendingOps = []

        guard let product = appState.products.first(where: { $0.id == productId }) else {
            chatError = "Product not found"
            isProcessingChat = false
            return
        }

        let map = appState.resourceMap(for: productId)

        do {
            let (text, ops) = try await ResourceDiscoveryService.processChatCommand(
                userMessage: input,
                product: product,
                currentMap: map,
                available: allDiscovered,
                modelOverride: appState.claudeModel
            )
            chatHistory.append((role: "assistant", text: text))
            pendingOps = ops
        } catch {
            chatError = error.localizedDescription
            chatHistory.append((role: "assistant", text: "Sorry, I encountered an error: \(error.localizedDescription)"))
        }

        isProcessingChat = false
    }

    func applyPendingOps(for productId: String, appState: AppState) {
        var map = appState.resourceMap(for: productId)
        let now = Date()

        for op in pendingOps {
            guard let type = MappedResourceType(rawValue: op.type) else { continue }
            if op.action == "add" {
                // Find in discovered pool or create from op info
                let resource = allDiscovered.first(where: { $0.id == op.id && $0.type == type })
                    ?? MappedResource(
                        id: op.id, name: op.id, type: type,
                        isConfirmed: true, aiSuggested: true,
                        confidence: nil,
                        url: nil, description: op.reason, addedAt: now
                    )
                var confirmed = resource
                confirmed.isConfirmed = true
                map.upsert(confirmed)
            } else if op.action == "remove" {
                map.remove(id: op.id, type: type)
            }
        }

        appState.updateResourceMap(map)
        pendingOps = []
        chatHistory.append((role: "assistant", text: "✓ Changes applied to \(map.id)."))
    }

    func dismissPendingOps() {
        pendingOps = []
        chatHistory.append((role: "assistant", text: "Changes dismissed."))
    }

    // MARK: - Manual Mutations (called from UI)

    func addManual(to productId: String, appState: AppState) {
        let id = manualAddId.trimmingCharacters(in: .whitespaces)
        let name = manualAddName.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }

        var map = appState.resourceMap(for: productId)
        map.upsert(MappedResource(
            id: id,
            name: name.isEmpty ? id : name,
            type: manualAddType,
            isConfirmed: true,
            aiSuggested: false,
            confidence: nil,
            url: nil,
            description: nil,
            addedAt: Date()
        ))
        appState.updateResourceMap(map)
        manualAddId = ""
        manualAddName = ""
    }

    func addResource(_ resource: MappedResource, to productId: String, appState: AppState) {
        addUserResource(resource, to: productId, appState: appState)
    }

    func removeResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
        removeUserResource(id: id, type: type, from: productId, appState: appState)
    }

    // MARK: - User Resource Additions

    /// Add a resource to the user's personal additions layer.
    func addUserResource(_ resource: MappedResource, to productId: String, appState: AppState) {
        var map = appState.userResourceAdditions.first(where: { $0.id == productId })
            ?? .empty(for: productId)
        var confirmed = resource
        confirmed.isConfirmed = true
        confirmed.isTeamDefault = false
        map.upsert(confirmed)
        if let idx = appState.userResourceAdditions.firstIndex(where: { $0.id == productId }) {
            appState.userResourceAdditions[idx] = map
        } else {
            appState.userResourceAdditions.append(map)
        }
        appState.saveConfig()
    }

    /// Remove a resource from the user's personal additions layer only.
    func removeUserResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
        guard let idx = appState.userResourceAdditions.firstIndex(where: { $0.id == productId }) else { return }
        appState.userResourceAdditions[idx].remove(id: id, type: type)
        appState.saveConfig()
    }

    // MARK: - Team Template Mutations (Director/Manager only)

    /// Add a resource to the team template (requires Director or Manager role).
    func addTeamResource(_ resource: MappedResource, to productId: String, appState: AppState) {
        guard appState.userProfile.role.canEditTeamTemplate else { return }
        var map = appState.teamResourceMaps.first(where: { $0.id == productId })
            ?? .empty(for: productId)
        var confirmed = resource
        confirmed.isConfirmed = true
        confirmed.isTeamDefault = true
        map.upsert(confirmed)
        if let idx = appState.teamResourceMaps.firstIndex(where: { $0.id == productId }) {
            appState.teamResourceMaps[idx] = map
        } else {
            appState.teamResourceMaps.append(map)
        }
        appState.saveConfig()
    }

    /// Remove a resource from the team template (requires Director or Manager role).
    func removeTeamResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
        guard appState.userProfile.role.canEditTeamTemplate else { return }
        guard let idx = appState.teamResourceMaps.firstIndex(where: { $0.id == productId }) else { return }
        appState.teamResourceMaps[idx].remove(id: id, type: type)
        appState.saveConfig()
    }

    func confirmResource(id: String, type: MappedResourceType, in productId: String, appState: AppState) {
        var map = appState.resourceMap(for: productId)
        if let idx = map.resources.firstIndex(where: { $0.id == id && $0.type == type }) {
            map.resources[idx].isConfirmed = true
        }
        appState.updateResourceMap(map)
    }

    func confirmAll(type: MappedResourceType, in productId: String, appState: AppState) {
        var map = appState.resourceMap(for: productId)
        map.confirmAll(type)
        appState.updateResourceMap(map)
    }

    func dismissPending(type: MappedResourceType, in productId: String, appState: AppState) {
        var map = appState.resourceMap(for: productId)
        map.dismissPending(type)
        appState.updateResourceMap(map)
    }

    func dismissAllPending(in productId: String, appState: AppState) {
        var map = appState.resourceMap(for: productId)
        map.resources.removeAll { $0.aiSuggested && !$0.isConfirmed }
        appState.updateResourceMap(map)
    }
}

// MARK: - Singleton In-Memory Discovery Cache

/// Loads from disk once at app launch, serves from RAM after that.
/// Discovery results are global (same Jira/GitHub/Jenkins for all products).
final class DiscoveryCache: @unchecked Sendable {
    static let shared = DiscoveryCache()

    private static let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boomi_sre_discovery_cache.json")
    }()

    /// In-memory cache — loaded from disk on first access.
    private(set) var data: [String: [MappedResource]]

    private init() {
        if let fileData = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder.iso8601.decode([String: [MappedResource]].self, from: fileData) {
            data = decoded
        } else {
            data = [:]
        }
    }

    /// Update the in-memory cache and persist to disk (off main thread).
    func update(_ newData: [String: [MappedResource]]) {
        data = newData
        DispatchQueue.global(qos: .utility).async {
            guard let encoded = try? JSONEncoder.iso8601.encode(newData) else { return }
            try? encoded.write(to: Self.fileURL)
        }
    }
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

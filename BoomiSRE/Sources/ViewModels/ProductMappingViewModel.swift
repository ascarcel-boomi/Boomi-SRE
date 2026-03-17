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

    /// Resources fetched from live APIs — transient, not persisted.
    /// Key: integration name (e.g. "Jira", "GitHub")
    @Published var discoveredByIntegration: [String: [MappedResource]] = [:]

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

    // MARK: Computed

    /// All discovered resources for the currently selected integration (flat list).
    func discovered(for integration: String) -> [MappedResource] {
        discoveredByIntegration[integration] ?? []
    }

    /// Available resources: discovered but not yet in the product's confirmed list.
    func available(for integration: String, in map: ProductResourceMap) -> [MappedResource] {
        let confirmedIds = Set(map.resources.map { $0.id + "|" + $0.type.rawValue })
        return discovered(for: integration).filter { r in
            !confirmedIds.contains(r.id + "|" + r.type.rawValue)
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
        discoveredByIntegration = [:]

        let integrations = ["Jira", "Confluence", "GitHub", "Bitbucket", "Jenkins", "Grafana", "JSM Ops"]

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
            return try await ResourceDiscoveryService.fetchJiraProjects(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken)
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
        case "JSM Ops":
            guard appState.isJiraConfigured else { return [] }
            return try await ResourceDiscoveryService.fetchJSMTeams(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, token: appState.jiraAPIToken)
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
        var map = appState.resourceMap(for: productId)
        var confirmed = resource
        confirmed.isConfirmed = true
        map.upsert(confirmed)
        appState.updateResourceMap(map)
    }

    func removeResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
        var map = appState.resourceMap(for: productId)
        map.remove(id: id, type: type)
        appState.updateResourceMap(map)
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

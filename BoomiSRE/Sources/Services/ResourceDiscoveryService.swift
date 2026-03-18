import Foundation

// MARK: - ResourceDiscoveryService
// Fetches live resources from each integration and uses Claude to suggest product mappings.

enum ResourceDiscoveryService {

    // MARK: - Per-integration fetchers

    /// Fetch Jira projects via API (paginated — fetches all).
    static func fetchJiraProjects(
        baseURL: String, email: String, token: String
    ) async throws -> [MappedResource] {
        struct Response: Decodable {
            struct Project: Decodable {
                let key: String
                let name: String
                let description: String?
                private enum CodingKeys: String, CodingKey { case key, name, description }
            }
            let values: [Project]
            let isLast: Bool?
            let nextPage: String?
        }

        var all: [MappedResource] = []
        var startAt = 0
        let pageSize = 100

        while true {
            guard let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/project/search?maxResults=\(pageSize)&startAt=\(startAt)&orderBy=name") else {
                throw DiscoveryError.invalidURL
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.addBasicAuth(email: email, token: token)
            let (data, _) = try await ZscalerTrustURLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(Response.self, from: data)

            all += result.values.map { p in
                MappedResource(
                    id: p.key,
                    name: "\(p.key) — \(p.name)",
                    type: .jiraProject,
                    isConfirmed: false, aiSuggested: false,
                    url: "\(baseURL.trimSlash)/jira/software/projects/\(p.key)/boards",
                    description: p.description,
                    addedAt: Date()
                )
            }

            if result.isLast == true || result.values.count < pageSize { break }
            startAt += pageSize
        }

        return all
    }

    /// Fetch Confluence spaces via API (paginated — fetches all).
    static func fetchConfluenceSpaces(
        baseURL: String, email: String, token: String
    ) async throws -> [MappedResource] {
        struct Response: Decodable {
            struct Space: Decodable {
                let key: String
                let name: String
                struct Links: Decodable { let webui: String? }
                let _links: Links
            }
            let results: [Space]
            let size: Int?
        }

        var all: [MappedResource] = []
        var start = 0
        let pageSize = 100

        while true {
            guard let url = URL(string: "\(baseURL.trimSlash)/wiki/rest/api/space?limit=\(pageSize)&start=\(start)&type=global") else {
                throw DiscoveryError.invalidURL
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.addBasicAuth(email: email, token: token)
            let (data, _) = try await ZscalerTrustURLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(Response.self, from: data)

            all += result.results.map { s in
                MappedResource(
                    id: s.key,
                    name: "\(s.key) — \(s.name)",
                    type: .confluenceSpace,
                    isConfirmed: false, aiSuggested: false,
                    url: s._links.webui.map { "\(baseURL.trimSlash)\($0)" },
                    description: nil,
                    addedAt: Date()
                )
            }

            if result.results.count < pageSize { break }
            start += pageSize
        }

        return all
    }

    /// Fetch GitHub repos for all configured orgs.
    static func fetchGitHubRepos(token: String, orgs: [String]) async throws -> [MappedResource] {
        let service = GitHubService()
        var result: [MappedResource] = []
        for org in orgs {
            let repos = try await service.listOrgRepos(org: org, token: token)
            for r in repos {
                result.append(MappedResource(
                    id: r.fullName,
                    name: r.name,
                    type: .githubRepo,
                    isConfirmed: false, aiSuggested: false,
                    url: r.htmlURL,
                    description: r.description.isEmpty ? nil : r.description,
                    addedAt: Date()
                ))
            }
        }
        return result
    }

    /// Fetch Bitbucket repos for the configured workspace.
    static func fetchBitbucketRepos(
        workspace: String, email: String, token: String
    ) async throws -> [MappedResource] {
        let service = BitbucketService()
        let repos = try await service.listWorkspaceRepos(workspace: workspace, email: email, apiToken: token)
        return repos.map { r in
            MappedResource(
                id: r.fullName,
                name: r.name,
                type: .bitbucketRepo,
                isConfirmed: false, aiSuggested: false,
                url: r.htmlURL,
                description: r.description.isEmpty ? nil : r.description,
                addedAt: Date()
            )
        }
    }

    /// Fetch Jenkins views and jobs from all configured servers.
    static func fetchJenkinsResources(servers: [JenkinsServer]) async throws -> [MappedResource] {
        let service = JenkinsService()
        var resources: [MappedResource] = []
        let multiServer = servers.count > 1

        for server in servers {
            let serverLabel = multiServer ? "[\(server.name)] " : ""

            // Views first
            let views = (try? await service.listViews(
                baseURL: server.url, username: server.username, token: server.token)) ?? []
            resources += views.map { v in
                MappedResource(
                    id: "\(server.id)/view/\(v.name)",
                    name: "\(serverLabel)\(v.name)",
                    type: .jenkinsView,
                    isConfirmed: false, aiSuggested: false,
                    url: v.url,
                    description: "\(v.jobNames.count) jobs" + (multiServer ? " · \(server.name)" : ""),
                    addedAt: Date()
                )
            }

            // Then jobs
            let jobs = (try? await service.listJobs(
                baseURL: server.url, username: server.username, token: server.token)) ?? []
            // Find which view each job belongs to
            let viewLookup: [String: String] = {
                var map: [String: String] = [:]
                for v in views {
                    for jobName in v.jobNames { map[jobName] = v.name }
                }
                return map
            }()

            resources += jobs.map { j in
                let viewName = viewLookup[j.name]
                let desc = [j.statusLabel, viewName.map { "View: \($0)" }, multiServer ? server.name : nil]
                    .compactMap { $0 }.joined(separator: " · ")
                return MappedResource(
                    id: "\(server.id)/job/\(j.name)",
                    name: "\(serverLabel)\(j.name)",
                    type: .jenkinsJob,
                    isConfirmed: false, aiSuggested: false,
                    url: j.url,
                    description: desc,
                    addedAt: Date()
                )
            }
        }

        return resources
    }

    /// Fetch Grafana folders and dashboards.
    static func fetchGrafanaResources(baseURL: String, token: String) async throws -> [MappedResource] {
        let service = GrafanaService()
        var resources: [MappedResource] = []

        // Folders first
        let folders = try await service.searchFolders(baseURL: baseURL, token: token)
        resources += folders.map { f in
            MappedResource(
                id: f.uid,
                name: f.title,
                type: .grafanaFolder,
                isConfirmed: false, aiSuggested: false,
                url: baseURL.trimSlash + "/dashboards/f/\(f.uid)",
                description: nil,
                addedAt: Date()
            )
        }

        // Then dashboards
        let dashboards = try await service.searchDashboards(baseURL: baseURL, token: token)
        resources += dashboards.map { d in
            let urlFull = baseURL.trimSlash + d.url
            return MappedResource(
                id: d.uid,
                name: d.title,
                type: .grafanaDashboard,
                isConfirmed: false, aiSuggested: false,
                url: urlFull,
                description: d.folderTitle.isEmpty ? nil : "Folder: \(d.folderTitle)",
                addedAt: Date()
            )
        }

        return resources
    }

    /// Fetch Jira saved filters via the filter search API.
    static func fetchJiraFilters(
        baseURL: String, email: String, token: String
    ) async throws -> [MappedResource] {
        struct Response: Decodable {
            struct Filter: Decodable {
                let id: String
                let name: String
                let jql: String?
                private enum CodingKeys: String, CodingKey { case id, name, jql }
            }
            let values: [Filter]
            let isLast: Bool?
        }

        var all: [MappedResource] = []
        var startAt = 0
        let pageSize = 100

        while true {
            guard let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/filter/search?expand=jql&maxResults=\(pageSize)&startAt=\(startAt)") else {
                throw DiscoveryError.invalidURL
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.addBasicAuth(email: email, token: token)
            let (data, _) = try await ZscalerTrustURLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(Response.self, from: data)

            all += result.values.map { f in
                MappedResource(
                    id: f.id,
                    name: f.name,
                    type: .jiraFilter,
                    isConfirmed: false, aiSuggested: false,
                    url: "\(baseURL.trimSlash)/issues/?filter=\(f.id)",
                    description: f.jql,
                    addedAt: Date()
                )
            }

            if result.isLast == true || result.values.count < pageSize { break }
            startAt += pageSize
        }

        return all
    }

    /// Fetch Jira boards via the Agile API.
    static func fetchJiraBoards(
        baseURL: String, email: String, token: String
    ) async throws -> [MappedResource] {
        struct Response: Decodable {
            struct Board: Decodable {
                let id: Int
                let name: String
                let type: String
                private enum CodingKeys: String, CodingKey { case id, name, type }
            }
            let values: [Board]
            let isLast: Bool?
        }

        var all: [MappedResource] = []
        var startAt = 0
        let pageSize = 100

        while true {
            guard let url = URL(string: "\(baseURL.trimSlash)/rest/agile/1.0/board?maxResults=\(pageSize)&startAt=\(startAt)") else {
                throw DiscoveryError.invalidURL
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.addBasicAuth(email: email, token: token)
            let (data, _) = try await ZscalerTrustURLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(Response.self, from: data)

            all += result.values.map { b in
                MappedResource(
                    id: String(b.id),
                    name: b.name,
                    type: .jiraBoard,
                    isConfirmed: false, aiSuggested: false,
                    url: "\(baseURL.trimSlash)/jira/software/projects/board/\(b.id)",
                    description: b.type,
                    addedAt: Date()
                )
            }

            if result.isLast == true || result.values.count < pageSize { break }
            startAt += pageSize
        }

        return all
    }

    /// Fetch incident product elements from the Boomi Incident Management project.
    /// If `fieldId` is empty, attempts to discover the field ID by searching for "product element" fields.
    static func fetchIncidentProductElements(
        baseURL: String, email: String, token: String, fieldId: String
    ) async throws -> [MappedResource] {
        var effectiveFieldId = fieldId

        // Auto-discover field ID if not provided
        if effectiveFieldId.isEmpty {
            let jiraService = JiraService()
            let fields = try await jiraService.getCustomFields(
                baseURL: baseURL, email: email, apiToken: token)
            if let match = fields.first(where: { $0.name.localizedCaseInsensitiveContains("product element") }) {
                effectiveFieldId = match.id
            } else {
                return [] // Cannot discover without the field ID
            }
        }

        let jiraService = JiraService()
        let values = try await jiraService.discoverProductElements(
            baseURL: baseURL, email: email, apiToken: token,
            productElementFieldId: effectiveFieldId)

        return values.map { v in
            MappedResource(
                id: v,
                name: v,
                type: .incidentProductElement,
                isConfirmed: false, aiSuggested: false,
                url: nil,
                description: "Product element from Boomi Incident Management",
                addedAt: Date()
            )
        }
    }

    /// Fetch JSM Teams.
    static func fetchJSMTeams(
        baseURL: String, email: String, token: String
    ) async throws -> [MappedResource] {
        let service = JSMOpsService()
        let teams = try await service.listTeams(baseURL: baseURL, email: email, apiToken: token)
        return teams.map { t in
            MappedResource(
                id: t.id,
                name: t.name,
                type: .jsmTeam,
                isConfirmed: false, aiSuggested: false,
                url: nil,
                description: t.description,
                addedAt: Date()
            )
        }
    }

    // MARK: - AI-Powered Suggestion

    /// Ask Claude to suggest which of the discovered resources belong to `product`.
    /// Returns the same resources with `aiSuggested = true` and `confidence` filled in.
    static func suggestMappings(
        discovered: [MappedResource],
        for product: ProductContext,
        modelOverride: String? = nil  // swiftlint:disable:this unused_parameter
    ) async throws -> [MappedResource] {
        guard !discovered.isEmpty else { return [] }

        let resourceList = discovered.prefix(500).map { r in
            "  - [\(r.type.rawValue)] \(r.id) — \(r.name)\(r.description.map { ": \($0)" } ?? "")"
        }.joined(separator: "\n")

        let prompt = """
        You are an SRE infrastructure assistant. Your job is to suggest which resources belong to a specific Boomi product.

        Product: \(product.name) (\(product.shortName))
        Description: \(product.productDescription.isEmpty ? "No description provided." : product.productDescription)

        Available resources to evaluate:
        \(resourceList)

        Return ONLY a JSON array of objects for resources that likely belong to this product. \
        Skip resources that clearly do not belong. Format:
        [
          {"id": "RESOURCE_ID", "type": "RESOURCE_TYPE", "confidence": 0.95, "reason": "brief reason"}
        ]

        Where confidence is 0.0–1.0. Only include resources with confidence >= 0.4.
        Respond with the JSON array only — no markdown, no explanation outside the JSON.
        """

        let service = ClaudeService()
        let response = try await service.chat(
            messages: [(role: "user", content: prompt)],
            systemPrompt: "You are a resource mapping assistant. Respond only with valid JSON arrays.",
            maxTokens: 4096,
            modelOverride: modelOverride
        )

        // Parse JSON from response
        let jsonText = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8) else { return [] }

        struct Suggestion: Decodable {
            let id: String
            let type: String
            let confidence: Double
            let reason: String
        }
        let suggestions = (try? JSONDecoder().decode([Suggestion].self, from: data)) ?? []

        // Map suggestions back to MappedResource (from discovered pool + AI metadata)
        // Build multiple lookup indices so we can match even if the AI returns a slightly different key format
        let byIdAndType = Dictionary(discovered.map { ($0.id + "|" + $0.type.rawValue, $0) }, uniquingKeysWith: { a, _ in a })
        let byId = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byName = Dictionary(discovered.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        return suggestions.compactMap { s in
            guard let type = MappedResourceType(rawValue: s.type) else { return nil }
            let key = s.id + "|" + s.type
            // Try exact match, then by ID alone, then by name (AI sometimes returns name as ID)
            var resource = byIdAndType[key] ?? byId[s.id] ?? byName[s.id] ?? MappedResource(
                id: s.id, name: s.id, type: type,
                isConfirmed: false, aiSuggested: true,
                url: nil, description: s.reason, addedAt: Date()
            )
            resource.aiSuggested = true
            resource.confidence = s.confidence
            resource.isConfirmed = false
            if resource.description == nil { resource.description = s.reason }
            return resource
        }
    }

    // MARK: - AI Chat Operations

    struct AIResourceOperation: Decodable {
        let action: String   // "add" | "remove"
        let id: String
        let type: String
        let reason: String?
    }

    /// Ask Claude to interpret a natural-language mapping request and return operations.
    /// Returns (assistant message text, list of operations to preview).
    static func processChatCommand(
        userMessage: String,
        product: ProductContext,
        currentMap: ProductResourceMap,
        available: [MappedResource],
        modelOverride: String? = nil
    ) async throws -> (text: String, operations: [AIResourceOperation]) {
        let confirmedSummary = MappedResourceType.allCases
            .compactMap { type -> String? in
                let ids = currentMap.confirmedIds(type)
                guard !ids.isEmpty else { return nil }
                return "\(type.displayName): \(ids.joined(separator: ", "))"
            }.joined(separator: "\n")

        let availableSummary = available.prefix(200).map { r in
            "[\(r.type.rawValue)] \(r.id) — \(r.name)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a resource mapping assistant for Boomi SRE. \
        The user is managing which infrastructure resources belong to the \(product.name) product.

        Currently mapped resources:
        \(confirmedSummary.isEmpty ? "  (none yet)" : confirmedSummary)

        Available resources from discovery:
        \(availableSummary.isEmpty ? "  (run discovery first to see available resources)" : availableSummary)

        When the user asks to add or remove resources, respond with:
        1. A brief natural-language explanation of what you're doing (1–2 sentences).
        2. A JSON block marked with ```json ... ``` containing an array of operations:
           [{"action": "add"|"remove", "id": "RESOURCE_ID", "type": "RESOURCE_TYPE_RAWVALUE", "reason": "..."}]

        Only reference resources from the available list (for adds) or the currently mapped list (for removes).
        If you cannot find matching resources, say so clearly and do not return a JSON block.
        """

        let service = ClaudeService()
        let response = try await service.chat(
            messages: [(role: "user", content: userMessage)],
            systemPrompt: systemPrompt,
            maxTokens: 2048,
            modelOverride: modelOverride
        )

        // Extract JSON block if present
        var ops: [AIResourceOperation] = []
        if let jsonRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: jsonRange.upperBound..<response.endIndex) {
            let jsonStr = String(response[jsonRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonStr.data(using: .utf8) {
                ops = (try? JSONDecoder().decode([AIResourceOperation].self, from: data)) ?? []
            }
        }

        // Strip the JSON block from the display text
        let displayText = response
            .replacingOccurrences(of: #"```json[\s\S]*?```"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (displayText, ops)
    }
}

// MARK: - DiscoveryError

enum DiscoveryError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid URL"
        case .httpError(let code):  return "HTTP \(code)"
        case .notConfigured(let s): return "\(s) not configured"
        }
    }
}

private extension DiscoveryError {
    static var httpError: DiscoveryError { .httpError(0) }
}

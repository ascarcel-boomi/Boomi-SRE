import Foundation

// MARK: - Resource Type

/// Every discoverable resource type across all integrations.
enum MappedResourceType: String, Codable, CaseIterable {
    case jiraProject      = "jira_project"
    case jiraFilter       = "jira_filter"
    case jiraBoard        = "jira_board"
    case githubRepo       = "github_repo"
    case bitbucketRepo    = "bitbucket_repo"
    case jenkinsView      = "jenkins_view"
    case jenkinsJob       = "jenkins_job"
    case grafanaFolder    = "grafana_folder"
    case grafanaDashboard = "grafana_dashboard"
    case confluenceSpace  = "confluence_space"
    case awsAccount       = "aws_account"
    case jsmTeam          = "jsm_team"

    var displayName: String {
        switch self {
        case .jiraProject:      return "Jira Projects"
        case .jiraFilter:       return "Jira Filters"
        case .jiraBoard:        return "Jira Boards"
        case .githubRepo:       return "GitHub Repos"
        case .bitbucketRepo:    return "Bitbucket Repos"
        case .jenkinsView:      return "Jenkins Views"
        case .jenkinsJob:       return "Jenkins Jobs"
        case .grafanaDashboard: return "Grafana Dashboards"
        case .grafanaFolder:    return "Grafana Folders"
        case .confluenceSpace:  return "Confluence Spaces"
        case .awsAccount:       return "AWS Accounts"
        case .jsmTeam:          return "JSM Teams"
        }
    }

    var integrationName: String {
        switch self {
        case .jiraProject, .jiraFilter, .jiraBoard: return "Jira"
        case .githubRepo:                           return "GitHub"
        case .bitbucketRepo:                        return "Bitbucket"
        case .jenkinsView, .jenkinsJob:             return "Jenkins"
        case .grafanaDashboard, .grafanaFolder:     return "Grafana"
        case .confluenceSpace:                      return "Confluence"
        case .awsAccount:                           return "AWS"
        case .jsmTeam:                              return "JSM Ops"
        }
    }

    var icon: String {
        switch self {
        case .jiraProject, .jiraFilter, .jiraBoard: return "checklist"
        case .githubRepo:                           return "chevron.left.forwardslash.chevron.right"
        case .bitbucketRepo:                        return "point.3.connected.trianglepath.dotted"
        case .jenkinsView, .jenkinsJob:             return "gearshape.2"
        case .grafanaDashboard, .grafanaFolder:     return "chart.xyaxis.line"
        case .confluenceSpace:                      return "book.closed"
        case .awsAccount:                           return "cloud"
        case .jsmTeam:                              return "person.3"
        }
    }

    /// All types belonging to a given integration, in display order.
    static func types(for integration: String) -> [MappedResourceType] {
        allCases.filter { $0.integrationName == integration }
    }

    /// Ordered list of integration names (for tab display).
    static var integrationNames: [String] {
        var seen = Set<String>()
        return allCases.compactMap { t -> String? in
            let name = t.integrationName
            return seen.insert(name).inserted ? name : nil
        }
    }
}

// MARK: - Mapped Resource

/// A single resource (Jira project, GitHub repo, AWS account, etc.) mapped to a product.
struct MappedResource: Identifiable, Codable, Hashable {
    /// Stable unique identifier — project key, repo slug, account ID, dashboard UID, etc.
    var id: String
    /// Human-readable display name (repo full name, dashboard title, account alias, etc.)
    var name: String
    var type: MappedResourceType
    /// User has explicitly confirmed this mapping (vs. unreviewed AI suggestion).
    var isConfirmed: Bool
    /// Was suggested by AI discovery (may or may not be confirmed yet).
    var aiSuggested: Bool
    /// AI confidence score 0.0–1.0 (nil if manually added).
    var confidence: Double?
    /// Web or deeplink URL for this resource.
    var url: String?
    /// Short description from the source API.
    var description: String?
    var addedAt: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }

    static func == (lhs: MappedResource, rhs: MappedResource) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }
}

// MARK: - Product Resource Map

/// The full set of resources mapped to one product.
/// One `ProductResourceMap` exists per `ProductContext` (matched by `productId`).
struct ProductResourceMap: Identifiable, Codable {
    /// Matches `ProductContext.id` (e.g. "cam-sre", "mft-sre").
    var id: String
    var resources: [MappedResource]
    var lastDiscoveredAt: Date?

    // MARK: Queries

    /// Confirmed resources of a given type — used by all service-layer filters.
    func confirmed(_ type: MappedResourceType) -> [MappedResource] {
        resources.filter { $0.type == type && $0.isConfirmed }
    }

    /// IDs of confirmed resources — convenience for building JQL / API queries.
    func confirmedIds(_ type: MappedResourceType) -> [String] {
        confirmed(type).map(\.id)
    }

    /// AI-suggested resources not yet reviewed by the user.
    func pending(_ type: MappedResourceType) -> [MappedResource] {
        resources.filter { $0.type == type && $0.aiSuggested && !$0.isConfirmed }
    }

    /// All pending suggestions across all types.
    var allPending: [MappedResource] {
        resources.filter { $0.aiSuggested && !$0.isConfirmed }
    }

    var pendingCount: Int { allPending.count }

    /// Integration names that have at least one confirmed resource.
    var activeIntegrations: Set<String> {
        Set(resources.filter(\.isConfirmed).map(\.type.integrationName))
    }

    // MARK: Mutations

    mutating func upsert(_ resource: MappedResource) {
        if let idx = resources.firstIndex(where: { $0.id == resource.id && $0.type == resource.type }) {
            resources[idx] = resource
        } else {
            resources.append(resource)
        }
    }

    mutating func remove(id: String, type: MappedResourceType) {
        resources.removeAll { $0.id == id && $0.type == type }
    }

    /// Approve all pending AI suggestions for a given type.
    mutating func confirmAll(_ type: MappedResourceType) {
        for i in resources.indices where resources[i].type == type && !resources[i].isConfirmed {
            resources[i].isConfirmed = true
        }
    }

    /// Dismiss all pending AI suggestions for a given type without confirming.
    mutating func dismissPending(_ type: MappedResourceType) {
        resources.removeAll { $0.type == type && $0.aiSuggested && !$0.isConfirmed }
    }

    /// Approve all pending suggestions across all types.
    mutating func confirmAllPending() {
        for i in resources.indices where !resources[i].isConfirmed {
            resources[i].isConfirmed = true
        }
    }
}

// MARK: - Factories

extension ProductResourceMap {

    static func empty(for productId: String) -> ProductResourceMap {
        ProductResourceMap(id: productId, resources: [], lastDiscoveredAt: nil)
    }

    /// Migrate an existing `ProductContext` (which stored patterns) into a resource map.
    /// Jira projects and Confluence spaces become confirmed resources.
    /// GitHub / Jenkins patterns become unconfirmed hints (need AI/manual review).
    static func migrated(from context: ProductContext) -> ProductResourceMap {
        var resources: [MappedResource] = []
        let now = Date()

        for key in context.jiraProjectKeys {
            resources.append(MappedResource(
                id: key, name: key, type: .jiraProject,
                isConfirmed: true, aiSuggested: false,
                url: nil, description: nil, addedAt: now))
        }
        for key in context.confluenceSpaceKeys {
            resources.append(MappedResource(
                id: key, name: key, type: .confluenceSpace,
                isConfirmed: true, aiSuggested: false,
                url: nil, description: nil, addedAt: now))
        }
        for teamId in context.jsmTeamIds {
            resources.append(MappedResource(
                id: teamId, name: teamId, type: .jsmTeam,
                isConfirmed: true, aiSuggested: false,
                url: nil, description: nil, addedAt: now))
        }
        // GitHub / Jenkins patterns are stored as unconfirmed hints
        // so discovery can flesh them out into real repos/jobs.
        for pattern in context.githubRepoPatterns {
            resources.append(MappedResource(
                id: pattern, name: pattern, type: .githubRepo,
                isConfirmed: false, aiSuggested: false,
                url: nil, description: "Pattern from previous config", addedAt: now))
        }
        for pattern in context.jenkinsJobPatterns {
            resources.append(MappedResource(
                id: pattern, name: pattern, type: .jenkinsJob,
                isConfirmed: false, aiSuggested: false,
                url: nil, description: "Pattern from previous config", addedAt: now))
        }

        return ProductResourceMap(id: context.id, resources: resources, lastDiscoveredAt: nil)
    }
}

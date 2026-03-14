import Foundation

// MARK: - Search API response

struct JiraSearchResult: Codable {
    let issues: [JiraIssue]
    let total: Int?         // Present in /search but absent in /search/jql
    let isLast: Bool?       // Present in /search/jql
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case issues, total, isLast, nextPageToken
    }

    var issueCount: Int { total ?? issues.count }
}

struct JiraIssue: Codable, Identifiable {
    let id: String
    let key: String
    let fields: JiraFields

    enum CodingKeys: String, CodingKey { case id, key, fields }
}

struct JiraFields: Codable {
    let summary: String?
    let status: JiraStatus?
    let priority: JiraNamedField?
    let issuetype: JiraNamedField?
    let duedate: String?
    let labels: [String]?
    let created: String?
    let updated: String?
    let assignee: JiraUser?

    enum CodingKeys: String, CodingKey {
        case summary, status, priority, issuetype, duedate, labels, created, updated, assignee
    }
}

struct JiraNamedField: Codable {
    let name: String

    enum CodingKeys: String, CodingKey { case name }
}

struct JiraStatus: Codable {
    let name: String
    let statusCategory: JiraStatusCategory?

    enum CodingKeys: String, CodingKey { case name, statusCategory }
}

struct JiraStatusCategory: Codable {
    let name: String
    let key: String?

    enum CodingKeys: String, CodingKey { case name, key }
}

struct JiraUser: Codable {
    let displayName: String
    let emailAddress: String?

    // Ignore extra fields from the API (accountId, avatarUrls, active, etc.)
    enum CodingKeys: String, CodingKey {
        case displayName
        case emailAddress
    }
}

// MARK: - Sprint (extracted from custom field)

struct JiraSprint: Codable, Identifiable {
    let id: Int
    let name: String
    let state: String  // "active", "closed", "future"
    let startDate: String?
    let endDate: String?
}

// MARK: - Saved filters

struct JiraFilter: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let jql: String
    let viewUrl: String?
    let favourite: Bool?

    // Ignore owner and other extra fields that have complex nested types
    enum CodingKeys: String, CodingKey {
        case id, name, jql, viewUrl, favourite
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JiraFilter, rhs: JiraFilter) -> Bool { lhs.id == rhs.id }
}

// MARK: - TODO Dashboard

enum TodoCategory: String, CaseIterable, Identifiable {
    case overdue = "Overdue"
    case inProgress = "In Progress"
    case sprintToDo = "Sprint To-Do"
    case unplanned = "Unplanned / Kanban"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .overdue: return 0
        case .inProgress: return 1
        case .sprintToDo: return 2
        case .unplanned: return 3
        }
    }
}

struct TodoItem: Identifiable {
    let id: String           // issue key
    let key: String
    let summary: String
    let status: String
    let statusCategoryName: String
    let priority: String
    let priorityOrder: Int   // 1=Highest...5=Lowest
    let dueDate: Date?
    let issueType: String
    let issueTypeIconURL: URL?
    let labels: [String]
    let sprint: JiraSprint?
    let category: TodoCategory
    let url: URL
    let updated: Date?
    let assignee: String     // "Unassigned" if nil
}

// MARK: - Ticket Actions

struct JiraTransition: Identifiable {
    let id: String
    let name: String
    let toStatus: String
    let toCategory: String
}

struct JiraAssignableUser: Identifiable {
    let accountId: String
    let displayName: String
    var id: String { accountId }
}

struct JiraComment: Identifiable, Sendable {
    let id: String
    let authorName: String
    let authorAvatarURL: String?
    let created: String
    let bodyText: String  // plain text extracted from ADF body
}

// MARK: - Dev Info (PRs, Commits)

struct JiraDevInfo {
    let prCount: Int
    let branchCount: Int
    let pullRequests: [JiraDevPR]
    let commits: [JiraDevCommit]
}

struct JiraDevPR: Identifiable {
    let name: String
    let url: String
    let status: String    // OPEN, MERGED, DECLINED
    let author: String
    let sourceBranch: String
    let destBranch: String
    var id: String { url }
}

struct JiraDevCommit: Identifiable {
    let message: String
    let url: String
    let author: String
    let date: String
    let hash: String
    var id: String { url }
}

// MARK: - Field metadata

struct JiraFieldMeta: Codable, Identifiable {
    let id: String
    let name: String
    let custom: Bool

    enum CodingKeys: String, CodingKey { case id, name, custom }
}

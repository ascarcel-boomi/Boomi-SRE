import Foundation

// MARK: - Search API response

struct JiraSearchResult: Codable {
    let total: Int
    let issues: [JiraIssue]
}

struct JiraIssue: Codable, Identifiable {
    let id: String
    let key: String
    let fields: JiraFields
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
}

struct JiraNamedField: Codable {
    let name: String
}

struct JiraStatus: Codable {
    let name: String
    let statusCategory: JiraStatusCategory?
}

struct JiraStatusCategory: Codable {
    let name: String
    let key: String?  // "new", "indeterminate", "done"
}

struct JiraUser: Codable {
    let displayName: String
    let emailAddress: String?
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
    let owner: JiraUser?
    let viewUrl: String?
    let favourite: Bool?

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
    let labels: [String]
    let sprint: JiraSprint?
    let category: TodoCategory
    let url: URL
    let updated: Date?
}

// MARK: - Field metadata

struct JiraFieldMeta: Codable, Identifiable {
    let id: String
    let name: String
    let custom: Bool
}

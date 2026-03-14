import Foundation
import SwiftUI

/// ViewModel for the personal TODO dashboard.
@MainActor
final class TodoDashboardViewModel: ObservableObject {
    @Published var items: [TodoItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefreshed: Date?

    private let jiraService = JiraService()
    private var sprintFieldId: String?

    /// Refresh the TODO list from Jira.
    func refresh(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira is not configured. Go to Settings to add your credentials."
            return
        }

        isLoading = true
        error = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)

        do {
            // Discover sprint field ID (once)
            if sprintFieldId == nil {
                sprintFieldId = try await jiraService.discoverSprintFieldId(
                    baseURL: baseURL, email: email, apiToken: token
                )
            }

            let sprintField = sprintFieldId ?? "customfield_10020"
            let fields = ["summary", "status", "priority", "issuetype",
                          "duedate", "labels", "created", "updated", "assignee", sprintField]

            let jql = "assignee = currentUser() AND statusCategory NOT IN (Done) ORDER BY priority ASC, updated DESC"

            let (result, rawIssues) = try await jiraService.searchIssuesRaw(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql, fields: fields, maxResults: 200
            )

            // Build TodoItems by combining typed + raw data
            var todos: [TodoItem] = []
            for (i, issue) in result.issues.enumerated() {
                let rawFields = (rawIssues.indices.contains(i)
                    ? rawIssues[i]["fields"] as? [String: Any]
                    : nil) ?? [:]

                let sprint = extractSprint(from: rawFields, fieldId: sprintField)
                let iconStr = (rawFields["issuetype"] as? [String: Any])?["iconUrl"] as? String
                let item = buildTodoItem(issue: issue, sprint: sprint, baseURL: baseURL, iconURL: iconStr)
                todos.append(item)
            }

            // Sort: overdue first, then in-progress, sprint to-do, unplanned
            // Within each: by priority (1=highest first)
            todos.sort {
                if $0.category.sortOrder != $1.category.sortOrder {
                    return $0.category.sortOrder < $1.category.sortOrder
                }
                return $0.priorityOrder < $1.priorityOrder
            }

            items = todos
            lastRefreshed = Date()
            isLoading = false

        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Items grouped by category.
    var groupedItems: [(TodoCategory, [TodoItem])] {
        TodoCategory.allCases.compactMap { cat in
            let catItems = items.filter { $0.category == cat }
            return catItems.isEmpty ? nil : (cat, catItems)
        }
    }

    /// Summary counts per category.
    var categoryCounts: [TodoCategory: Int] {
        Dictionary(grouping: items, by: \.category).mapValues(\.count)
    }

    /// Chart-ready data: items by category grouped by priority.
    var chartSections: [ResultSection] {
        // Priority distribution pie
        let byPriority = Dictionary(grouping: items, by: \.priority).map { (key, val) in
            ResultRow(label: key, value: Double(val.count))
        }.sorted { $0.value > $1.value }

        let prioritySection = ResultSection(
            title: "By Priority", rows: byPriority, chartHint: .pie
        )

        // Category bar chart with priority stacking
        var catRows: [ResultRow] = []
        for cat in TodoCategory.allCases {
            let catItems = items.filter { $0.category == cat }
            let byPri = Dictionary(grouping: catItems, by: \.priority)
            for (pri, priItems) in byPri {
                catRows.append(ResultRow(
                    label: cat.rawValue, value: Double(priItems.count), group: pri
                ))
            }
        }

        let categorySection = ResultSection(
            title: "By Category", rows: catRows, chartHint: .stackedBar
        )

        return [categorySection, prioritySection]
    }

    // MARK: - Private helpers

    private func extractSprint(from rawFields: [String: Any], fieldId: String) -> JiraSprint? {
        guard let sprintArray = rawFields[fieldId] as? [[String: Any]],
              let last = sprintArray.last else { return nil }

        // Find the active sprint, or fallback to the last one
        let active = sprintArray.first { ($0["state"] as? String) == "active" }
        let sprint = active ?? last

        guard let id = sprint["id"] as? Int,
              let name = sprint["name"] as? String,
              let state = sprint["state"] as? String else { return nil }

        return JiraSprint(
            id: id, name: name, state: state,
            startDate: sprint["startDate"] as? String,
            endDate: sprint["endDate"] as? String
        )
    }

    private func buildTodoItem(issue: JiraIssue, sprint: JiraSprint?, baseURL: String, iconURL: String? = nil) -> TodoItem {
        let f = issue.fields
        let statusCatName = f.status?.statusCategory?.name ?? "Unknown"
        let priorityName = f.priority?.name ?? "Medium"
        let priorityOrder = Self.priorityOrder(for: priorityName)
        let dueDate = Self.parseDate(f.duedate)
        let updated = Self.parseDate(f.updated)
        let now = Date()

        // Determine category
        let category: TodoCategory
        if let due = dueDate, due < now {
            category = .overdue
        } else if statusCatName == "In Progress" {
            category = .inProgress
        } else if let s = sprint, s.state == "active", statusCatName == "To Do" {
            category = .sprintToDo
        } else {
            category = .unplanned
        }

        let issueURL = URL(string: "\(baseURL.hasSuffix("/") ? baseURL : baseURL + "/")browse/\(issue.key)")
            ?? URL(string: "https://boomii.atlassian.net/browse/\(issue.key)")!

        return TodoItem(
            id: issue.key, key: issue.key,
            summary: f.summary ?? "",
            status: f.status?.name ?? "Unknown",
            statusCategoryName: statusCatName,
            priority: priorityName,
            priorityOrder: priorityOrder,
            dueDate: dueDate,
            issueType: f.issuetype?.name ?? "Task",
            issueTypeIconURL: iconURL.flatMap { URL(string: $0) },
            labels: f.labels ?? [],
            sprint: sprint,
            category: category,
            url: issueURL,
            updated: updated,
            assignee: f.assignee?.displayName ?? "Unassigned"
        )
    }

    private static func priorityOrder(for name: String) -> Int {
        switch name.lowercased() {
        case "highest": return 1
        case "high": return 2
        case "medium": return 3
        case "low": return 4
        case "lowest": return 5
        default: return 3
        }
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        // Try ISO date first (2026-03-11), then full ISO datetime
        let formatters: [DateFormatter] = {
            let df1 = DateFormatter()
            df1.dateFormat = "yyyy-MM-dd"
            let df2 = DateFormatter()
            df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            return [df1, df2]
        }()
        for fmt in formatters {
            if let d = fmt.date(from: s) { return d }
        }
        // Try ISO8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}

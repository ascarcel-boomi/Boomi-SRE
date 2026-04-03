import Foundation
import SwiftUI

// MARK: - Filter enums

enum TicketStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case toDo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"
    var id: String { rawValue }
}

enum TicketPriorityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case highest = "Highest"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case lowest = "Lowest"
    var id: String { rawValue }
}

// MARK: - ViewModel

/// ViewModel for the personal TODO dashboard.
@MainActor
final class TodoDashboardViewModel: ObservableObject {
    @Published var items: [TodoItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefreshed: Date?
    @Published var cachedChartSections: [ResultSection] = []

    // MARK: Filter state
    @Published var statusFilter: TicketStatusFilter = .all
    @Published var priorityFilter: TicketPriorityFilter = .all
    @Published var assigneeFilter: String = "All"

    // MARK: Inline detail state
    @Published var selectedItem: TodoItem? = nil
    @Published var detailIssue: (issue: JiraIssue, raw: [String: Any])? = nil
    @Published var detailComments: [JiraComment] = []
    @Published var detailTransitions: [JiraTransition] = []
    @Published var isLoadingDetail = false
    @Published var detailError: String? = nil

    // MARK: Comment input
    @Published var commentInput: String = ""
    @Published var isPostingComment = false

    // MARK: Transition state
    @Published var isTransitioning = false
    @Published var transitionFeedback: String? = nil

    private let jiraService = JiraService()
    private var sprintFieldId: String?

    // MARK: - Derived: Filtered items

    var filteredItems: [TodoItem] {
        items.filter { item in
            let statusMatch: Bool = {
                switch statusFilter {
                case .all: return true
                case .toDo: return item.statusCategoryName == "To Do"
                case .inProgress: return item.statusCategoryName == "In Progress"
                case .done: return item.statusCategoryName == "Done"
                }
            }()
            let priorityMatch = priorityFilter == .all || item.priority.lowercased() == priorityFilter.rawValue.lowercased()
            let assigneeMatch = assigneeFilter == "All" || item.assignee == assigneeFilter
            return statusMatch && priorityMatch && assigneeMatch
        }
    }

    /// All unique assignees in the current item set (for dropdown).
    var allAssignees: [String] {
        let names = Set(items.map { $0.assignee }).sorted()
        return ["All"] + names
    }

    // MARK: - SP Summary

    struct SPSummary {
        let completedPoints: Double    // Done items in sprint
        let committedPoints: Double    // All sprint items (active sprint)
        let plannedPoints: Double      // Items with sprint
        let unplannedPoints: Double    // Items without sprint
    }

    private var rawStoryPoints: [String: Double] = [:]  // key -> SP

    var spSummary: SPSummary {
        let sprintItems = items.filter { $0.sprint != nil && $0.sprint?.state == "active" }
        let unplannedItems = items.filter { $0.sprint == nil || $0.sprint?.state != "active" }

        let completedPoints = sprintItems
            .filter { $0.statusCategoryName == "Done" }
            .reduce(0.0) { $0 + (rawStoryPoints[$1.key] ?? 0) }
        let committedPoints = sprintItems
            .reduce(0.0) { $0 + (rawStoryPoints[$1.key] ?? 0) }
        let plannedPoints = committedPoints
        let unplannedPoints = unplannedItems
            .reduce(0.0) { $0 + (rawStoryPoints[$1.key] ?? 0) }

        return SPSummary(
            completedPoints: completedPoints,
            committedPoints: committedPoints,
            plannedPoints: plannedPoints,
            unplannedPoints: unplannedPoints
        )
    }

    // MARK: - Refresh

    /// Refresh the TODO list from Jira.
    func refresh(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira is not configured. Go to Settings to add your credentials."
            return
        }

        isLoading = true
        error = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)
        let spFieldId = appState.storyPointsFieldId

        do {
            // Discover sprint field ID (once)
            if sprintFieldId == nil {
                sprintFieldId = try await jiraService.discoverSprintFieldId(
                    baseURL: baseURL, email: email, apiToken: token
                )
            }

            let sprintField = sprintFieldId ?? "customfield_10020"
            let fields = ["summary", "status", "priority", "issuetype",
                          "duedate", "labels", "created", "updated", "assignee",
                          sprintField, spFieldId]

            let projectKeys = appState.activeJiraProjectKeys
            let projectFilter = projectKeys.isEmpty
                ? ""
                : " AND project IN (\(projectKeys.joined(separator: ", ")))"
            let jql = "assignee = currentUser() AND statusCategory NOT IN (Done)\(projectFilter) ORDER BY priority ASC, updated DESC"

            let (result, rawIssues) = try await jiraService.searchIssuesRaw(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql, fields: fields, maxResults: 200
            )

            // Build TodoItems by combining typed + raw data
            var todos: [TodoItem] = []
            var pointsMap: [String: Double] = [:]
            for (i, issue) in result.issues.enumerated() {
                let rawFields = (rawIssues.indices.contains(i)
                    ? rawIssues[i]["fields"] as? [String: Any]
                    : nil) ?? [:]

                let sprint = extractSprint(from: rawFields, fieldId: sprintField)
                let iconStr = (rawFields["issuetype"] as? [String: Any])?["iconUrl"] as? String
                let item = buildTodoItem(issue: issue, sprint: sprint, baseURL: baseURL, iconURL: iconStr)
                todos.append(item)

                // Collect story points (customfield_10008 may come back as Double or Int)
                if let sp = rawFields[spFieldId] as? Double {
                    pointsMap[issue.key] = sp
                } else if let sp = rawFields[spFieldId] as? Int {
                    pointsMap[issue.key] = Double(sp)
                }
            }

            // Sort: overdue first, then in-progress, sprint to-do, unplanned
            todos.sort {
                if $0.category.sortOrder != $1.category.sortOrder {
                    return $0.category.sortOrder < $1.category.sortOrder
                }
                return $0.priorityOrder < $1.priorityOrder
            }

            items = todos
            rawStoryPoints = pointsMap
            cachedChartSections = chartSections
            lastRefreshed = Date()
            isLoading = false

        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Inline Detail

    func selectItem(_ item: TodoItem, appState: AppState) {
        selectedItem = item
        detailIssue = nil
        detailComments = []
        detailTransitions = []
        detailError = nil
        transitionFeedback = nil
        Task { await loadDetail(for: item, appState: appState) }
    }

    func clearSelection() {
        selectedItem = nil
        detailIssue = nil
        detailComments = []
        detailTransitions = []
        detailError = nil
    }

    func loadDetail(for item: TodoItem, appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isLoadingDetail = true
        detailError = nil
        do {
            async let issueTask = jiraService.getIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: item.key
            )
            async let commentsTask = jiraService.getIssueComments(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, issueKey: item.key
            )
            async let transitionsTask = jiraService.getTransitions(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: item.key
            )
            let (issueResult, comments, transitions) = try await (issueTask, commentsTask, transitionsTask)
            detailIssue = issueResult
            detailComments = comments
            detailTransitions = transitions
        } catch {
            detailError = error.localizedDescription
        }
        isLoadingDetail = false
    }

    // MARK: - Comment posting

    func postComment(appState: AppState) async {
        let text = commentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let item = selectedItem, appState.isJiraConfigured else { return }
        isPostingComment = true
        do {
            try await jiraService.addComment(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: item.key, body: text
            )
            commentInput = ""
            // Refresh comments
            let updated = try await jiraService.getIssueComments(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, issueKey: item.key
            )
            detailComments = updated
        } catch {
            detailError = "Failed to post comment: \(error.localizedDescription)"
        }
        isPostingComment = false
    }

    // MARK: - Status transition

    func applyTransition(_ transition: JiraTransition, appState: AppState) async {
        guard let item = selectedItem, appState.isJiraConfigured else { return }
        isTransitioning = true
        transitionFeedback = nil
        do {
            try await jiraService.transitionIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: item.key, transitionId: transition.id
            )
            transitionFeedback = "Moved to \(transition.toStatus)"
            // Refresh transitions + reload list item
            async let newTransitions = jiraService.getTransitions(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: item.key
            )
            async let newIssue = jiraService.getIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: item.key
            )
            let (t, i) = try await (newTransitions, newIssue)
            detailTransitions = t
            detailIssue = i
            // Update the item in the list if status changed
            if let idx = items.firstIndex(where: { $0.key == item.key }) {
                let updatedItem = items[idx]
                // Rebuild category based on new status
                let newStatusCat = i.issue.fields.status?.statusCategory?.name ?? updatedItem.statusCategoryName
                let newStatus = i.issue.fields.status?.name ?? updatedItem.status
                let rebuilt = TodoItem(
                    id: updatedItem.id, key: updatedItem.key, summary: updatedItem.summary,
                    status: newStatus, statusCategoryName: newStatusCat,
                    priority: updatedItem.priority, priorityOrder: updatedItem.priorityOrder,
                    dueDate: updatedItem.dueDate, issueType: updatedItem.issueType,
                    issueTypeIconURL: updatedItem.issueTypeIconURL, labels: updatedItem.labels,
                    sprint: updatedItem.sprint, category: updatedItem.category, url: updatedItem.url,
                    updated: Date(), assignee: updatedItem.assignee
                )
                items[idx] = rebuilt
                selectedItem = rebuilt
            }
        } catch {
            detailError = "Failed to transition: \(error.localizedDescription)"
        }
        isTransitioning = false
    }

    // MARK: - Grouped (for list view)

    var groupedItems: [(TodoCategory, [TodoItem])] {
        TodoCategory.allCases.compactMap { cat in
            let catItems = filteredItems.filter { $0.category == cat }
            return catItems.isEmpty ? nil : (cat, catItems)
        }
    }

    var categoryCounts: [TodoCategory: Int] {
        Dictionary(grouping: items, by: \.category).mapValues(\.count)
    }

    var chartSections: [ResultSection] {
        let byPriority = Dictionary(grouping: items, by: \.priority).map { (key, val) in
            ResultRow(label: key, value: Double(val.count))
        }.sorted { $0.value > $1.value }

        let prioritySection = ResultSection(
            title: "By Priority", rows: byPriority, chartHint: .pie
        )

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
            ?? URL(string: "https://boomii.atlassian.net/browse/\(issue.key)")
            ?? URL(string: "https://boomii.atlassian.net")!

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
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}

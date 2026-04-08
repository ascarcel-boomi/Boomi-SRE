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
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case normal = "Normal"
    case low = "Low"
    case lowest = "Lowest"
    var id: String { rawValue }
}

// MARK: - ViewModel

/// ViewModel for the personal TODO dashboard.
@Observable
@MainActor
final class TodoDashboardViewModel {
    var items: [TodoItem] = []
    var isLoading = false
    var error: String?
    var lastRefreshed: Date?
    var cachedChartSections: [ResultSection] = []

    // MARK: Filter state
    var statusFilter: TicketStatusFilter = .all
    var priorityFilter: TicketPriorityFilter = .all
    var assigneeFilter: String = "All"
    var typeFilter: String = "All"

    // MARK: Inline detail state
    var selectedItem: TodoItem? = nil
    var detailIssue: (issue: JiraIssue, raw: [String: Any])? = nil
    var detailComments: [JiraComment] = []
    var detailTransitions: [JiraTransition] = []
    var isLoadingDetail = false
    var detailError: String? = nil

    // MARK: Comment input
    var commentInput: String = ""
    var isPostingComment = false

    // MARK: Transition state
    var isTransitioning = false
    var transitionFeedback: String? = nil

    @ObservationIgnored private let jiraService = JiraService()
    @ObservationIgnored private var sprintFieldId: String?

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
            let typeMatch = typeFilter == "All" || item.issueType == typeFilter
            let assigneeMatch = assigneeFilter == "All" || item.assignee == assigneeFilter
            let spMatch = spCategoryFilter == nil || items(for: spCategoryFilter!).contains(item.key)
            return statusMatch && priorityMatch && typeMatch && assigneeMatch && spMatch
        }
    }

    /// All unique assignees in the current item set (for dropdown).
    var allAssignees: [String] {
        let names = Set(items.map { $0.assignee }).sorted()
        return ["All"] + names
    }

    /// All unique issue types in the current item set (for dropdown), in logical order.
    private static let issueTypeOrder = [
        "Initiative", "Parent Epic", "Epic", "Story", "Task", "Subtask",
        "Operational Request", "Troubleshooting Request", "Access Request",
    ]

    var allIssueTypes: [String] {
        let present = Set(items.map { $0.issueType })
        let ordered = Self.issueTypeOrder.filter { present.contains($0) }
        let extra = present.filter { !Self.issueTypeOrder.contains($0) }.sorted()
        return ["All"] + ordered + extra
    }

    // MARK: - Contextual dropdown options (derived from filtered data)

    /// Available statuses given current filters (excludes status filter itself).
    var availableStatuses: Set<String> {
        Set(itemsFilteredExcluding(.status).map(\.statusCategoryName))
    }

    /// Available priorities given current filters (excludes priority filter itself).
    var availablePriorities: Set<String> {
        Set(itemsFilteredExcluding(.priority).map(\.priority))
    }

    /// Available types given current filters (excludes type filter itself).
    var availableTypes: Set<String> {
        Set(itemsFilteredExcluding(.type).map(\.issueType))
    }

    private enum FilterDimension { case status, priority, type }

    /// Items filtered by all dimensions EXCEPT the specified one.
    private func itemsFilteredExcluding(_ dimension: FilterDimension) -> [TodoItem] {
        items.filter { item in
            let statusMatch = dimension == .status || {
                switch statusFilter {
                case .all: return true
                case .toDo: return item.statusCategoryName == "To Do"
                case .inProgress: return item.statusCategoryName == "In Progress"
                case .done: return item.statusCategoryName == "Done"
                }
            }()
            let priorityMatch = dimension == .priority || priorityFilter == .all || item.priority.lowercased() == priorityFilter.rawValue.lowercased()
            let typeMatch = dimension == .type || typeFilter == "All" || item.issueType == typeFilter
            let assigneeMatch = assigneeFilter == "All" || item.assignee == assigneeFilter
            let spMatch = spCategoryFilter == nil || self.items(for: spCategoryFilter!).contains(item.key)
            return statusMatch && priorityMatch && typeMatch && assigneeMatch && spMatch
        }
    }

    // MARK: - SP Summary

    enum SPCategory: String, CaseIterable {
        case planned = "Planned"
        case unplanned = "Unplanned"
        case inSprint = "In Sprint"
        case overdue = "Overdue"
    }

    /// Planned work = these issue types. Everything else = unplanned.
    private static let plannedIssueTypes: Set<String> = [
        "Initiative", "Parent Epic", "Epic", "Story", "Task", "Subtask"
    ]

    struct SPSummary {
        let plannedPoints: Double      // SP for planned work types
        let plannedCount: Int          // Ticket count for planned work
        let unplannedCount: Int        // Ticket count for unplanned work (no SP)
        let inSprintPoints: Double     // SP for tickets in active sprint
        let inSprintCount: Int         // Ticket count in active sprint
        let overdueCount: Int          // Tickets past due date
    }

    private var rawStoryPoints: [String: Double] = [:]  // key -> SP

    private func isPlannedWork(_ item: TodoItem) -> Bool {
        Self.plannedIssueTypes.contains(item.issueType)
    }

    /// SP summary computed from items filtered by all dimensions except SP category.
    var spSummary: SPSummary {
        let base = items.filter { item in
            let statusMatch: Bool = {
                switch statusFilter {
                case .all: return true
                case .toDo: return item.statusCategoryName == "To Do"
                case .inProgress: return item.statusCategoryName == "In Progress"
                case .done: return item.statusCategoryName == "Done"
                }
            }()
            let priorityMatch = priorityFilter == .all || item.priority.lowercased() == priorityFilter.rawValue.lowercased()
            let typeMatch = typeFilter == "All" || item.issueType == typeFilter
            let assigneeMatch = assigneeFilter == "All" || item.assignee == assigneeFilter
            return statusMatch && priorityMatch && typeMatch && assigneeMatch
        }

        let plannedItems = base.filter { isPlannedWork($0) }
        let unplannedItems = base.filter { !isPlannedWork($0) }
        let inSprintItems = base.filter { $0.sprint?.state == "active" }
        let overdueItems = base.filter { if let due = $0.dueDate { return due < Date() } else { return false } }

        return SPSummary(
            plannedPoints: plannedItems.reduce(0.0) { $0 + (rawStoryPoints[$1.key] ?? 0) },
            plannedCount: plannedItems.count,
            unplannedCount: unplannedItems.count,
            inSprintPoints: inSprintItems.reduce(0.0) { $0 + (rawStoryPoints[$1.key] ?? 0) },
            inSprintCount: inSprintItems.count,
            overdueCount: overdueItems.count
        )
    }

    /// Items matching a given SP category, for filtering on click.
    func items(for category: SPCategory) -> Set<String> {
        switch category {
        case .planned:
            return Set(items.filter { isPlannedWork($0) }.map(\.key))
        case .unplanned:
            return Set(items.filter { !isPlannedWork($0) }.map(\.key))
        case .inSprint:
            return Set(items.filter { $0.sprint?.state == "active" }.map(\.key))
        case .overdue:
            return Set(items.filter { if let due = $0.dueDate { return due < Date() } else { return false } }.map(\.key))
        }
    }

    /// Currently active SP category filter (nil = no SP filter).
    var spCategoryFilter: SPCategory? = nil

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
            let jqlReservedWords: Set<String> = ["DO", "IF", "OR", "IN", "ON", "TO", "AS", "BY", "IS", "NOT", "AND", "WAS", "SET"]
            let quoted = projectKeys.map { jqlReservedWords.contains($0.uppercased()) ? "\"\($0)\"" : $0 }
            let projectFilter = quoted.isEmpty ? "" : " AND project IN (\(quoted.joined(separator: ", ")))"
            let jql = "assignee = currentUser() AND statusCategory NOT IN (Done)\(projectFilter) ORDER BY priority ASC, updated DESC"

            let (result, rawIssues) = try await jiraService.searchIssuesRaw(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql, fields: fields, maxResults: 1000
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
        buildChartSections(from: items)
    }

    /// Chart sections that reflect the current Status/Priority filters.
    var filteredChartSections: [ResultSection] {
        buildChartSections(from: filteredItems)
    }

    /// Priority display order — highest severity first. Used to sort chart segments.
    static let priorityOrder = ["Highest", "Critical", "High", "Medium", "Normal", "Low", "Lowest"]

    /// Sort priority keys in severity order; unknown priorities go at the end.
    private func sortedByPriority(_ keys: [String]) -> [String] {
        keys.sorted { a, b in
            let ai = Self.priorityOrder.firstIndex(of: a) ?? Int.max
            let bi = Self.priorityOrder.firstIndex(of: b) ?? Int.max
            return ai < bi
        }
    }

    private func buildChartSections(from source: [TodoItem]) -> [ResultSection] {
        // Pie chart: slices in priority order (Highest → Lowest)
        let priGroups = Dictionary(grouping: source, by: \.priority)
        let byPriority = sortedByPriority(Array(priGroups.keys)).compactMap { key -> ResultRow? in
            guard let val = priGroups[key] else { return nil }
            return ResultRow(label: key, value: Double(val.count))
        }

        let prioritySection = ResultSection(
            title: "By Priority", rows: byPriority, chartHint: .pie
        )

        // Status stacked bar: segments in priority order within each status
        let statusOrder = ["To Do", "In Progress", "Done"]
        var statusRows: [ResultRow] = []
        for statusCat in statusOrder {
            let statusItems = source.filter { $0.statusCategoryName == statusCat }
            let byPri = Dictionary(grouping: statusItems, by: \.priority)
            for pri in sortedByPriority(Array(byPri.keys)) {
                guard let priItems = byPri[pri] else { continue }
                statusRows.append(ResultRow(
                    label: statusCat, value: Double(priItems.count), group: pri
                ))
            }
        }

        let statusSection = ResultSection(
            title: "By Status", rows: statusRows, chartHint: .stackedBar
        )

        // Type stacked bar: segments in priority order within each type
        let typeGroups = Dictionary(grouping: source, by: \.issueType)
        let typeOrder = Self.issueTypeOrder
        let orderedTypes = typeOrder.filter { typeGroups[$0] != nil }
        let extraTypes = typeGroups.keys.filter { !typeOrder.contains($0) }.sorted()
        var typeRows: [ResultRow] = []
        for typeName in orderedTypes + extraTypes {
            guard let typeItems = typeGroups[typeName] else { continue }
            let byPri = Dictionary(grouping: typeItems, by: \.priority)
            for pri in sortedByPriority(Array(byPri.keys)) {
                guard let priItems = byPri[pri] else { continue }
                typeRows.append(ResultRow(
                    label: typeName, value: Double(priItems.count), group: pri
                ))
            }
        }

        let typeSection = ResultSection(
            title: "By Type", rows: typeRows, chartHint: .stackedBar
        )

        return [statusSection, prioritySection, typeSection]
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

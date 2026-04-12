import Foundation
import SwiftUI
import os.log

/// Lightweight struct holding essential data per node for cascading filter support.
struct WorkMapNode {
    let key: String
    let name: String
    let type: String
    let status: String
    let statusCategory: String
    let assignee: String
    let quarter: String  // from customfield_24155 or label fallback
    let sp: Double?
    let labels: [String]
    let updated: String
    var children: [WorkMapNode]
}

@Observable
@MainActor
final class WorkMapViewModel {
    private static let log = Logger(subsystem: "com.boomi.sre", category: "WorkMapVM")

    var treeJSON: String = ""
    var isLoading = false
    var error: String?
    var epicCount = 0
    var issueCount = 0
    var completionPct = 0.0
    var statusFilter: String = "All"
    var searchText: String = ""
    var assigneeFilter: String = "All"
    var quarterFilter: String = "All"
    var showCompleted: Bool = false

    /// All parsed nodes (project > epic > children) for cascading filter computation.
    var allNodes: [WorkMapNode] = []

    /// Quarters derived from filtered data (cascading).
    var uniqueQuarters: [String] {
        let quarterPattern = /Q\dCY\d{2}/
        var set = Set<String>()
        let nodes = assigneeFilter == "All" ? allNodes : allNodes.map { project in
            var p = project
            p.children = project.children.filter { epic in
                epic.assignee == assigneeFilter ||
                epic.children.contains(where: { $0.assignee == assigneeFilter })
            }
            return p
        }.filter { !$0.children.isEmpty }

        for project in nodes {
            for epic in project.children {
                let q = epic.quarter
                if !q.isEmpty, let m = q.firstMatch(of: quarterPattern) {
                    set.insert(String(m.output))
                }
                // Also scan child labels for quarter values
                for child in epic.children {
                    for label in child.labels {
                        if let m = label.firstMatch(of: quarterPattern) {
                            set.insert(String(m.output))
                        }
                    }
                }
            }
        }
        // Sort chronologically: by year (CY25, CY26) then quarter (Q1, Q2, Q3, Q4)
        return set.sorted { a, b in
            let aYear = Int(a.suffix(2)) ?? 0
            let bYear = Int(b.suffix(2)) ?? 0
            if aYear != bYear { return aYear < bYear }
            let aQ = Int(a.dropFirst(1).prefix(1)) ?? 0
            let bQ = Int(b.dropFirst(1).prefix(1)) ?? 0
            return aQ < bQ
        }
    }

    /// Assignees derived from filtered data (cascading).
    var uniqueAssignees: [String] {
        var set = Set<String>()
        let nodes = quarterFilter == "All" ? allNodes : allNodes.map { project in
            var p = project
            p.children = project.children.filter { epic in
                let q = epic.quarter
                return q.hasPrefix(quarterFilter) ||
                    epic.labels.contains(where: { $0.hasPrefix(quarterFilter) })
            }
            return p
        }.filter { !$0.children.isEmpty }

        for project in nodes {
            for epic in project.children {
                if epic.assignee != "Unassigned" { set.insert(epic.assignee) }
                for child in epic.children {
                    if child.assignee != "Unassigned" { set.insert(child.assignee) }
                }
            }
        }
        return set.sorted()
    }

    @ObservationIgnored private let jiraService = JiraService()

    func loadTree(appState: AppState) async {
        guard appState.isJiraConfigured else {
            withAnimation(.none) { error = "Jira not configured." }
            return
        }
        withAnimation(.none) { isLoading = true; error = nil }

        do {
            // Use the Jira projects mapped in Products & Resources for the selected teams.
            let projectKeys = appState.activeJiraProjectKeys
            guard !projectKeys.isEmpty else {
                withAnimation(.none) { isLoading = false; error = "No active Jira projects." }
                return
            }
            let quotedKeys = projectKeys.map { k in
                let reserved: Set<String> = ["DO", "IF", "OR", "IN", "IS", "ON", "TO", "AS", "BY", "OF", "NO", "IT", "GO", "AT"]
                return reserved.contains(k.uppercased()) ? "\"\(k)\"" : k
            }.joined(separator: ", ")
            let doneClause = showCompleted
                ? "AND created >= \"2025-01-01\""
                : "AND statusCategory NOT IN (Done)"
            let epicJQL = "issuetype = Epic AND project IN (\(quotedKeys)) \(doneClause) ORDER BY project ASC, key ASC"
            Self.log.notice("loadTree: isAllProducts=\(appState.isAllProducts, privacy: .public), keys=\(quotedKeys, privacy: .public)")
            let spFieldId = appState.storyPointsFieldId

            // Paginated fetch — /search/jql caps at ~100 per page
            let (epicIssues, epicRawIssues) = try await jiraService.searchAllPaginated(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, jql: epicJQL,
                fields: ["summary", "status", "priority", "assignee", "updated", "labels",
                         spFieldId, "customfield_24155"]
            )

            // Extract story points and quarter from raw epic data
            let quarterFieldId = "customfield_24155"
            let quarterPattern = /Q\dCY\d{2}/
            var epicSPMap: [String: Double] = [:]
            var epicQuarterMap: [String: String] = [:]
            for (i, epic) in epicIssues.enumerated() {
                let rawFields = (epicRawIssues.indices.contains(i)
                    ? epicRawIssues[i]["fields"] as? [String: Any]
                    : nil) ?? [:]
                if let sp = rawFields[spFieldId] as? Double {
                    epicSPMap[epic.key] = sp
                } else if let sp = rawFields[spFieldId] as? Int {
                    epicSPMap[epic.key] = Double(sp)
                }
                // Extract "Committed for Quarter" — select field: {"value": "Q2CY26 - Done"}
                if let qObj = rawFields[quarterFieldId] as? [String: Any],
                   let qValue = qObj["value"] as? String {
                    epicQuarterMap[epic.key] = qValue
                }
                // Fallback: extract quarter from labels if field is not populated
                if epicQuarterMap[epic.key] == nil {
                    let labels = epic.fields.labels ?? []
                    for label in labels {
                        if let match = label.firstMatch(of: quarterPattern) {
                            epicQuarterMap[epic.key] = String(match.output)
                            break
                        }
                    }
                }
            }

            var epicChildMap: [String: [JiraIssue]] = [:]
            var childSPMap: [String: Double] = [:]
            var childLabelsMap: [String: [String]] = [:]
            let epicKeys = epicIssues.map(\.key)

            // Fetch children for all epics concurrently
            await withTaskGroup(of: (String, [JiraIssue], [String: Double], [String: [String]]).self) { group in
                for epicKey in epicKeys {
                    group.addTask {
                        let childJQL = "parent = \(epicKey) ORDER BY status ASC, key ASC"
                        guard let (childResult, childRaw) = try? await self.jiraService.searchIssuesRaw(
                            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                            apiToken: appState.jiraAPIToken, jql: childJQL,
                            fields: ["summary", "status", "priority", "issuetype",
                                     "assignee", "updated", "labels", spFieldId],
                            maxResults: 200
                        ) else {
                            return (epicKey, [], [:], [:])
                        }
                        var spMap: [String: Double] = [:]
                        var labelsMap: [String: [String]] = [:]
                        for (i, child) in childResult.issues.enumerated() {
                            let rawFields = (childRaw.indices.contains(i)
                                ? childRaw[i]["fields"] as? [String: Any]
                                : nil) ?? [:]
                            if let sp = rawFields[spFieldId] as? Double {
                                spMap[child.key] = sp
                            } else if let sp = rawFields[spFieldId] as? Int {
                                spMap[child.key] = Double(sp)
                            }
                            labelsMap[child.key] = child.fields.labels ?? []
                        }
                        return (epicKey, childResult.issues, spMap, labelsMap)
                    }
                }
                for await (epicKey, children, spMap, labelsMap) in group {
                    epicChildMap[epicKey] = children
                    for (k, v) in spMap { childSPMap[k] = v }
                    for (k, v) in labelsMap { childLabelsMap[k] = v }
                }
            }

            let tree = buildTreeJSON(
                epics: epicIssues,
                childMap: epicChildMap,
                epicSPMap: epicSPMap,
                childSPMap: childSPMap,
                epicQuarterMap: epicQuarterMap
            )
            let jsonData = try JSONSerialization.data(withJSONObject: tree, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let allChildren = epicChildMap.values.flatMap { $0 }
            let allIssues = epicIssues.count + allChildren.count
            let doneCount = epicIssues.filter { $0.fields.status?.statusCategory?.key == "done" }.count
                + allChildren.filter { $0.fields.status?.statusCategory?.key == "done" }.count
            let pct = allIssues > 0 ? Double(doneCount) / Double(allIssues) * 100 : 0

            // Build WorkMapNode tree for cascading filter support
            var projectNodeMap: [String: [WorkMapNode]] = [:]
            for epic in epicIssues {
                let projectKey = String(epic.key.split(separator: "-").first ?? Substring("?"))
                let children = epicChildMap[epic.key] ?? []
                let childNodes: [WorkMapNode] = children.map { child in
                    WorkMapNode(
                        key: child.key,
                        name: child.fields.summary ?? child.key,
                        type: child.fields.issuetype?.name.lowercased() ?? "task",
                        status: child.fields.status?.name ?? "Unknown",
                        statusCategory: child.fields.status?.statusCategory?.key ?? "undefined",
                        assignee: child.fields.assignee?.displayName ?? "Unassigned",
                        quarter: "",
                        sp: childSPMap[child.key],
                        labels: childLabelsMap[child.key] ?? child.fields.labels ?? [],
                        updated: child.fields.updated ?? "",
                        children: []
                    )
                }
                let epicNode = WorkMapNode(
                    key: epic.key,
                    name: epic.fields.summary ?? epic.key,
                    type: "epic",
                    status: epic.fields.status?.name ?? "Unknown",
                    statusCategory: epic.fields.status?.statusCategory?.key ?? "undefined",
                    assignee: epic.fields.assignee?.displayName ?? "Unassigned",
                    quarter: epicQuarterMap[epic.key] ?? "",
                    sp: epicSPMap[epic.key],
                    labels: epic.fields.labels ?? [],
                    updated: epic.fields.updated ?? "",
                    children: childNodes
                )
                projectNodeMap[projectKey, default: []].append(epicNode)
            }
            let projectNodes: [WorkMapNode] = projectNodeMap.sorted(by: { $0.key < $1.key }).map { (key, epics) in
                WorkMapNode(
                    key: key, name: key, type: "project",
                    status: "", statusCategory: "", assignee: "",
                    quarter: "", sp: nil, labels: [], updated: "",
                    children: epics
                )
            }

            withAnimation(.none) {
                treeJSON = jsonString
                epicCount = epicIssues.count
                issueCount = allIssues
                completionPct = pct
                allNodes = projectNodes
                isLoading = false
            }
            Self.log.notice("loadTree: \(epicIssues.count, privacy: .public) epics, \(allIssues, privacy: .public) total issues")
        } catch {
            withAnimation(.none) {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func buildTreeJSON(
        epics: [JiraIssue],
        childMap: [String: [JiraIssue]],
        epicSPMap: [String: Double],
        childSPMap: [String: Double],
        epicQuarterMap: [String: String] = [:]
    ) -> [String: Any] {
        var projectGroups: [String: [JiraIssue]] = [:]
        for epic in epics {
            let projectKey = String(epic.key.split(separator: "-").first ?? Substring("?"))
            projectGroups[projectKey, default: []].append(epic)
        }

        let projectNodes: [[String: Any]] = projectGroups.sorted(by: { $0.key < $1.key }).map { (projectKey, projectEpics) in
            let epicNodes: [[String: Any]] = projectEpics.map { epic in
                let children = childMap[epic.key] ?? []
                let childNodes: [[String: Any]] = children.map { child in
                    var node: [String: Any] = [
                        "key": child.key,
                        "name": child.fields.summary ?? child.key,
                        "type": child.fields.issuetype?.name.lowercased() ?? "task",
                        "status": child.fields.status?.name ?? "Unknown",
                        "statusCategory": child.fields.status?.statusCategory?.key ?? "undefined",
                        "assignee": child.fields.assignee?.displayName ?? "Unassigned",
                        "updated": child.fields.updated ?? "",
                        "labels": child.fields.labels ?? []
                    ]
                    if let sp = childSPMap[child.key] {
                        node["sp"] = sp
                    }
                    return node
                }
                var epicNode: [String: Any] = [
                    "key": epic.key,
                    "name": epic.fields.summary ?? epic.key,
                    "type": "epic",
                    "status": epic.fields.status?.name ?? "Unknown",
                    "statusCategory": epic.fields.status?.statusCategory?.key ?? "undefined",
                    "assignee": epic.fields.assignee?.displayName ?? "Unassigned",
                    "updated": epic.fields.updated ?? "",
                    "labels": epic.fields.labels ?? [],
                    "children": childNodes
                ]
                if let sp = epicSPMap[epic.key] {
                    epicNode["sp"] = sp
                }
                if let quarter = epicQuarterMap[epic.key] {
                    epicNode["quarter"] = quarter
                }
                return epicNode
            }
            return [
                "key": projectKey,
                "name": projectKey,
                "type": "project",
                "status": "",
                "statusCategory": "",
                "children": epicNodes
            ]
        }

        return [
            "name": "Work Map",
            "key": "root",
            "type": "root",
            "status": "",
            "statusCategory": "",
            "children": projectNodes
        ]
    }
}

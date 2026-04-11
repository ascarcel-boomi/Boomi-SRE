import Foundation
import SwiftUI
import os.log

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
            let epicJQL = "issuetype = Epic AND project IN (\(quotedKeys)) AND statusCategory NOT IN (Done) ORDER BY project ASC, key ASC"
            Self.log.notice("loadTree: isAllProducts=\(appState.isAllProducts, privacy: .public), keys=\(quotedKeys, privacy: .public)")
            let spFieldId = appState.storyPointsFieldId

            // Paginated fetch — /search/jql caps at ~100 per page
            let (epicIssues, epicRawIssues) = try await jiraService.searchAllPaginated(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, jql: epicJQL,
                fields: ["summary", "status", "priority", "assignee", "updated", spFieldId]
            )

            // Extract story points from raw epic data
            var epicSPMap: [String: Double] = [:]
            for (i, epic) in epicIssues.enumerated() {
                let rawFields = (epicRawIssues.indices.contains(i)
                    ? epicRawIssues[i]["fields"] as? [String: Any]
                    : nil) ?? [:]
                if let sp = rawFields[spFieldId] as? Double {
                    epicSPMap[epic.key] = sp
                } else if let sp = rawFields[spFieldId] as? Int {
                    epicSPMap[epic.key] = Double(sp)
                }
            }

            var epicChildMap: [String: [JiraIssue]] = [:]
            var childSPMap: [String: Double] = [:]
            let epicKeys = epicIssues.map(\.key)

            // Fetch children for all epics concurrently
            await withTaskGroup(of: (String, [JiraIssue], [String: Double]).self) { group in
                for epicKey in epicKeys {
                    group.addTask {
                        let childJQL = "parent = \(epicKey) ORDER BY status ASC, key ASC"
                        guard let (childResult, childRaw) = try? await self.jiraService.searchIssuesRaw(
                            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                            apiToken: appState.jiraAPIToken, jql: childJQL,
                            fields: ["summary", "status", "priority", "issuetype",
                                     "assignee", "updated", spFieldId],
                            maxResults: 200
                        ) else {
                            return (epicKey, [], [:])
                        }
                        var spMap: [String: Double] = [:]
                        for (i, child) in childResult.issues.enumerated() {
                            let rawFields = (childRaw.indices.contains(i)
                                ? childRaw[i]["fields"] as? [String: Any]
                                : nil) ?? [:]
                            if let sp = rawFields[spFieldId] as? Double {
                                spMap[child.key] = sp
                            } else if let sp = rawFields[spFieldId] as? Int {
                                spMap[child.key] = Double(sp)
                            }
                        }
                        return (epicKey, childResult.issues, spMap)
                    }
                }
                for await (epicKey, children, spMap) in group {
                    epicChildMap[epicKey] = children
                    for (k, v) in spMap { childSPMap[k] = v }
                }
            }

            let tree = buildTreeJSON(
                epics: epicIssues,
                childMap: epicChildMap,
                epicSPMap: epicSPMap,
                childSPMap: childSPMap
            )
            let jsonData = try JSONSerialization.data(withJSONObject: tree, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let allChildren = epicChildMap.values.flatMap { $0 }
            let allIssues = epicIssues.count + allChildren.count
            let doneCount = epicIssues.filter { $0.fields.status?.statusCategory?.key == "done" }.count
                + allChildren.filter { $0.fields.status?.statusCategory?.key == "done" }.count
            let pct = allIssues > 0 ? Double(doneCount) / Double(allIssues) * 100 : 0

            withAnimation(.none) {
                treeJSON = jsonString
                epicCount = epicIssues.count
                issueCount = allIssues
                completionPct = pct
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
        childSPMap: [String: Double]
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
                        "updated": child.fields.updated ?? ""
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
                    "children": childNodes
                ]
                if let sp = epicSPMap[epic.key] {
                    epicNode["sp"] = sp
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

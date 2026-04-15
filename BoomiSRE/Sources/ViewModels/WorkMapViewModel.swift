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

/// Codable mirror of WorkMapNode for disk caching.
struct WorkMapNodeCodable: Codable {
    let key: String
    let name: String
    let type: String
    let status: String
    let statusCategory: String
    let assignee: String
    let quarter: String
    let sp: Double?
    let labels: [String]
    let updated: String
    var children: [WorkMapNodeCodable]
}

private extension WorkMapNode {
    func toCodable() -> WorkMapNodeCodable {
        WorkMapNodeCodable(
            key: key, name: name, type: type, status: status,
            statusCategory: statusCategory, assignee: assignee, quarter: quarter,
            sp: sp, labels: labels, updated: updated,
            children: children.map { $0.toCodable() }
        )
    }
}

private extension WorkMapNodeCodable {
    func toNode() -> WorkMapNode {
        WorkMapNode(
            key: key, name: name, type: type, status: status,
            statusCategory: statusCategory, assignee: assignee, quarter: quarter,
            sp: sp, labels: labels, updated: updated,
            children: children.map { $0.toNode() }
        )
    }
}

/// Disk cache entry for the Work Map feature.
private struct WorkMapCache: Codable {
    let treeJSON: String
    let projectKeys: [String]   // cache key component
    let showCompleted: Bool      // cache key component
    let epicCount: Int
    let issueCount: Int
    let completionPct: Double
    let allNodes: [WorkMapNodeCodable]
    let timestamp: Date
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

    var myFocusActive = false
    var eisenhowerResult: EisenhowerResult?
    var myEpicCount = 0
    var myIssueCount = 0

    @ObservationIgnored private var watchedKeys: Set<String>?
    @ObservationIgnored private var watchedKeysTask: Task<Set<String>, Never>?

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

    /// Path to the on-disk cache file.
    @ObservationIgnored private let cacheFileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".boomi_sre_workmap_cache.json")
    }()

    // MARK: - Cache helpers

    /// TTL: 24 h when showCompleted (Done epics rarely change), 5 min otherwise.
    private func cacheTTL(showCompleted: Bool) -> TimeInterval {
        showCompleted ? 24 * 60 * 60 : 5 * 60
    }

    /// Returns a valid cache entry if the keys and TTL match, otherwise nil.
    private func loadFromDisk(projectKeys: [String], showCompleted: Bool) -> WorkMapCache? {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: cacheFileURL) else { return nil }
        guard let cache = try? JSONDecoder().decode(WorkMapCache.self, from: data) else { return nil }

        // Key must match
        guard cache.projectKeys.sorted() == projectKeys.sorted(),
              cache.showCompleted == showCompleted else { return nil }

        // TTL check
        let age = Date().timeIntervalSince(cache.timestamp)
        guard age < cacheTTL(showCompleted: showCompleted) else { return nil }

        return cache
    }

    /// Serialises and atomically writes cache to disk (does not block caller — called from a detached task).
    private nonisolated func saveToDisk(_ cache: WorkMapCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        let url = cacheFileURL
        // Atomic write via a temp file in the same directory
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".boomi_sre_workmap_cache.json.tmp")
        do {
            try data.write(to: tmpURL, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            // Non-fatal — best effort
            Logger(subsystem: "com.boomi.sre", category: "WorkMapVM")
                .warning("Cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Load

    func loadTree(appState: AppState) async {
        guard appState.isJiraConfigured else {
            withAnimation(.none) { error = "Jira not configured." }
            return
        }

        let projectKeys = appState.activeJiraProjectKeys
        guard !projectKeys.isEmpty else {
            withAnimation(.none) { isLoading = false; error = "No active Jira projects." }
            return
        }

        // ── Cache check ──────────────────────────────────────────────────────
        let cachedEntry = loadFromDisk(projectKeys: projectKeys, showCompleted: showCompleted)
        let servedFromCache = cachedEntry != nil

        if let entry = cachedEntry {
            // Serve cached data immediately — no loading spinner
            withAnimation(.none) {
                treeJSON = entry.treeJSON
                epicCount = entry.epicCount
                issueCount = entry.issueCount
                completionPct = entry.completionPct
                allNodes = entry.allNodes.map { $0.toNode() }
                isLoading = false
                self.error = nil
            }
            Self.log.notice("loadTree: served from cache (\(entry.epicCount, privacy: .public) epics), refreshing in background")
        } else {
            // No cache — show spinner for first-ever load
            withAnimation(.none) { isLoading = true; error = nil }
        }

        // ── Fetch fresh data (always, regardless of cache) ───────────────────
        do {
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
                // Normalize to just the "Q\dCY\d{2}" portion (strip suffixes like " - Done")
                if let qObj = rawFields[quarterFieldId] as? [String: Any],
                   let qValue = qObj["value"] as? String,
                   let match = qValue.firstMatch(of: quarterPattern) {
                    epicQuarterMap[epic.key] = String(match.output)
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
            Self.log.notice("loadTree: \(epicIssues.count, privacy: .public) epics, \(allIssues, privacy: .public) total issues\(servedFromCache ? " (background refresh)" : "", privacy: .public)")

            // If My Focus is active, re-classify with fresh data
            if myFocusActive {
                let displayName = appState.jiraDisplayName
                let watched = watchedKeys ?? []
                let now = Date()
                let cal = Calendar.current
                let month = cal.component(.month, from: now)
                let year = cal.component(.year, from: now) % 100
                let q = (month - 1) / 3 + 1
                let currentQuarter = "Q\(q)CY\(year)"
                let result = EisenhowerClassifier.classify(
                    nodes: allNodes,
                    userDisplayName: displayName,
                    watchedKeys: watched,
                    currentQuarter: currentQuarter
                )
                let userEpics = allNodes.flatMap(\.children).filter { epic in
                    result.userNodeKeys.contains(epic.key)
                }.count
                withAnimation(.none) {
                    eisenhowerResult = result
                    myEpicCount = userEpics
                    myIssueCount = result.totalCount
                }
            }

            // ── Persist to disk cache ─────────────────────────────────────────
            let cacheEntry = WorkMapCache(
                treeJSON: jsonString,
                projectKeys: projectKeys,
                showCompleted: showCompleted,
                epicCount: epicIssues.count,
                issueCount: allIssues,
                completionPct: pct,
                allNodes: projectNodes.map { $0.toCodable() },
                timestamp: Date()
            )
            Task.detached(priority: .background) { [weak self] in
                self?.saveToDisk(cacheEntry)
            }

        } catch {
            withAnimation(.none) {
                // If we already served from cache, don't clobber the UI with an error
                if !servedFromCache {
                    self.error = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    // MARK: - My Focus

    /// Fetch ticket keys the current user is watching. Cached for the session.
    private func fetchWatchedKeys(appState: AppState) async -> Set<String> {
        if let cached = watchedKeys { return cached }

        // Deduplicate concurrent calls
        if let existing = watchedKeysTask {
            return await existing.value
        }

        let task = Task<Set<String>, Never> {
            do {
                let jql = "watcher = currentUser() AND statusCategory != Done ORDER BY updated DESC"
                let result = try await jiraService.searchIssues(
                    baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken, jql: jql,
                    fields: ["summary"], maxResults: 200
                )
                let keys = Set(result.issues.map(\.key))
                return keys
            } catch {
                Self.log.warning("Watcher fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        watchedKeysTask = task
        let result = await task.value
        watchedKeys = result
        watchedKeysTask = nil
        return result
    }

    /// Activate My Focus mode: resolve display name, fetch watchers, classify, update state.
    func activateMyFocus(appState: AppState) async {
        await appState.resolveJiraDisplayName()
        let displayName = appState.jiraDisplayName
        guard !displayName.isEmpty else {
            Self.log.warning("My Focus: could not resolve display name")
            withAnimation(.none) { myFocusActive = false }
            return
        }

        let watched = await fetchWatchedKeys(appState: appState)

        let now = Date()
        let cal = Calendar.current
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now) % 100
        let q = (month - 1) / 3 + 1
        let currentQuarter = "Q\(q)CY\(year)"

        let result = EisenhowerClassifier.classify(
            nodes: allNodes,
            userDisplayName: displayName,
            watchedKeys: watched,
            currentQuarter: currentQuarter
        )

        let userEpics = allNodes.flatMap(\.children).filter { epic in
            result.userNodeKeys.contains(epic.key)
        }.count
        let userIssues = result.totalCount

        withAnimation(.none) {
            eisenhowerResult = result
            myEpicCount = userEpics
            myIssueCount = userIssues
            myFocusActive = true
        }
    }

    /// Deactivate My Focus mode: clear classification, restore tree.
    func deactivateMyFocus() {
        withAnimation(.none) {
            myFocusActive = false
            eisenhowerResult = nil
            myEpicCount = 0
            myIssueCount = 0
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

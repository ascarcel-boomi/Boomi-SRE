import Foundation
import SwiftUI

/// Full ticket detail data extracted from raw Jira JSON.
struct TicketDetail {
    let key: String
    let summary: String
    let status: String
    let statusCategory: String
    let priority: String
    let issueType: String
    let assignee: String
    let reporter: String
    let creator: String
    let created: String
    let updated: String
    let startDate: String
    let dueDate: String
    let labels: [String]
    let description: String
    let sprint: JiraSprint?
    let parentKey: String
    let parentSummary: String
    let subtasks: [(key: String, summary: String, status: String)]
    let comments: [JiraComment]
    let history: [HistoryEntry]
    let url: URL
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let date: String
    let author: String
    let field: String
    let from: String
    let to: String
}

@MainActor
final class TicketDetailViewModel: ObservableObject {
    @Published var detail: TicketDetail?
    @Published var transitions: [JiraTransition] = []
    @Published var isLoading = false
    @Published var actionMessage: String?
    @Published var actionIsError = false

    private let jiraService = JiraService()

    func load(key: String, appState: AppState) async {
        isLoading = true
        actionMessage = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)

        do {
            async let issueResult = jiraService.getIssue(
                baseURL: baseURL, email: email, apiToken: token, key: key)
            async let transResult = jiraService.getTransitions(
                baseURL: baseURL, email: email, apiToken: token, key: key)

            let (issueData, trans) = try await (issueResult, transResult)
            transitions = trans
            detail = parseDetail(key: key, raw: issueData.raw, baseURL: baseURL)
            isLoading = false
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
            isLoading = false
        }
    }

    func transition(to t: JiraTransition, key: String, appState: AppState) async {
        actionMessage = nil
        do {
            try await jiraService.transitionIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, transitionId: t.id)
            actionMessage = "Moved to \(t.toStatus)"
            actionIsError = false
            await load(key: key, appState: appState)
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }

    func addComment(text: String, key: String, appState: AppState) async {
        actionMessage = nil
        do {
            try await jiraService.addComment(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, body: text)
            actionMessage = "Comment added"
            actionIsError = false
            await load(key: key, appState: appState)
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }

    func assign(accountId: String?, key: String, appState: AppState) async {
        actionMessage = nil
        do {
            try await jiraService.assignIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, accountId: accountId)
            actionMessage = accountId != nil ? "Assigned" : "Unassigned"
            actionIsError = false
            await load(key: key, appState: appState)
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }

    func assignToMe(key: String, appState: AppState) async {
        do {
            let myId = try await jiraService.getMyAccountId(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken)
            await assign(accountId: myId, key: key, appState: appState)
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }

    // MARK: - Parse raw JSON into TicketDetail

    private func parseDetail(key: String, raw: [String: Any], baseURL: String) -> TicketDetail {
        let f = raw["fields"] as? [String: Any] ?? [:]

        let status = f["status"] as? [String: Any] ?? [:]
        let statusCat = status["statusCategory"] as? [String: Any] ?? [:]

        // Sprint
        var sprint: JiraSprint?
        if let sprints = f["customfield_10020"] as? [[String: Any]],
           let active = sprints.first(where: { ($0["state"] as? String) == "active" }) ?? sprints.last {
            sprint = JiraSprint(
                id: active["id"] as? Int ?? 0,
                name: active["name"] as? String ?? "",
                state: active["state"] as? String ?? "",
                startDate: active["startDate"] as? String,
                endDate: active["endDate"] as? String
            )
        }

        // Parent
        let parent = f["parent"] as? [String: Any] ?? [:]
        let parentFields = parent["fields"] as? [String: Any] ?? [:]

        // Subtasks
        let rawSubtasks = f["subtasks"] as? [[String: Any]] ?? []
        let subtasks = rawSubtasks.map { st in
            let stf = st["fields"] as? [String: Any] ?? [:]
            let stStatus = (stf["status"] as? [String: Any])?["name"] as? String ?? "?"
            return (key: st["key"] as? String ?? "?",
                    summary: stf["summary"] as? String ?? "",
                    status: stStatus)
        }

        // Comments
        let commentObj = f["comment"] as? [String: Any] ?? [:]
        let rawComments = commentObj["comments"] as? [[String: Any]] ?? []
        let comments = rawComments.map { c in
            let author = (c["author"] as? [String: Any])?["displayName"] as? String ?? "Unknown"
            let created = (c["created"] as? String ?? "").prefix(16).replacingOccurrences(of: "T", with: " ")
            let body = extractTextFromADF(c["body"] as? [String: Any])
            return JiraComment(author: author, created: String(created), body: body)
        }

        // History from changelog
        let changelog = raw["changelog"] as? [String: Any] ?? [:]
        let histories = changelog["histories"] as? [[String: Any]] ?? []
        var historyEntries: [HistoryEntry] = []
        for h in histories {
            let author = (h["author"] as? [String: Any])?["displayName"] as? String ?? "?"
            let date = (h["created"] as? String ?? "").prefix(16).replacingOccurrences(of: "T", with: " ")
            for item in (h["items"] as? [[String: Any]] ?? []) {
                historyEntries.append(HistoryEntry(
                    date: String(date),
                    author: author,
                    field: item["field"] as? String ?? "?",
                    from: (item["fromString"] as? String) ?? "",
                    to: (item["toString"] as? String) ?? ""
                ))
            }
        }
        // Reverse so newest is first
        historyEntries.reverse()

        let url = URL(string: "\(baseURL.hasSuffix("/") ? baseURL : baseURL + "/")browse/\(key)")
            ?? URL(string: "https://boomii.atlassian.net/browse/\(key)")!

        return TicketDetail(
            key: key,
            summary: f["summary"] as? String ?? "",
            status: status["name"] as? String ?? "Unknown",
            statusCategory: statusCat["name"] as? String ?? "",
            priority: (f["priority"] as? [String: Any])?["name"] as? String ?? "Medium",
            issueType: (f["issuetype"] as? [String: Any])?["name"] as? String ?? "",
            assignee: (f["assignee"] as? [String: Any])?["displayName"] as? String ?? "Unassigned",
            reporter: (f["reporter"] as? [String: Any])?["displayName"] as? String ?? "Unknown",
            creator: (f["creator"] as? [String: Any])?["displayName"] as? String ?? "Unknown",
            created: String((f["created"] as? String ?? "").prefix(19)).replacingOccurrences(of: "T", with: " "),
            updated: String((f["updated"] as? String ?? "").prefix(19)).replacingOccurrences(of: "T", with: " "),
            startDate: f["customfield_10015"] as? String ?? "",
            dueDate: f["duedate"] as? String ?? "",
            labels: f["labels"] as? [String] ?? [],
            description: extractTextFromADF(f["description"] as? [String: Any]),
            sprint: sprint,
            parentKey: parent["key"] as? String ?? "",
            parentSummary: parentFields["summary"] as? String ?? "",
            subtasks: subtasks,
            comments: comments,
            history: historyEntries,
            url: url
        )
    }

    private func extractTextFromADF(_ node: [String: Any]?) -> String {
        guard let node else { return "" }
        var parts: [String] = []
        if let text = node["text"] as? String { parts.append(text) }
        if let content = node["content"] as? [[String: Any]] {
            for child in content {
                let t = extractTextFromADF(child)
                if !t.isEmpty { parts.append(t) }
            }
        }
        let nodeType = node["type"] as? String ?? ""
        if ["paragraph", "heading", "bulletList", "orderedList", "listItem"].contains(nodeType) {
            return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces) + "\n"
        }
        return parts.joined(separator: "")
    }
}

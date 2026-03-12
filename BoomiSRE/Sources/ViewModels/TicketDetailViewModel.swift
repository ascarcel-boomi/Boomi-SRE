import Foundation
import SwiftUI

/// ViewModel for the ticket detail / action panel.
@MainActor
final class TicketDetailViewModel: ObservableObject {
    @Published var issue: JiraIssue?
    @Published var transitions: [JiraTransition] = []
    @Published var comments: [JiraComment] = []
    @Published var assigneeName: String = "Unassigned"
    @Published var description: String = ""
    @Published var isLoading = false
    @Published var actionMessage: String?
    @Published var actionIsError = false

    private let jiraService = JiraService()

    /// Load full ticket details.
    func load(key: String, appState: AppState) async {
        isLoading = true
        actionMessage = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)

        do {
            // Fetch issue details + transitions in parallel
            async let issueResult = jiraService.getIssue(
                baseURL: baseURL, email: email, apiToken: token, key: key)
            async let transResult = jiraService.getTransitions(
                baseURL: baseURL, email: email, apiToken: token, key: key)

            let (issueData, trans) = try await (issueResult, transResult)
            issue = issueData.issue
            transitions = trans

            // Extract comments from raw JSON (ADF → plain text)
            let rawFields = issueData.raw["fields"] as? [String: Any] ?? [:]
            comments = extractComments(from: rawFields)
            description = extractDescription(from: rawFields)

            // Extract assignee
            if let assignee = rawFields["assignee"] as? [String: Any],
               let name = assignee["displayName"] as? String {
                assigneeName = name
            } else {
                assigneeName = "Unassigned"
            }

            isLoading = false
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
            isLoading = false
        }
    }

    /// Transition the ticket to a new status.
    func transition(to t: JiraTransition, key: String, appState: AppState) async {
        actionMessage = nil
        do {
            try await jiraService.transitionIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, transitionId: t.id)
            actionMessage = "Moved to \(t.toStatus)"
            actionIsError = false
            // Reload to reflect new status
            await load(key: key, appState: appState)
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }

    /// Add a comment to the ticket.
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

    /// Assign the ticket to a user.
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

    /// Assign to myself.
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

    // MARK: - ADF parsing

    /// Extract plain-text comments from the raw comment field.
    private func extractComments(from fields: [String: Any]) -> [JiraComment] {
        guard let commentObj = fields["comment"] as? [String: Any],
              let commentList = commentObj["comments"] as? [[String: Any]] else { return [] }

        return commentList.compactMap { c in
            let author = (c["author"] as? [String: Any])?["displayName"] as? String ?? "Unknown"
            let created = (c["created"] as? String ?? "").prefix(16).replacingOccurrences(of: "T", with: " ")
            let bodyAdf = c["body"] as? [String: Any]
            let text = extractTextFromADF(bodyAdf)
            return JiraComment(author: author, created: String(created), body: text)
        }
    }

    /// Extract plain-text description from ADF.
    private func extractDescription(from fields: [String: Any]) -> String {
        guard let desc = fields["description"] as? [String: Any] else { return "" }
        return extractTextFromADF(desc)
    }

    /// Recursively extract plain text from Atlassian Document Format.
    private func extractTextFromADF(_ node: [String: Any]?) -> String {
        guard let node else { return "" }
        var parts: [String] = []

        if let text = node["text"] as? String {
            parts.append(text)
        }

        if let content = node["content"] as? [[String: Any]] {
            for child in content {
                let childText = extractTextFromADF(child)
                if !childText.isEmpty {
                    parts.append(childText)
                }
            }
        }

        let nodeType = node["type"] as? String ?? ""
        if ["paragraph", "heading", "bulletList", "orderedList", "listItem"].contains(nodeType) {
            return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces) + "\n"
        }
        return parts.joined(separator: "")
    }
}

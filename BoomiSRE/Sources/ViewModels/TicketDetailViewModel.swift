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

@Observable
@MainActor
final class TicketDetailViewModel {
    var detail: TicketDetail?
    var transitions: [JiraTransition] = []
    var isLoading = false
    var actionMessage: String?
    var actionIsError = false
    var aiAnalysis: String?
    var isAnalyzing = false
    var aiError: String?
    var devInfo: JiraDevInfo?
    var issueTypeIconURL: URL?

    @ObservationIgnored private var devInfoTask: Task<Void, Never>?

    // MARK: - AI Extended Actions
    var draftedContent: String?       // last drafted comment / PR desc / subtasks / estimate
    var draftedContentType: String?   // label shown above the draft ("Draft Comment", etc.)
    var isGeneratingDraft = false
    var draftError: String?
    var followUpQuestion: String = ""
    var followUpHistory: [(question: String, answer: String)] = []
    var isAnsweringFollowUp = false

    @ObservationIgnored private let jiraService = JiraService()
    @ObservationIgnored private let claudeService = ClaudeService()
    @ObservationIgnored private var depthHint: String = ""

    func load(key: String, appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
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

            // Extract issue type icon URL
            let fields = issueData.raw["fields"] as? [String: Any] ?? [:]
            if let iconStr = (fields["issuetype"] as? [String: Any])?["iconUrl"] as? String {
                issueTypeIconURL = URL(string: iconStr)
            }

            // Fetch dev info (PRs, commits) in background
            let issueId = issueData.raw["id"] as? String ?? ""
            if !issueId.isEmpty {
                devInfoTask?.cancel()
                devInfoTask = Task {
                    let info = try? await jiraService.getDevInfo(
                        baseURL: baseURL, email: email, apiToken: token, issueId: issueId)
                    guard !Task.isCancelled else { return }
                    devInfo = info
                }
            }

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

    /// Check if the most recent comment is an AI analysis (to prevent duplicates).
    var lastCommentIsAIAnalysis: Bool {
        guard let d = detail, let last = d.comments.last else { return false }
        return last.bodyText.contains("[AI Analysis]") || last.bodyText.contains("**Current Status**")
    }

    /// Post the AI analysis as a comment on the ticket.
    func postAnalysisAsComment(key: String, appState: AppState) async {
        guard let analysis = aiAnalysis else { return }
        // Check for duplicate
        if lastCommentIsAIAnalysis {
            actionMessage = "The most recent comment is already an AI analysis. Skipping to avoid duplicates."
            actionIsError = true
            return
        }

        let commentBody = "[AI Analysis] — Auto-generated by Boomi SRE\n\n\(analysis)"
        actionMessage = nil
        do {
            try await jiraService.addComment(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, body: commentBody)
            actionMessage = "AI analysis posted as comment"
            actionIsError = false
            await load(key: key, appState: appState)
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }

    // MARK: - AI Draft Actions

    func draftComment() async {
        guard let d = detail else { return }
        guard claudeService.isAIAvailable else {
            draftError = ClaudeError.noAuth.localizedDescription; return
        }
        isGeneratingDraft = true; draftError = nil; draftedContent = nil
        draftedContentType = "Draft Comment"
        do {
            draftedContent = try await claudeService.chat(
                messages: [("user", """
                Draft a Jira comment for this ticket providing a concise status update.

                \(ticketContextText(d))

                Requirements:
                - Summarize current status and what has been done
                - State what's next or what's blocking
                - Professional, first-person ("I" / "We"), under 150 words
                - No markdown headers (they render poorly in Jira comments)
                """)],
                systemPrompt: "You are an SRE engineer writing a Jira ticket status update. Be clear and concise." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
                maxTokens: 512
            )
        } catch { draftError = error.localizedDescription }
        isGeneratingDraft = false
    }

    func draftPRDescription() async {
        guard let d = detail else { return }
        guard claudeService.isAIAvailable else {
            draftError = ClaudeError.noAuth.localizedDescription; return
        }
        isGeneratingDraft = true; draftError = nil; draftedContent = nil
        draftedContentType = "Draft PR Description"
        do {
            draftedContent = try await claudeService.chat(
                messages: [("user", """
                Generate a pull request description for a PR implementing this Jira ticket.

                \(ticketContextText(d))

                Format:
                ## Summary
                (2–3 sentences on what this PR does)

                ## Changes
                (bullet list of key changes)

                ## Testing
                (how to verify this change)

                ## Jira Ticket
                [\(d.key)](\(d.url.absoluteString))
                """)],
                systemPrompt: "You are an SRE engineer writing a pull request description. Be technical but clear." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
                maxTokens: 768
            )
        } catch { draftError = error.localizedDescription }
        isGeneratingDraft = false
    }

    func estimateEffort() async {
        guard let d = detail else { return }
        guard claudeService.isAIAvailable else {
            draftError = ClaudeError.noAuth.localizedDescription; return
        }
        isGeneratingDraft = true; draftError = nil; draftedContent = nil
        draftedContentType = "Effort Estimate"
        do {
            draftedContent = try await claudeService.chat(
                messages: [("user", """
                Estimate story points for this Jira ticket using the Fibonacci scale (1, 2, 3, 5, 8, 13, 21).

                \(ticketContextText(d))

                Provide:
                1. **Recommended Story Points**: X points
                2. **Reasoning**: why (complexity, uncertainty, subtask count, description clarity)
                3. **Assumptions**: what is/isn't in scope
                4. **Risk Factors**: what could make this take longer

                Be concise and specific.
                """)],
                systemPrompt: "You are an experienced SRE estimating Jira story points. Use Fibonacci scale with clear reasoning." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
                maxTokens: 512
            )
        } catch { draftError = error.localizedDescription }
        isGeneratingDraft = false
    }

    func generateSubtasks() async {
        guard let d = detail else { return }
        guard claudeService.isAIAvailable else {
            draftError = ClaudeError.noAuth.localizedDescription; return
        }
        isGeneratingDraft = true; draftError = nil; draftedContent = nil
        draftedContentType = "Suggested Subtasks"
        do {
            draftedContent = try await claudeService.chat(
                messages: [("user", """
                Suggest a breakdown of this Jira ticket into 3–7 independently completable subtasks.

                \(ticketContextText(d))

                For each subtask:
                - **[Task name]**: Brief description of what's needed (estimated: X points)

                Focus on subtasks that are individually verifiable and parallelisable where possible.
                """)],
                systemPrompt: "You are a technical lead breaking down Jira tickets for an SRE team. Be specific and practical." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
                maxTokens: 768
            )
        } catch { draftError = error.localizedDescription }
        isGeneratingDraft = false
    }

    func askFollowUp(question: String) async {
        guard let d = detail, !question.isEmpty else { return }
        guard claudeService.isAIAvailable else {
            draftError = ClaudeError.noAuth.localizedDescription; return
        }
        followUpQuestion = ""
        isAnsweringFollowUp = true

        // Build multi-turn messages: ticket context → analysis → conversation history → new question
        var messages: [(role: String, content: String)] = [
            ("user", "Ticket context:\n\(ticketContextText(d))\n\nInitial analysis:\n\(aiAnalysis ?? "(not yet analyzed)")"),
            ("assistant", "I've reviewed the ticket. What would you like to know?")
        ]
        for entry in followUpHistory {
            messages.append(("user", entry.question))
            messages.append(("assistant", entry.answer))
        }
        messages.append(("user", question))

        do {
            let answer = try await claudeService.chat(
                messages: messages,
                systemPrompt: "You are an SRE assistant with full context of a Jira ticket. Answer questions concisely and specifically." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
                maxTokens: 1024
            )
            followUpHistory.append((question: question, answer: answer))
        } catch { draftError = error.localizedDescription }
        isAnsweringFollowUp = false
    }

    /// Build plain-text ticket context for AI prompts.
    func ticketContextText(_ d: TicketDetail) -> String {
        var parts = [
            "Ticket: \(d.key) — \(d.summary)",
            "Status: \(d.status) | Priority: \(d.priority) | Type: \(d.issueType)",
            "Assignee: \(d.assignee) | Reporter: \(d.reporter)"
        ]
        if !d.dueDate.isEmpty { parts.append("Due: \(d.dueDate)") }
        if let sprint = d.sprint { parts.append("Sprint: \(sprint.name)") }
        if !d.labels.isEmpty { parts.append("Labels: \(d.labels.joined(separator: ", "))") }
        if !d.parentKey.isEmpty { parts.append("Parent: \(d.parentKey) — \(d.parentSummary)") }
        if !d.description.isEmpty { parts.append("\nDescription:\n\(d.description.prefix(2000))") }
        if !d.subtasks.isEmpty {
            parts.append("\nSubtasks (\(d.subtasks.count)):")
            for st in d.subtasks { parts.append("  • \(st.key): \(st.summary) [\(st.status)]") }
        }
        if !d.comments.isEmpty {
            parts.append("\nRecent Comments (last 3):")
            for c in d.comments.suffix(3) {
                parts.append("  [\(c.created)] \(c.authorName): \(c.bodyText.prefix(300))")
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Ask Claude to analyze the ticket and recommend next steps.
    func analyzeWithAI() async {
        guard let d = detail else { return }
        guard claudeService.isAIAvailable else {
            aiError = ClaudeError.noAuth.localizedDescription
            return
        }

        isAnalyzing = true
        aiError = nil
        aiAnalysis = nil

        do {
            let analysis = try await claudeService.analyzeTicket(ticketDetail: d, devInfo: devInfo)
            aiAnalysis = analysis
            isAnalyzing = false
        } catch {
            aiError = error.localizedDescription
            isAnalyzing = false
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
            let id = c["id"] as? String ?? UUID().uuidString
            let author = (c["author"] as? [String: Any])?["displayName"] as? String ?? "Unknown"
            let avatarURL = ((c["author"] as? [String: Any])?["avatarUrls"] as? [String: Any])?["24x24"] as? String
            let created = (c["created"] as? String ?? "").prefix(16).replacingOccurrences(of: "T", with: " ")
            let body = Self.extractMarkdownFromADF(c["body"] as? [String: Any])
            return JiraComment(id: id, authorName: author, authorAvatarURL: avatarURL, created: String(created), bodyText: body, bodyMarkdown: body)
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
            ?? URL(string: "https://boomii.atlassian.net/browse/\(key)")
            ?? URL(string: "https://boomii.atlassian.net")!

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
            description: Self.extractMarkdownFromADF(f["description"] as? [String: Any]),
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

    static func extractMarkdownFromADF(_ node: [String: Any]?) -> String {
        guard let node else { return "" }
        let nodeType = node["type"] as? String ?? ""

        if nodeType == "text" {
            var text = node["text"] as? String ?? ""
            if let marks = node["marks"] as? [[String: Any]] {
                for mark in marks {
                    switch mark["type"] as? String ?? "" {
                    case "strong": text = "**\(text)**"
                    case "em": text = "*\(text)*"
                    case "code": text = "`\(text)`"
                    case "strike": text = "~~\(text)~~"
                    case "link":
                        if let href = (mark["attrs"] as? [String: Any])?["href"] as? String {
                            text = "[\(text)](\(href))"
                        }
                    default: break
                    }
                }
            }
            return text
        }

        if nodeType == "hardBreak" { return "\n" }
        if nodeType == "rule" { return "\n---\n\n" }

        let children = node["content"] as? [[String: Any]] ?? []
        let childTexts = children.map { extractMarkdownFromADF($0) }

        switch nodeType {
        case "doc":
            return childTexts.joined()
        case "paragraph":
            return childTexts.joined() + "\n\n"
        case "heading":
            let level = (node["attrs"] as? [String: Any])?["level"] as? Int ?? 1
            let prefix = String(repeating: "#", count: level)
            return "\(prefix) \(childTexts.joined())\n\n"
        case "bulletList", "orderedList":
            return childTexts.joined()
        case "listItem":
            let inner = childTexts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(inner)\n"
        case "codeBlock":
            let lang = (node["attrs"] as? [String: Any])?["language"] as? String ?? ""
            return "```\(lang)\n\(childTexts.joined())```\n\n"
        case "blockquote":
            let lines = childTexts.joined().split(separator: "\n", omittingEmptySubsequences: false)
            return lines.map { "> \($0)" }.joined(separator: "\n") + "\n\n"
        case "table":
            return convertADFTable(children)
        case "tableRow":
            return "| " + childTexts.joined(separator: " | ") + " |\n"
        case "tableHeader", "tableCell":
            return childTexts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        case "mediaSingle", "media":
            if let url = (node["attrs"] as? [String: Any])?["url"] as? String {
                return "![](\(url))\n\n"
            }
            return ""
        case "emoji":
            return (node["attrs"] as? [String: Any])?["shortName"] as? String ?? ""
        case "mention":
            if let text = (node["attrs"] as? [String: Any])?["text"] as? String {
                return "**\(text)**"
            }
            return ""
        default:
            return childTexts.joined()
        }
    }

    private static func convertADFTable(_ rows: [[String: Any]]) -> String {
        guard !rows.isEmpty else { return "" }
        var result = ""
        for (i, row) in rows.enumerated() {
            let cells = row["content"] as? [[String: Any]] ?? []
            let cellTexts = cells.map { extractMarkdownFromADF($0) }
            result += "| " + cellTexts.joined(separator: " | ") + " |\n"
            if i == 0 {
                result += "|" + cellTexts.map { _ in " --- " }.joined(separator: "|") + "|\n"
            }
        }
        return result + "\n"
    }
}

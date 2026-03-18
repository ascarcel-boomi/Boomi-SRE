import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published State

    @Published var messages: [CopilotMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isGatheringContext: Bool = false
    @Published var error: String?
    @Published var activeContextTypes: Set<ContextType> = [.jiraTickets]
    @Published var contextLabels: [ContextType: String] = [:]
    /// Non-nil when the loop is paused waiting for the user to confirm a Jira comment.
    @Published var pendingConfirmation: PendingCommentConfirmation?

    // MARK: - Private State

    private let claudeService    = ClaudeService()
    private let jiraService      = JiraService()
    private let googleService    = GoogleService()
    private let costService      = AWSCostService()
    private let grafanaService   = GrafanaService()
    private let jenkinsService   = JenkinsService()
    private let confluenceService = ConfluenceService()

    /// Conversation history in Anthropic API format — NOT persisted across restarts.
    /// Content values may be String or [[String: Any]] (tool-use content blocks).
    private var apiHistory: [[String: Any]] = []
    /// Snapshot of apiHistory at the point the loop was suspended for confirmation.
    private var pausedApiHistory: [[String: Any]] = []
    /// Session cache: ticket key → formatted text. Cleared on clearHistory().
    private var ticketCache: [String: String] = [:]

    private let historyURL: URL

    // MARK: - Init

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.historyURL = home.appendingPathComponent(".boomi_sre_chat_history.json")
        loadHistory()
    }

    // MARK: - Send (entry point)

    func send(appState: AppState) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedText = text
        guard !text.isEmpty else { return }

        guard claudeService.isAIAvailable else {
            error = "No AI backend found. Install Claude Code (claude CLI) for Enterprise license, or set ANTHROPIC_API_KEY."
            return
        }

        inputText = ""
        error = nil

        // Gather context from selected services (skip if auto-context is disabled)
        isGatheringContext = appState.autoContextEnabled
        let (contextText, sources) = appState.autoContextEnabled
            ? await gatherContext(appState: appState)
            : ("", [ContextSource]())
        isGatheringContext = false

        // Build the API-format user content (with context preamble)
        let screenCtx = appState.currentScreenContext
        let userApiContent: String
        if !contextText.isEmpty {
            var preamble = "=== LIVE CONTEXT ===\n\(contextText)\n=== END CONTEXT ==="
            if !screenCtx.isEmpty { preamble += "\n\nCurrent screen: \(screenCtx)." }
            userApiContent = preamble + "\n\n\(text)"
        } else if !screenCtx.isEmpty {
            userApiContent = "Current screen: \(screenCtx).\n\n\(text)"
        } else {
            userApiContent = text
        }

        // Add display message (shows only the user's actual question)
        let userMsg = CopilotMessage(
            role: .user,
            content: text,
            apiContent: contextText.isEmpty ? nil : userApiContent,
            contextSources: sources
        )
        messages.append(userMsg)

        // Add to API history
        apiHistory.append(["role": "user", "content": userApiContent])

        // Run the agentic tool loop
        await runToolLoop(appState: appState)
        saveHistory()
        if self.error == nil {
            ProductivityTracker.shared.log(.aiCopilotQuery, detail: String(savedText.prefix(60)), source: "AI Copilot")
        }
    }

    // MARK: - Agentic Tool Loop

    private func runToolLoop(appState: AppState) async {
        isLoading = true

        let baseURL   = appState.jiraBaseURL
        let email     = appState.jiraEmail
        let token     = appState.jiraAPIToken
        var sysPrompt = systemPrompt(userEmail: email, depth: appState.analysisDepth, profile: appState.userProfile)
        // Inject product context if a specific product is selected
        if let product = appState.selectedProduct, product.id != "all" {
            var productCtx = "\n\nCURRENT PRODUCT CONTEXT: \(product.name)"
            if !product.productDescription.isEmpty { productCtx += "\nDescription: \(product.productDescription)" }
            if !product.architectureNotes.isEmpty { productCtx += "\nArchitecture: \(product.architectureNotes)" }
            if !product.commonAlertPatterns.isEmpty {
                productCtx += "\nCommon alert patterns:\n" + product.commonAlertPatterns.map { "- \($0)" }.joined(separator: "\n")
            }
            if !product.escalationContacts.isEmpty {
                productCtx += "\nEscalation contacts:\n" + product.escalationContacts.map { "- \($0.name) (\($0.role)) — \($0.slackHandle)" }.joined(separator: "\n")
            }
            if !product.keyRunbooks.isEmpty {
                productCtx += "\nKey runbooks: " + product.keyRunbooks.joined(separator: ", ")
            }
            productCtx += "\n\nWhen answering, prioritize information relevant to \(product.shortName). Reference specific runbooks and alert patterns when applicable."
            sysPrompt += productCtx
        }
        let maxTok    = appState.chatMaxTokens
        let modelOvr: String? = appState.claudeModel == "claude-sonnet-4-6" ? nil : appState.claudeModel

        // CLI fallback: no tool-use support, so pre-fetch tickets and use regular chat
        if case .claudeCLI = claudeService.discoverAuthMethod() {
            await runCLIFallback(
                appState: appState, sysPrompt: sysPrompt, maxTokens: maxTok, modelOverride: modelOvr
            )
            return
        }

        // Safety cap: prevent runaway loops
        for _ in 0..<8 {
            do {
                let response = try await claudeService.chatWithTools(
                    apiHistory: apiHistory,
                    tools: JiraTools.definitions,
                    systemPrompt: sysPrompt,
                    maxTokens: maxTok
                )

                switch response {

                case .finalText(let text):
                    messages.append(CopilotMessage(
                        role: .assistant,
                        content: text.isEmpty ? "(No response)" : text
                    ))
                    isLoading = false
                    return

                case .toolUse(let textBefore, let tools, let rawBlocks):
                    // Show any text Claude said before calling tools
                    if let text = textBefore, !text.isEmpty {
                        messages.append(CopilotMessage(role: .assistant, content: text))
                    }

                    // Append the assistant turn (with raw content blocks) to history
                    apiHistory.append(["role": "assistant", "content": rawBlocks])

                    // Process tools: execute synchronous ones, note any confirmation-required one
                    var toolResultBlocks: [[String: Any]] = []
                    var confirmTool: ClaudeToolUse?

                    for tool in tools {
                        switch tool.name {
                        case "get_jira_ticket":
                            let key = tool.input["ticket_key"] as? String ?? ""
                            let result = await executeGetTicket(
                                key: key, baseURL: baseURL, email: email, token: token
                            )
                            toolResultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": tool.id,
                                "content": result
                            ])
                        case "get_grafana_alerts":
                            let result = await executeGetAlerts(appState: appState)
                            messages.append(CopilotMessage(role: .system, content: "",
                                toolEvent: ToolCallEvent(eventType: .fetchedAlerts, ticketKey: "Grafana", succeeded: true, detail: nil)))
                            toolResultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": tool.id,
                                "content": result
                            ])
                        case "get_jenkins_builds":
                            let jobName = tool.input["job_name"] as? String
                            let result = await executeGetBuilds(appState: appState, jobName: jobName)
                            messages.append(CopilotMessage(role: .system, content: "",
                                toolEvent: ToolCallEvent(eventType: .fetchedBuilds, ticketKey: "Jenkins", succeeded: true, detail: nil)))
                            toolResultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": tool.id,
                                "content": result
                            ])
                        case "search_confluence":
                            let query = tool.input["query"] as? String ?? ""
                            let result = await executeSearchConfluence(appState: appState, query: query)
                            messages.append(CopilotMessage(role: .system, content: "",
                                toolEvent: ToolCallEvent(eventType: .searchedDocs, ticketKey: query, succeeded: true, detail: nil)))
                            toolResultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": tool.id,
                                "content": result
                            ])
                        case "post_jira_comment":
                            confirmTool = tool
                        default:
                            toolResultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": tool.id,
                                "content": "Unknown tool: \(tool.name)"
                            ])
                        }
                    }

                    if let confirmTool {
                        // Flush any synchronous results first, then pause for confirmation
                        if !toolResultBlocks.isEmpty {
                            apiHistory.append(["role": "user", "content": toolResultBlocks])
                        }
                        let key  = confirmTool.input["ticket_key"]    as? String ?? ""
                        let body = confirmTool.input["comment_body"] as? String ?? ""
                        isLoading = false
                        pauseForConfirmation(
                            toolUseId: confirmTool.id, ticketKey: key, commentMarkdown: body
                        )
                        return  // Loop resumes in confirmPostComment() or cancelPostComment()
                    } else {
                        // All sync — continue the loop
                        apiHistory.append(["role": "user", "content": toolResultBlocks])
                    }
                }

            } catch {
                self.error = error.localizedDescription
                isLoading = false
                return
            }
        }

        self.error = "Tool loop exceeded maximum iterations."
        isLoading = false
    }

    // MARK: - CLI Fallback (Enterprise license — no tool-use API)

    /// When using `claude -p` (Enterprise license) we cannot pass custom tool definitions.
    /// Instead, pre-fetch any Jira tickets referenced in the conversation, include them as
    /// context, and do a single `chat()` call. The user gets a working Copilot — they just
    /// lose the dynamic tool-calling loop.
    private func runCLIFallback(
        appState: AppState,
        sysPrompt: String,
        maxTokens: Int,
        modelOverride: String?
    ) async {
        let baseURL = appState.jiraBaseURL
        let email   = appState.jiraEmail
        let token   = appState.jiraAPIToken

        // Extract ticket keys from the full conversation
        var mentionedKeys = Set<String>()
        let regex = try? NSRegularExpression(pattern: "[A-Z][A-Z0-9]+-\\d+")
        for msg in apiHistory {
            if let content = msg["content"] as? String {
                let range = NSRange(content.startIndex..., in: content)
                for match in regex?.matches(in: content, range: range) ?? [] {
                    if let r = Range(match.range, in: content) {
                        mentionedKeys.insert(String(content[r]).uppercased())
                    }
                }
            }
        }

        // Pre-fetch any referenced tickets not already in context
        var ticketContext = ""
        for key in mentionedKeys.sorted() {
            let detail = await executeGetTicket(
                key: key, baseURL: baseURL, email: email, token: token
            )
            if !detail.starts(with: "Failed") {
                ticketContext += "\n\n--- Ticket \(key) ---\n\(detail)"
            }
        }

        // Build messages for the chat() call
        var chatMessages: [(role: String, content: String)] = []
        for msg in apiHistory {
            guard let role = msg["role"] as? String,
                  let content = msg["content"] as? String else { continue }
            chatMessages.append((role: role, content: content))
        }

        // Inject pre-fetched ticket data into the system prompt
        var enrichedSystem = sysPrompt
        if !ticketContext.isEmpty {
            enrichedSystem += "\n\n=== PRE-FETCHED TICKET DATA ===\(ticketContext)\n=== END TICKET DATA ==="
        }
        enrichedSystem += """

        \nNote: You are running via the Claude CLI backend (Enterprise license). You cannot call \
        tools dynamically, but ticket data has been pre-fetched and included above. If the user \
        asks you to post a Jira comment, draft the comment in your response and let them know \
        they can copy it to Jira manually, or switch to an API key backend for automatic posting.
        """

        do {
            let response = try await claudeService.chat(
                messages: chatMessages,
                systemPrompt: enrichedSystem,
                maxTokens: maxTokens,
                modelOverride: modelOverride
            )

            // Append to API history so future turns have context
            apiHistory.append(["role": "assistant", "content": response])

            messages.append(CopilotMessage(
                role: .assistant,
                content: response.isEmpty ? "(No response)" : response
            ))
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Tool Execution: get_jira_ticket

    private func executeGetTicket(
        key: String, baseURL: String, email: String, token: String
    ) async -> String {
        // Cache hit
        if let cached = ticketCache[key.uppercased()] {
            return cached
        }

        // Insert inline fetch indicator
        let msgId = UUID()
        messages.append(CopilotMessage(
            id: msgId,
            role: .system,
            content: "",
            toolEvent: ToolCallEvent(eventType: .fetchedTicket, ticketKey: key, succeeded: true, detail: nil)
        ))

        do {
            let (_, raw) = try await jiraService.getIssue(
                baseURL: baseURL, email: email, apiToken: token, key: key.uppercased()
            )
            let text = formatTicketRaw(key: key.uppercased(), raw: raw, baseURL: baseURL)
            ticketCache[key.uppercased()] = text
            return text
        } catch {
            // Update indicator to show failure
            if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                messages[idx].toolEvent = ToolCallEvent(
                    eventType: .fetchedTicket,
                    ticketKey: key,
                    succeeded: false,
                    detail: error.localizedDescription
                )
            }
            return "Failed to fetch ticket \(key): \(error.localizedDescription)"
        }
    }

    // MARK: - Confirmation Flow: post_jira_comment

    private func pauseForConfirmation(toolUseId: String, ticketKey: String, commentMarkdown: String) {
        pausedApiHistory = apiHistory
        let confirmation = PendingCommentConfirmation(
            toolUseId: toolUseId,
            ticketKey: ticketKey,
            commentMarkdown: commentMarkdown
        )
        pendingConfirmation = confirmation
        messages.append(CopilotMessage(
            role: .system,
            content: "",
            pendingAction: confirmation
        ))
    }

    func confirmPostComment(appState: AppState) async {
        guard let pending = pendingConfirmation else { return }

        // Remove the confirmation card
        messages.removeAll { $0.pendingAction?.toolUseId == pending.toolUseId }
        pendingConfirmation = nil
        isLoading = true

        do {
            let adf = MarkdownToADF.convert(pending.commentMarkdown)
            try await jiraService.addCommentADF(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                key: pending.ticketKey,
                adfDoc: adf
            )

            // Success indicator
            let deepLink = "https://boomii.atlassian.net/browse/\(pending.ticketKey)"
            messages.append(CopilotMessage(
                role: .system,
                content: "",
                toolEvent: ToolCallEvent(
                    eventType: .postedComment,
                    ticketKey: pending.ticketKey,
                    succeeded: true,
                    detail: deepLink
                )
            ))

            // Resume loop with success result
            apiHistory = pausedApiHistory
            apiHistory.append(["role": "user", "content": [[
                "type": "tool_result",
                "tool_use_id": pending.toolUseId,
                "content": "Comment posted successfully to \(pending.ticketKey). View at \(deepLink)"
            ]]])
            await runToolLoop(appState: appState)

        } catch {
            // Failure indicator
            messages.append(CopilotMessage(
                role: .system,
                content: "",
                toolEvent: ToolCallEvent(
                    eventType: .commentFailed,
                    ticketKey: pending.ticketKey,
                    succeeded: false,
                    detail: error.localizedDescription
                )
            ))

            // Re-surface confirmation card so user can retry
            pendingConfirmation = pending
            messages.append(CopilotMessage(
                role: .system,
                content: "",
                pendingAction: pending
            ))
            isLoading = false
        }

        saveHistory()
    }

    func cancelPostComment(appState: AppState) async {
        guard let pending = pendingConfirmation else { return }

        messages.removeAll { $0.pendingAction?.toolUseId == pending.toolUseId }
        pendingConfirmation = nil

        // Cancelled indicator
        messages.append(CopilotMessage(
            role: .system,
            content: "",
            toolEvent: ToolCallEvent(
                eventType: .commentCancelled,
                ticketKey: pending.ticketKey,
                succeeded: false,
                detail: nil
            )
        ))

        // Resume loop with cancellation result
        apiHistory = pausedApiHistory
        apiHistory.append(["role": "user", "content": [[
            "type": "tool_result",
            "tool_use_id": pending.toolUseId,
            "content": "User cancelled the comment post. Do not attempt to post again unless explicitly asked."
        ]]])
        await runToolLoop(appState: appState)
        saveHistory()
    }

    // MARK: - Quick Actions

    func executeQuickAction(_ action: QuickAction) {
        if !action.contextTypes.isEmpty {
            activeContextTypes = action.contextTypes
        }
        inputText = action.prompt
    }

    // MARK: - Context Gathering

    private func gatherContext(appState: AppState) async -> (text: String, sources: [ContextSource]) {
        var parts: [String] = []
        var sources: [ContextSource] = []

        let types          = activeContextTypes
        let baseURL        = appState.jiraBaseURL
        let email          = appState.jiraEmail
        let token          = appState.jiraAPIToken
        let jiraConfigured = appState.isJiraConfigured
        let googleCreds    = appState.googleCredentials
        let awsProfile     = appState.awsSSOProfile

        let activeProjectKeys = appState.activeProductIds.isEmpty ? [String]() : appState.activeJiraProjectKeys

        if types.contains(.jiraTickets) && jiraConfigured {
            if let (text, source) = await fetchJiraContext(
                baseURL: baseURL, email: email, token: token, activeProjectKeys: activeProjectKeys
            ) {
                parts.append(text)
                sources.append(source)
                contextLabels[.jiraTickets] = source.label
            }
        }

        if types.contains(.calendar), let creds = googleCreds {
            if let (text, source) = await fetchCalendarContext(credentials: creds) {
                parts.append(text)
                sources.append(source)
                contextLabels[.calendar] = source.label
            }
        }

        if types.contains(.email), let creds = googleCreds {
            if let (text, source) = await fetchEmailContext(credentials: creds) {
                parts.append(text)
                sources.append(source)
                contextLabels[.email] = source.label
            }
        }

        if types.contains(.grafanaAlerts) && !appState.grafanaURL.isEmpty {
            if let (text, source) = await fetchGrafanaContext(appState: appState) {
                parts.append(text)
                sources.append(source)
                contextLabels[.grafanaAlerts] = source.label
            }
        }

        if types.contains(.jenkinsBuilds) && !appState.jenkinsServers.isEmpty {
            if let (text, source) = await fetchJenkinsContext(appState: appState) {
                parts.append(text)
                sources.append(source)
                contextLabels[.jenkinsBuilds] = source.label
            }
        }

        if types.contains(.awsCosts) && !awsProfile.isEmpty {
            if let (text, source) = await fetchAWSContext(profile: awsProfile) {
                parts.append(text)
                sources.append(source)
                contextLabels[.awsCosts] = source.label
            }
        }

        return (parts.joined(separator: "\n\n"), sources)
    }

    private func fetchJiraContext(
        baseURL: String, email: String, token: String, activeProjectKeys: [String] = []
    ) async -> (String, ContextSource)? {
        do {
            var jql = "assignee = currentUser() AND statusCategory NOT IN (Done)"
            if !activeProjectKeys.isEmpty {
                let filter = activeProjectKeys.map { "\"\($0)\"" }.joined(separator: ", ")
                jql += " AND project IN (\(filter))"
            }
            jql += " ORDER BY priority ASC, updated DESC"
            let result = try await jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql,
                fields: ["summary", "status", "priority", "issuetype", "duedate", "labels", "updated"],
                maxResults: 15
            )
            guard !result.issues.isEmpty else { return nil }
            var lines = ["My open Jira tickets (\(result.issues.count)):"]
            for issue in result.issues {
                let status   = issue.fields.status?.name   ?? "?"
                let priority = issue.fields.priority?.name ?? "?"
                let type_    = issue.fields.issuetype?.name ?? ""
                var line = "  • \(issue.key) [\(priority)] [\(status)] \(type_): \(issue.fields.summary ?? "")"
                if let due = issue.fields.duedate, !due.isEmpty { line += " (due \(due))" }
                lines.append(line)
            }
            let text = lines.joined(separator: "\n")
            return (text, ContextSource(type: .jiraTickets, label: "\(result.issues.count) tickets", summary: text))
        } catch { return nil }
    }

    private func fetchCalendarContext(credentials: GoogleCredentials) async -> (String, ContextSource)? {
        do {
            let events = try await googleService.listEvents(credentials: credentials, maxResults: 10, daysAhead: 1)
            guard !events.isEmpty else { return nil }
            var lines = ["Today's calendar (\(events.count) events):"]
            for event in events.prefix(10) {
                let time = String(event.startDateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
                let allDay = event.isAllDay ? " (all day)" : ""
                lines.append("  • \(time)\(allDay): \(event.summary)")
            }
            let text = lines.joined(separator: "\n")
            return (text, ContextSource(type: .calendar, label: "\(events.count) events", summary: text))
        } catch { return nil }
    }

    private func fetchEmailContext(credentials: GoogleCredentials) async -> (String, ContextSource)? {
        do {
            let msgs = try await googleService.listMessages(credentials: credentials, query: "is:unread", maxResults: 15)
            guard !msgs.isEmpty else { return nil }
            var lines = ["Recent unread emails (\(msgs.count)):"]
            for msg in msgs.prefix(15) { lines.append("  • From: \(msg.from) — \(msg.subject)") }
            let text = lines.joined(separator: "\n")
            return (text, ContextSource(type: .email, label: "\(msgs.count) unread", summary: text))
        } catch { return nil }
    }

    private func fetchAWSContext(profile: String) async -> (String, ContextSource)? {
        do {
            let cal = Calendar.current
            let now = Date()
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let nextMonth  = cal.date(byAdding: .month, value: 1, to: monthStart)!
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let result = try await costService.getCostAndUsage(
                profile: profile,
                startDate: df.string(from: monthStart),
                endDate:   df.string(from: nextMonth),
                granularity: .monthly, groupBy: .service
            )
            let top   = result.aggregated.prefix(10)
            let total = result.totalCost
            var lines = ["AWS costs this month (top services, total $\(String(format: "%.2f", total)):"]
            for item in top { lines.append("  • \(item.name): $\(String(format: "%.2f", item.amount))") }
            let text = lines.joined(separator: "\n")
            return (text, ContextSource(type: .awsCosts, label: "$\(String(format: "%.0f", total))", summary: text))
        } catch { return nil }
    }

    private func fetchGrafanaContext(appState: AppState) async -> (String, ContextSource)? {
        do {
            let alerts = try await grafanaService.listAlertRules(
                baseURL: appState.grafanaURL, token: appState.grafanaToken)
            var firing = alerts.filter { $0.state == "alerting" || $0.state == "pending" }
            // Filter by product's grafana tags when a product is selected
            if !appState.activeProductIds.isEmpty {
                let tags = appState.products.filter { appState.activeProductIds.contains($0.id) }
                    .flatMap { $0.grafanaDashboardTags }
                if !tags.isEmpty {
                    firing = firing.filter { rule in
                        tags.contains { tag in
                            rule.labels.keys.contains { $0.lowercased() == tag.lowercased() } ||
                            rule.labels.values.contains { $0.lowercased() == tag.lowercased() }
                        }
                    }
                }
            }
            guard !firing.isEmpty else {
                return ("No active Grafana alerts.", ContextSource(type: .grafanaAlerts, label: "0 alerts", summary: "No active alerts"))
            }
            var lines = ["Active Grafana alerts (\(firing.count)):"]
            for alert in firing.prefix(20) {
                let state = alert.state.uppercased()
                lines.append("  • [\(state)] \(alert.title)")
            }
            let text = lines.joined(separator: "\n")
            return (text, ContextSource(type: .grafanaAlerts, label: "\(firing.count) firing", summary: text))
        } catch { return nil }
    }

    private func fetchJenkinsContext(appState: AppState) async -> (String, ContextSource)? {
        let activeJobs = appState.activeJenkinsJobs
        var allLines: [String] = []
        var failCount = 0
        for server in appState.jenkinsServers {
            guard !server.url.isEmpty else { continue }
            do {
                var jobs = try await jenkinsService.listJobs(
                    baseURL: server.url, username: server.username, token: server.token)
                if !activeJobs.isEmpty {
                    jobs = jobs.filter { activeJobs.contains($0.name) }
                }
                let failing = jobs.filter { $0.color == "red" || $0.color == "yellow" || $0.color.hasSuffix("_anime") }
                for job in failing.prefix(10) {
                    allLines.append("  • [\(job.statusLabel)] \(server.name)/\(job.name)")
                    failCount += 1
                }
            } catch { continue }
        }
        guard !allLines.isEmpty else {
            return ("All Jenkins builds healthy.", ContextSource(type: .jenkinsBuilds, label: "all green", summary: "All Jenkins builds healthy"))
        }
        let header = "Jenkins builds needing attention (\(failCount)):"
        let text = ([header] + allLines).joined(separator: "\n")
        return (text, ContextSource(type: .jenkinsBuilds, label: "\(failCount) failing", summary: text))
    }

    // MARK: - Tool Execution: get_grafana_alerts

    private func executeGetAlerts(appState: AppState) async -> String {
        do {
            let alerts = try await grafanaService.listAlertRules(
                baseURL: appState.grafanaURL, token: appState.grafanaToken)
            var firing = alerts.filter { $0.state == "alerting" || $0.state == "pending" }
            // Filter by product's grafana tags when a product is selected
            if !appState.activeProductIds.isEmpty {
                let tags = appState.products.filter { appState.activeProductIds.contains($0.id) }
                    .flatMap { $0.grafanaDashboardTags }
                if !tags.isEmpty {
                    firing = firing.filter { rule in
                        tags.contains { tag in
                            rule.labels.keys.contains { $0.lowercased() == tag.lowercased() } ||
                            rule.labels.values.contains { $0.lowercased() == tag.lowercased() }
                        }
                    }
                }
            }
            if firing.isEmpty { return "No active Grafana alerts." }
            var lines = ["Active alerts (\(firing.count)):"]
            for alert in firing {
                lines.append("[\(alert.state.uppercased())] \(alert.title)")
                if !alert.summary.isEmpty { lines.append("  Summary: \(alert.summary)") }
                if !alert.labels.isEmpty {
                    lines.append("  Labels: \(alert.labels.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
                }
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Failed to fetch alerts: \(error.localizedDescription)"
        }
    }

    // MARK: - Tool Execution: get_jenkins_builds

    private func executeGetBuilds(appState: AppState, jobName: String?) async -> String {
        let activeJobs = appState.activeJenkinsJobs
        var allLines: [String] = []
        for server in appState.jenkinsServers {
            guard !server.url.isEmpty else { continue }
            do {
                var jobs = try await jenkinsService.listJobs(
                    baseURL: server.url, username: server.username, token: server.token)
                if !activeJobs.isEmpty {
                    jobs = jobs.filter { activeJobs.contains($0.name) }
                }
                let targetJobs: [JenkinsJob]
                if let name = jobName, !name.isEmpty {
                    targetJobs = jobs.filter { $0.name.localizedCaseInsensitiveContains(name) }
                } else {
                    targetJobs = jobs
                }
                for job in targetJobs.prefix(15) {
                    let builds = try await jenkinsService.getBuildHistory(
                        baseURL: server.url, jobName: job.name,
                        username: server.username, token: server.token, limit: 3)
                    if !builds.isEmpty {
                        allLines.append("\(server.name)/\(job.name) [\(job.statusLabel)]:")
                        for build in builds {
                            let result = build.displayResult
                            allLines.append("  #\(build.number) \(result) (\(build.formattedDuration)) — \(Formatters.shortDateTime.string(from: build.date))")
                        }
                    }
                }
            } catch {
                allLines.append("\(server.name): error — \(error.localizedDescription)")
            }
        }
        return allLines.isEmpty ? "No Jenkins builds found." : allLines.joined(separator: "\n")
    }

    // MARK: - Tool Execution: search_confluence

    private func executeSearchConfluence(appState: AppState, query: String) async -> String {
        do {
            let pages = try await confluenceService.searchPages(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, query: query, limit: 8)
            if pages.isEmpty { return "No Confluence pages found for \"\(query)\"." }
            var lines = ["Confluence results for \"\(query)\" (\(pages.count)):"]
            for page in pages {
                lines.append("  • \(page.title) [\(page.spaceKey)]")
                lines.append("    URL: \(page.url)")
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Confluence search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - System Prompt

    private func systemPrompt(userEmail: String, depth: String = "standard", profile: UserProfile = .empty) -> String {
        let depthModifier: String
        switch depth {
        case "brief":    depthModifier = "\n\nIMPORTANT: Keep all responses concise and under 200 words. Focus only on the most critical points."
        case "thorough": depthModifier = "\n\nIMPORTANT: Be comprehensive and thorough. Include detailed analysis, edge cases, and multiple perspectives."
        default:         depthModifier = ""
        }
        let profileHint = buildProfileContext(profile: profile)
        return buildSystemPrompt(userEmail: userEmail) + depthModifier + profileHint
    }

    private func buildProfileContext(profile: UserProfile) -> String {
        guard !profile.displayName.isEmpty || !profile.team.isEmpty else { return "" }
        var parts: [String] = []
        if !profile.displayName.isEmpty {
            parts.append("You are assisting \(profile.displayName)")
            if !profile.role.rawValue.isEmpty {
                parts[parts.count - 1] += ", a \(profile.role.displayName)"
            }
            if !profile.team.isEmpty {
                parts[parts.count - 1] += " on the \(profile.team) team"
            }
            parts[parts.count - 1] += "."
        }
        parts.append(profile.experienceLevel.analysisDepthHint)
        return "\n\n" + parts.joined(separator: " ")
    }

    private func buildSystemPrompt(userEmail: String) -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
        let now = df.string(from: Date())
        return """
        You are an AI Copilot embedded in Boomi SRE — a native macOS app for Boomi's APIM SRE team. \
        Today is \(now). The user's email is \(userEmail.isEmpty ? "unknown" : userEmail).

        You have access to real-time SRE context that may be injected at the start of user messages \
        under a "=== LIVE CONTEXT ===" block. You have tools to pull data from multiple services:

        **get_jira_ticket(ticket_key)** — Fetch full Jira ticket details. Use automatically when a \
        ticket key is mentioned (e.g. CAMSRE-123). Always fetch before drafting content about a ticket.

        **post_jira_comment(ticket_key, comment_body)** — Post a markdown comment to a Jira ticket. \
        A confirmation dialog is shown before posting.

        **get_grafana_alerts()** — Fetch currently firing/pending Grafana alert rules. Use when \
        troubleshooting, investigating an incident, or when the user asks about alerts or system health.

        **get_jenkins_builds(job_name?)** — Fetch recent build results across Jenkins servers. Use when \
        checking if a recent deploy caused an issue. Optional job_name filter.

        **search_confluence(query)** — Search Confluence for runbooks, SOPs, and docs. Use when \
        the user needs a procedure or when you want to reference existing documentation.

        **Cross-service troubleshooting:** When investigating an issue, proactively use multiple tools \
        to build the full picture. For example: fetch the ticket, check for related alerts, look at \
        recent deploys, and search for relevant runbooks — then synthesize everything into a coherent \
        analysis with root cause, blast radius, and next steps.

        Guidelines:
        - Be specific and actionable — reference actual ticket keys, alert names, job names, dollar amounts
        - Format responses in markdown (headings, bullet points, code blocks where relevant)
        - When troubleshooting, always cross-reference: alerts ↔ deploys ↔ tickets ↔ runbooks
        - Jira links: [KEY](https://boomii.atlassian.net/browse/KEY)
        - When context is missing, state what you'd need and suggest enabling the relevant context chip
        """
    }

    // MARK: - Ticket Formatting (used by get_jira_ticket tool)

    private func formatTicketRaw(key: String, raw: [String: Any], baseURL: String) -> String {
        let f = raw["fields"] as? [String: Any] ?? [:]
        var lines: [String] = ["Ticket: \(key)"]
        lines.append("URL: https://boomii.atlassian.net/browse/\(key)")
        lines.append("Summary: \(f["summary"] as? String ?? "?")")
        let status   = (f["status"]    as? [String: Any])?["name"] as? String ?? "?"
        let priority = (f["priority"]  as? [String: Any])?["name"] as? String ?? "?"
        let issueType = (f["issuetype"] as? [String: Any])?["name"] as? String ?? "?"
        lines.append("Status: \(status)")
        lines.append("Priority: \(priority)")
        lines.append("Type: \(issueType)")
        let assignee = (f["assignee"] as? [String: Any])?["displayName"] as? String ?? "Unassigned"
        let reporter = (f["reporter"] as? [String: Any])?["displayName"] as? String ?? "?"
        lines.append("Assignee: \(assignee)")
        lines.append("Reporter: \(reporter)")
        if let due = f["duedate"] as? String, !due.isEmpty { lines.append("Due Date: \(due)") }

        if let descNode = f["description"] as? [String: Any] {
            let text = extractADFText(descNode)
            if !text.isEmpty { lines.append("\nDescription:\n\(text.prefix(2500))") }
        }

        let rawComments = (f["comment"] as? [String: Any])?["comments"] as? [[String: Any]] ?? []
        if !rawComments.isEmpty {
            lines.append("\nComments (\(rawComments.count) total, last 5):")
            for c in rawComments.suffix(5) {
                let author  = (c["author"] as? [String: Any])?["displayName"] as? String ?? "?"
                let created = String((c["created"] as? String ?? "").prefix(16)).replacingOccurrences(of: "T", with: " ")
                let body    = extractADFText(c["body"] as? [String: Any])
                lines.append("  [\(created)] \(author): \(body.prefix(400))")
            }
        }

        let subtasks = f["subtasks"] as? [[String: Any]] ?? []
        if !subtasks.isEmpty {
            lines.append("\nSubtasks:")
            for st in subtasks {
                let stKey    = st["key"] as? String ?? "?"
                let stFields = st["fields"] as? [String: Any] ?? [:]
                let stStatus = (stFields["status"] as? [String: Any])?["name"] as? String ?? "?"
                lines.append("  \(stKey): \(stFields["summary"] as? String ?? "") [\(stStatus)]")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func extractADFText(_ node: [String: Any]?) -> String {
        guard let node else { return "" }
        var parts: [String] = []
        if let text = node["text"] as? String { parts.append(text) }
        if let content = node["content"] as? [[String: Any]] {
            for child in content {
                let t = extractADFText(child)
                if !t.isEmpty { parts.append(t) }
            }
        }
        let nodeType = node["type"] as? String ?? ""
        if ["paragraph", "heading", "bulletList", "orderedList", "listItem"].contains(nodeType) {
            return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces) + "\n"
        }
        return parts.joined(separator: "")
    }

    // MARK: - History Persistence

    func clearHistory() {
        messages = []
        apiHistory = []
        ticketCache = [:]
        pendingConfirmation = nil
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([CopilotMessage].self, from: data) else { return }
        // Drop stale pending confirmation cards — their API history context is gone
        messages = Array(decoded.filter { $0.pendingAction == nil }.suffix(50))
    }

    private func saveHistory() {
        let toSave = Array(messages.suffix(50))
        if let data = try? JSONEncoder().encode(toSave) {
            try? data.write(to: historyURL)
        }
    }
}

import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [CopilotMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isGatheringContext: Bool = false
    @Published var error: String?
    @Published var activeContextTypes: Set<ContextType> = [.jiraTickets]
    @Published var contextLabels: [ContextType: String] = [:]  // e.g. "5 tickets", "3 events"

    private let claudeService = ClaudeService()
    private let jiraService = JiraService()
    private let googleService = GoogleService()
    private let costService = AWSCostService()
    private let historyURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.historyURL = home.appendingPathComponent(".boomi_sre_chat_history.json")
        loadHistory()
    }

    // MARK: - Send

    func send(appState: AppState) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard claudeService.discoverAPIKey() != nil else {
            error = "No Anthropic API key found. Configure it in Settings or set ANTHROPIC_API_KEY."
            return
        }

        inputText = ""
        error = nil

        // Gather context from selected services
        isGatheringContext = true
        let (contextText, sources) = await gatherContext(appState: appState)
        isGatheringContext = false

        // Build user message: API content includes context preamble, display content is just the question
        let apiContent: String
        if !contextText.isEmpty {
            apiContent = "=== LIVE CONTEXT ===\n\(contextText)\n=== END CONTEXT ===\n\n\(text)"
        } else {
            apiContent = text
        }

        let userMsg = CopilotMessage(
            role: .user,
            content: text,
            apiContent: contextText.isEmpty ? nil : apiContent,
            contextSources: sources
        )
        messages.append(userMsg)

        // Build API messages array from conversation history
        var apiMessages: [(role: String, content: String)] = []
        for msg in messages {
            switch msg.role {
            case .user:
                apiMessages.append((role: "user", content: msg.apiContent ?? msg.content))
            case .assistant:
                apiMessages.append((role: "assistant", content: msg.content))
            case .system:
                break  // handled as system prompt
            }
        }

        isLoading = true
        do {
            let response = try await claudeService.chat(
                messages: apiMessages,
                systemPrompt: systemPrompt(userEmail: appState.jiraEmail),
                maxTokens: 4096
            )
            let assistantMsg = CopilotMessage(role: .assistant, content: response)
            messages.append(assistantMsg)
        } catch {
            self.error = error.localizedDescription
            // Remove the user message that failed
            messages.removeLast()
        }
        isLoading = false
        saveHistory()
    }

    // MARK: - Quick Actions

    func executeQuickAction(_ action: QuickAction) {
        // Override active context types for this action
        if !action.contextTypes.isEmpty {
            activeContextTypes = action.contextTypes
        }
        inputText = action.prompt
    }

    // MARK: - Context Gathering

    private func gatherContext(appState: AppState) async -> (text: String, sources: [ContextSource]) {
        var parts: [String] = []
        var sources: [ContextSource] = []

        // Capture values for use in tasks
        let types = activeContextTypes
        let baseURL = appState.jiraBaseURL
        let email = appState.jiraEmail
        let token = appState.jiraAPIToken
        let jiraConfigured = appState.isJiraConfigured
        let googleCreds = appState.googleCredentials
        let awsProfile = appState.awsSSOProfile

        // Jira tickets
        if types.contains(.jiraTickets) && jiraConfigured {
            if let (text, source) = await fetchJiraContext(
                baseURL: baseURL, email: email, token: token
            ) {
                parts.append(text)
                sources.append(source)
                await MainActor.run { contextLabels[.jiraTickets] = source.label }
            }
        }

        // Calendar events (today)
        if types.contains(.calendar), let creds = googleCreds {
            if let (text, source) = await fetchCalendarContext(credentials: creds) {
                parts.append(text)
                sources.append(source)
                await MainActor.run { contextLabels[.calendar] = source.label }
            }
        }

        // Recent unread emails
        if types.contains(.email), let creds = googleCreds {
            if let (text, source) = await fetchEmailContext(credentials: creds) {
                parts.append(text)
                sources.append(source)
                await MainActor.run { contextLabels[.email] = source.label }
            }
        }

        // AWS costs (current month)
        if types.contains(.awsCosts) && !awsProfile.isEmpty {
            if let (text, source) = await fetchAWSContext(profile: awsProfile) {
                parts.append(text)
                sources.append(source)
                await MainActor.run { contextLabels[.awsCosts] = source.label }
            }
        }

        return (parts.joined(separator: "\n\n"), sources)
    }

    private func fetchJiraContext(
        baseURL: String, email: String, token: String
    ) async -> (String, ContextSource)? {
        do {
            let jql = "assignee = currentUser() AND statusCategory NOT IN (Done) ORDER BY priority ASC, updated DESC"
            let result = try await jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql,
                fields: ["summary", "status", "priority", "issuetype", "duedate", "labels", "updated"],
                maxResults: 15
            )
            guard !result.issues.isEmpty else { return nil }

            var lines = ["My open Jira tickets (\(result.issues.count)):"]
            for issue in result.issues {
                let status = issue.fields.status?.name ?? "?"
                let priority = issue.fields.priority?.name ?? "?"
                let type_ = issue.fields.issuetype?.name ?? ""
                var line = "  • \(issue.key) [\(priority)] [\(status)] \(type_): \(issue.fields.summary ?? "")"
                if let due = issue.fields.duedate, !due.isEmpty {
                    line += " (due \(due))"
                }
                lines.append(line)
            }
            let text = lines.joined(separator: "\n")
            let source = ContextSource(
                type: .jiraTickets,
                label: "\(result.issues.count) tickets",
                summary: text
            )
            return (text, source)
        } catch {
            return nil
        }
    }

    private func fetchCalendarContext(credentials: GoogleCredentials) async -> (String, ContextSource)? {
        do {
            let events = try await googleService.listEvents(
                credentials: credentials, maxResults: 10, daysAhead: 1
            )
            guard !events.isEmpty else { return nil }

            var lines = ["Today's calendar (\(events.count) events):"]
            for event in events.prefix(10) {
                // startDateTime is ISO8601 string; show first 16 chars (date + time)
                let timeStr = String(event.startDateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
                let allDayNote = event.isAllDay ? " (all day)" : ""
                lines.append("  • \(timeStr)\(allDayNote): \(event.summary)")
            }
            let text = lines.joined(separator: "\n")
            let source = ContextSource(
                type: .calendar,
                label: "\(events.count) events",
                summary: text
            )
            return (text, source)
        } catch {
            return nil
        }
    }

    private func fetchEmailContext(credentials: GoogleCredentials) async -> (String, ContextSource)? {
        do {
            let messages = try await googleService.listMessages(
                credentials: credentials, query: "is:unread", maxResults: 15
            )
            guard !messages.isEmpty else { return nil }

            var lines = ["Recent unread emails (\(messages.count)):"]
            for msg in messages.prefix(15) {
                lines.append("  • From: \(msg.from) — \(msg.subject)")
            }
            let text = lines.joined(separator: "\n")
            let source = ContextSource(
                type: .email,
                label: "\(messages.count) unread",
                summary: text
            )
            return (text, source)
        } catch {
            return nil
        }
    }

    private func fetchAWSContext(profile: String) async -> (String, ContextSource)? {
        do {
            let calendar = Calendar.current
            let now = Date()
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let result = try await costService.getCostAndUsage(
                profile: profile,
                startDate: df.string(from: monthStart),
                endDate: df.string(from: nextMonth),
                granularity: .monthly,
                groupBy: .service
            )

            // Use aggregated convenience property (sums across all periods)
            let aggregated = result.aggregated.prefix(10)
            let total = result.totalCost
            let sorted = aggregated

            var lines = ["AWS costs this month (top services, total $\(String(format: "%.2f", total)):"]
            for item in sorted {
                lines.append("  • \(item.name): $\(String(format: "%.2f", item.amount))")
            }
            let text = lines.joined(separator: "\n")
            let source = ContextSource(
                type: .awsCosts,
                label: "$\(String(format: "%.0f", total))",
                summary: text
            )
            return (text, source)
        } catch {
            return nil
        }
    }

    // MARK: - System Prompt

    private func systemPrompt(userEmail: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        let nowStr = df.string(from: Date())

        return """
        You are an AI Copilot embedded in Boomi SRE — a native macOS app for Boomi's APIM SRE team. \
        Today is \(nowStr). The user's email is \(userEmail.isEmpty ? "unknown" : userEmail).

        You have access to real-time SRE context that may be injected at the start of user messages \
        under a "=== LIVE CONTEXT ===" block. Use this data to give specific, actionable answers.

        Your capabilities:
        - Analyze and prioritize Jira tickets (reference specific ticket keys like CAMSRE-123)
        - Explain AWS cost trends and recommend concrete optimizations
        - Draft incident postmortems, runbooks, and Confluence documentation
        - Help plan sprints based on the actual ticket backlog
        - Correlate information across systems (e.g., cost spike + recent deploy)
        - Draft Jira comments, PR descriptions, and stakeholder updates

        Guidelines:
        - Be specific and actionable — reference actual ticket keys, dollar amounts, service names
        - Format all responses in markdown (bold headings, bullet points, code blocks where relevant)
        - When context is missing, say so and suggest what to enable
        - Keep responses focused and concise; avoid restating information the user already has
        - Jira base URL is https://boomii.atlassian.net — format ticket links as [KEY](https://boomii.atlassian.net/browse/KEY)
        """
    }

    // MARK: - History Persistence

    func clearHistory() {
        messages = []
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([CopilotMessage].self, from: data) else { return }
        // Keep last 50 messages
        messages = Array(decoded.suffix(50))
    }

    private func saveHistory() {
        let toSave = Array(messages.suffix(50))
        if let data = try? JSONEncoder().encode(toSave) {
            try? data.write(to: historyURL)
        }
    }
}

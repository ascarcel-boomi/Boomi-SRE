import Foundation
import SwiftUI

@Observable
@MainActor
final class ExecAssistantViewModel {

    // MARK: - Published State

    var briefings: [Briefing] = []
    var isGenerating: [BriefingType: Bool] = [:]
    var errors: [BriefingType: String] = [:]
    var saveError: String?

    // MARK: - Services

    @ObservationIgnored private let claudeService = ClaudeService()
    @ObservationIgnored private let jiraService   = JiraService()
    @ObservationIgnored private let googleService = GoogleService()

    @ObservationIgnored private let historyURL: URL

    /// Weak-ref so ExecAssistantViewModel can fire briefing notifications without
    /// threading notificationVM through every generate method.
    @ObservationIgnored weak var notificationVM: NotificationViewModel?

    // MARK: - Init

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.historyURL = home.appendingPathComponent(".boomi_sre_briefings.json")
        loadHistory()
    }

    // MARK: - Convenience

    /// Most recent briefing of the given type, or nil if never generated.
    func lastBriefing(of type: BriefingType) -> Briefing? {
        briefings
            .filter { $0.type == type }
            .sorted { $0.generatedAt > $1.generatedAt }
            .first
    }

    var unreadCount: Int {
        briefings.filter { !$0.isRead }.count
    }

    func markAsRead(_ briefing: Briefing, appState: AppState) {
        if let idx = briefings.firstIndex(where: { $0.id == briefing.id }) {
            briefings[idx].isRead = true
            saveHistory()
            appState.unreadBriefingCount = unreadCount
        }
    }

    // MARK: - Generate All

    func generateAll(appState: AppState) async {
        let hasGoogle  = appState.googleCredentials != nil
        let hasJira    = appState.isJiraConfigured
        let enabled    = appState.enabledBriefingTypes

        func isEnabled(_ type: BriefingType) -> Bool {
            enabled.isEmpty || enabled.contains(type.rawValue)
        }

        if hasGoogle {
            if isEnabled(.morningBrief)    { await generateMorningBrief(appState: appState) }
            if isEnabled(.emailTriage)     { await generateEmailTriage(appState: appState) }
            if isEnabled(.preMeetingBrief) { await generatePreMeetingBrief(appState: appState) }
            if isEnabled(.actionTracker)   { await generateActionTracker(appState: appState) }
            if isEnabled(.eodDigest)       { await generateEODDigest(appState: appState) }
        }
        if hasJira && isEnabled(.dailyTicketBrief) {
            await generateDailyTicketBrief(appState: appState)
        }
        if isEnabled(.claudeUsage) {
            await generateClaudeUsage(appState: appState)
        }
    }

    // MARK: - Task 1: Morning Brief

    func generateMorningBrief(appState: AppState) async {
        guard let creds = appState.googleCredentials else {
            errors[.morningBrief] = "Google Workspace not configured."
            return
        }
        guard claudeService.isAIAvailable else {
            errors[.morningBrief] = "No Anthropic API key found."
            return
        }

        setGenerating(.morningBrief, true)
        errors[.morningBrief] = nil

        do {
            // Today's events + overnight emails (since 10 PM yesterday)
            async let eventsTask  = googleService.listEvents(credentials: creds, maxResults: 20, daysAhead: 1)
            async let emailsTask  = googleService.listMessages(
                credentials: creds, query: overnightEmailQuery(), maxResults: 30
            )
            let (events, emails) = try await (eventsTask, emailsTask)

            let userPrompt = """
            Prepare \(displayName(appState))\'s morning briefing.

            ## TODAY'S CALENDAR
            \(formatEvents(events))

            ## OVERNIGHT EMAILS (since 10pm yesterday)
            \(formatEmails(emails))

            Write a morning brief with these sections:
            1. **Day at a Glance** — 2–3 sentence overview of the day
            2. **Meetings Today** — list each meeting with time, attendees, and a one-line purpose
            3. **Email Priorities** — top 3–5 emails that need attention today, with suggested action
            4. **Action Items** — any commitments or deadlines visible from the emails above
            5. **Heads Up** — anything unusual, time-sensitive, or worth flagging

            Keep the whole brief under 400 words. Use bullet points. Be direct.
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: eaPersona(appState),
                maxTokens: 4096
            )
            appendBriefing(Briefing(
                type: .morningBrief,
                content: content,
                contextSummary: "\(events.count) meetings, \(emails.count) overnight emails"
            ), appState: appState)
        } catch {
            errors[.morningBrief] = error.localizedDescription
        }

        setGenerating(.morningBrief, false)
    }

    // MARK: - Task 2: Email Triage

    func generateEmailTriage(appState: AppState) async {
        guard let creds = appState.googleCredentials else {
            errors[.emailTriage] = "Google Workspace not configured."
            return
        }
        guard claudeService.isAIAvailable else {
            errors[.emailTriage] = "No Anthropic API key found."
            return
        }

        setGenerating(.emailTriage, true)
        errors[.emailTriage] = nil

        do {
            let emails = try await googleService.listMessages(
                credentials: creds, query: "is:unread", maxResults: 25
            )

            let userPrompt = """
            Triage \(displayName(appState))\'s inbox. Here are the unread emails:

            \(formatEmails(emails))

            For each email, classify it:
            - **P1 — Respond within 2 hours**: direct questions, executive escalations, time-sensitive requests
            - **P2 — Respond by end of day**: items that need a reply today but not urgently
            - **P3 — FYI / Low priority**: newsletters, notifications, CC\'d threads, no action needed

            Output format (one block per email):
            ---
            **[P1/P2/P3] Subject**
            From: sender
            Action: one sentence describing what to do
            Reply suggestion (P1 only): "..."
            ---

            After the list, add a **Summary** line: "X P1 items need your attention, Y P2 by EOD, Z P3 can wait."
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: eaPersona(appState),
                maxTokens: 4096
            )
            appendBriefing(Briefing(
                type: .emailTriage,
                content: content,
                contextSummary: "\(emails.count) unread emails"
            ), appState: appState)
        } catch {
            errors[.emailTriage] = error.localizedDescription
        }

        setGenerating(.emailTriage, false)
    }

    // MARK: - Task 3: Pre-Meeting Brief

    func generatePreMeetingBrief(appState: AppState) async {
        guard let creds = appState.googleCredentials else {
            errors[.preMeetingBrief] = "Google Workspace not configured."
            return
        }
        guard claudeService.isAIAvailable else {
            errors[.preMeetingBrief] = "No Anthropic API key found."
            return
        }

        setGenerating(.preMeetingBrief, true)
        errors[.preMeetingBrief] = nil

        do {
            async let eventsTask = googleService.listEvents(credentials: creds, maxResults: 10, daysAhead: 1)
            async let emailsTask = googleService.listMessages(
                credentials: creds, query: "is:unread newer_than:7d", maxResults: 20
            )
            let (events, emails) = try await (eventsTask, emailsTask)

            // Find next non-all-day event starting after now
            let now = Date()
            let nextEvent = events.first { event in
                !event.isAllDay && parseEventDate(event.startDateTime).map { $0 > now } ?? false
            }

            guard let event = nextEvent else {
                appendBriefing(Briefing(
                    type: .preMeetingBrief,
                    content: "## Pre-Meeting Brief\n\nNo upcoming meetings found in the next 24 hours.",
                    contextSummary: "No upcoming meetings"
                ), appState: appState)
                setGenerating(.preMeetingBrief, false)
                return
            }

            let startStr = String(event.startDateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
            let endStr   = String(event.endDateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
            let attendeeStr = event.attendees.prefix(8).joined(separator: ", ")

            let userPrompt = """
            Prepare a pre-meeting brief for \(displayName(appState)).

            ## MEETING
            Title: \(event.summary)
            Time: \(startStr) → \(endStr)
            Attendees: \(attendeeStr.isEmpty ? "None listed" : attendeeStr)
            Description: \(event.description.isEmpty ? "None" : event.description)
            Location/Link: \(event.hangoutLink.isEmpty ? (event.location.isEmpty ? "None" : event.location) : event.hangoutLink)

            ## RECENT RELATED EMAILS (past 7 days)
            \(formatEmails(emails))

            Write a concise pre-meeting brief (under 250 words) with:
            1. **Purpose** — what this meeting is for in one sentence
            2. **Key People** — who\'s attending and their likely agenda
            3. **Context from Email** — relevant threads or decisions from recent emails
            4. **Suggested Talking Points** — 3–4 bullets \(displayName(appState)) should be ready to address
            5. **Watch Out** — any open questions, risks, or tensions to be aware of
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: eaPersona(appState),
                maxTokens: 4096
            )
            appendBriefing(Briefing(
                type: .preMeetingBrief,
                content: content,
                contextSummary: "Next: \(event.summary) at \(startStr)"
            ), appState: appState)
        } catch {
            errors[.preMeetingBrief] = error.localizedDescription
        }

        setGenerating(.preMeetingBrief, false)
    }

    // MARK: - Task 4: Action Tracker

    func generateActionTracker(appState: AppState) async {
        guard let creds = appState.googleCredentials else {
            errors[.actionTracker] = "Google Workspace not configured."
            return
        }
        guard claudeService.isAIAvailable else {
            errors[.actionTracker] = "No Anthropic API key found."
            return
        }

        setGenerating(.actionTracker, true)
        errors[.actionTracker] = nil

        do {
            async let eventsTask = googleService.listEvents(credentials: creds, maxResults: 20, daysAhead: 0)
            async let emailsTask = googleService.listMessages(
                credentials: creds, query: "newer_than:1d", maxResults: 25
            )
            let (events, emails) = try await (eventsTask, emailsTask)

            // Past events only
            let now = Date()
            let pastEvents = events.filter { event in
                parseEventDate(event.endDateTime).map { $0 < now } ?? false
            }

            let userPrompt = """
            Extract action items from \(displayName(appState))\'s emails and completed meetings today.

            ## TODAY'S EMAILS
            \(formatEmails(emails))

            ## COMPLETED MEETINGS TODAY
            \(formatEvents(pastEvents))

            List action items grouped into these categories:

            **Commitments You Made** — things \(displayName(appState)) committed to doing

            **Waiting On Others** — things \(displayName(appState)) is waiting on someone else to do

            **Follow-Ups Needed** — ongoing items requiring follow-up

            **Decisions Needed** — things that need a decision

            For each item: what needs to be done, who owns it, and due date (if visible).
            Only include concrete, actionable items. Omit any section that has no items.
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: eaPersona(appState),
                maxTokens: 4096
            )
            appendBriefing(Briefing(
                type: .actionTracker,
                content: content,
                contextSummary: "\(emails.count) emails, \(pastEvents.count) completed meetings"
            ), appState: appState)
        } catch {
            errors[.actionTracker] = error.localizedDescription
        }

        setGenerating(.actionTracker, false)
    }

    // MARK: - Task 5: EOD Digest

    func generateEODDigest(appState: AppState) async {
        guard let creds = appState.googleCredentials else {
            errors[.eodDigest] = "Google Workspace not configured."
            return
        }
        guard claudeService.isAIAvailable else {
            errors[.eodDigest] = "No Anthropic API key found."
            return
        }

        setGenerating(.eodDigest, true)
        errors[.eodDigest] = nil

        do {
            async let todayEventsTask    = googleService.listEvents(credentials: creds, maxResults: 20, daysAhead: 0)
            async let tomorrowEventsTask = googleService.listEvents(credentials: creds, maxResults: 10, daysAhead: 2)
            async let emailsTask         = googleService.listMessages(
                credentials: creds, query: "newer_than:1d", maxResults: 20
            )
            let (todayEvents, tomorrowEvents, emails) = try await (todayEventsTask, tomorrowEventsTask, emailsTask)

            // Filter tomorrow's events (skip today's)
            let cal = Calendar.current
            let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
            let justTomorrow = tomorrowEvents.filter { event in
                parseEventDate(event.startDateTime).map { cal.isDate($0, inSameDayAs: tomorrow) } ?? false
            }

            // Use most recent action tracker briefing content as context if available
            let actionItemsText: String
            if let at = lastBriefing(of: .actionTracker) {
                actionItemsText = at.content
            } else {
                actionItemsText = "None tracked today. Derive from the emails and meetings below."
            }

            let userPrompt = """
            Prepare \(displayName(appState))\'s end-of-day digest.

            ## TODAY'S MEETINGS
            \(formatEvents(todayEvents))

            ## TODAY'S EMAILS (sample)
            \(formatEmails(Array(emails.prefix(15))))

            ## TRACKED ACTION ITEMS
            \(actionItemsText)

            ## TOMORROW'S CALENDAR
            \(formatEvents(justTomorrow))

            Write an EOD digest (under 350 words) with:
            1. **Day Summary** — 2–3 sentences on what got done today
            2. **Open Action Items** — what still needs attention before tomorrow
            3. **Waiting On** — items where \(displayName(appState)) is waiting on someone else
            4. **Tomorrow's Preview** — key meetings and priorities for tomorrow
            5. **One Thing** — the single most important thing to do first thing tomorrow

            Be direct. No filler.
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: eaPersona(appState),
                maxTokens: 4096
            )
            appendBriefing(Briefing(
                type: .eodDigest,
                content: content,
                contextSummary: "\(todayEvents.count) meetings, \(emails.count) emails, \(justTomorrow.count) tomorrow"
            ), appState: appState)
        } catch {
            errors[.eodDigest] = error.localizedDescription
        }

        setGenerating(.eodDigest, false)
    }

    // MARK: - Task 6: Daily Ticket Brief

    func generateDailyTicketBrief(appState: AppState) async {
        guard appState.isJiraConfigured else {
            errors[.dailyTicketBrief] = "Jira is not configured."
            return
        }
        guard claudeService.isAIAvailable else {
            errors[.dailyTicketBrief] = "No Anthropic API key found."
            return
        }

        setGenerating(.dailyTicketBrief, true)
        errors[.dailyTicketBrief] = nil

        let baseURL = appState.jiraBaseURL
        let email   = appState.jiraEmail
        let token   = appState.jiraAPIToken
        let fields  = ["summary", "status", "priority", "issuetype", "duedate", "labels"]

        do {
            async let inProgressTask = jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: "assignee = currentUser() AND statusCategory = \"In Progress\" ORDER BY updated DESC",
                fields: fields, maxResults: 20
            )
            async let overdueTask = jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: "assignee = currentUser() AND duedate < now() AND statusCategory NOT IN (Done) ORDER BY duedate ASC",
                fields: fields, maxResults: 15
            )
            async let sprintTodoTask = jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: "assignee = currentUser() AND sprint in openSprints() AND statusCategory = \"To Do\" ORDER BY priority ASC, created ASC",
                fields: fields, maxResults: 20
            )
            async let unplannedTask = jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: "assignee = currentUser() AND issuetype in (\"Operational Request\", \"Troubleshooting Request\", \"Access Request\", \"Bug\", \"Incident\") AND statusCategory NOT IN (Done) AND (sprint is EMPTY OR sprint not in openSprints()) ORDER BY priority ASC, created ASC",
                fields: fields, maxResults: 20
            )

            let (inProgress, overdue, sprintTodo, unplanned) = try await (
                inProgressTask, overdueTask, sprintTodoTask, unplannedTask
            )

            let ticketsText = """
            IN PROGRESS (\(inProgress.issues.count)):
            \(formatJiraIssues(inProgress.issues))

            OVERDUE (\(overdue.issues.count)):
            \(formatJiraIssues(overdue.issues))

            SPRINT TO-DO (\(sprintTodo.issues.count)):
            \(formatJiraIssues(sprintTodo.issues))

            UNPLANNED / KANBAN (\(unplanned.issues.count)):
            \(formatJiraIssues(unplanned.issues))
            """

            let totalCount = inProgress.issues.count + overdue.issues.count + sprintTodo.issues.count + unplanned.issues.count

            let userPrompt = """
            Build a strategic daily ticket plan for \(displayName(appState)).

            ## OPEN JIRA TICKETS (assigned to \(displayName(appState)))

            \(ticketsText)

            Create a focused daily ticket brief using only the sections that apply. Omit any section with no relevant tickets.

            **Focus Now** — The 1–3 tickets to start on first today. Be specific about why each one is the priority (e.g. overdue, blocking others, sprint at risk, SLA concern). One action sentence per ticket.

            **Sprint Commitments** — In-sprint stories. Is the sprint on track? Flag anything at risk of not completing. If everything looks fine, one sentence is enough.

            **Unplanned Queue** — Operational Requests, Troubleshooting Requests, and Access Requests. Order by urgency. Call out anything that looks time-sensitive or SLA-bound.

            **Blocked / Needs Input** — Tickets that can\'t move forward without action from someone else. What exactly is needed and from whom?

            **Defer** — Tickets that can safely wait until tomorrow or later. One line each.

            Formatting rules:
            - Every ticket must be a markdown link: [TICKET-KEY](https://boomii.atlassian.net/browse/TICKET-KEY)
            - Be prescriptive — tell \(displayName(appState)) exactly what to do, not just what to think about
            - Keep the total brief under 500 words
            - Start directly with the first section — no preamble
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: eaPersona(appState),
                maxTokens: 4096
            )
            appendBriefing(Briefing(
                type: .dailyTicketBrief,
                content: content,
                contextSummary: "\(totalCount) open tickets"
            ), appState: appState)
        } catch {
            errors[.dailyTicketBrief] = error.localizedDescription
        }

        setGenerating(.dailyTicketBrief, false)
    }

    // MARK: - Task 7: Claude Usage Report

    func generateClaudeUsage(appState: AppState) async {
        guard claudeService.isAIAvailable else {
            errors[.claudeUsage] = "No Anthropic API key found."
            return
        }

        setGenerating(.claudeUsage, true)
        errors[.claudeUsage] = nil

        let usageData = await Task.detached(priority: .utility) {
            Self.parseClaudeUsageLogs(hoursBack: 24)
        }.value

        do {
            let userPrompt = """
            Generate a Claude Code usage report based on the following data.

            \(usageData)

            Write a usage report with these sections:
            1. **Summary** — total estimated cost, total messages, total input/output tokens, overall cache hit rate
            2. **By Model** — breakdown per model (messages, tokens, estimated cost, cache hit rate)
            3. **Optimization Tips** — 2-4 specific, actionable suggestions based on the data (e.g. cache hit rate low → suggest prompt caching, high context usage → consider breaking into smaller conversations)

            Keep it concise and factual. Use bullet points.
            """

            let content = try await claudeService.chat(
                messages: [("user", userPrompt)],
                systemPrompt: """
                You are a developer productivity analyst. Parse Claude API usage data and generate \
                clear, actionable reports. Be concise and factual. Format costs as "$X.XXXX".
                """,
                maxTokens: 2048
            )
            appendBriefing(Briefing(
                type: .claudeUsage,
                content: content,
                contextSummary: "Past 24 hours"
            ), appState: appState)
        } catch {
            errors[.claudeUsage] = error.localizedDescription
        }

        setGenerating(.claudeUsage, false)
    }

    // MARK: - Claude Usage Log Parser

    /// Reads `~/.claude/projects/**/*.jsonl` and aggregates token usage by model.
    /// `nonisolated` so it can be called from `Task.detached` (pure file I/O, no actor state).
    nonisolated static func parseClaudeUsageLogs(hoursBack: Int = 24) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude/projects")

        guard let enumerator = FileManager.default.enumerator(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return "No Claude Code project logs found at ~/.claude/projects/" }

        let cutoff = Date().addingTimeInterval(-Double(hoursBack) * 3600)

        struct ModelStats {
            var inputTokens: Int = 0
            var outputTokens: Int = 0
            var cacheWriteTokens: Int = 0
            var cacheReadTokens: Int = 0
            var messageCount: Int = 0
        }

        var modelStats: [String: ModelStats] = [:]
        var filesScanned = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate,
                  modDate > cutoff else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            filesScanned += 1

            for line in content.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["type"] as? String) == "assistant",
                      let message = json["message"] as? [String: Any],
                      let model = message["model"] as? String,
                      let usage = message["usage"] as? [String: Any] else { continue }

                var stats = modelStats[model, default: ModelStats()]
                stats.inputTokens      += usage["input_tokens"]                    as? Int ?? 0
                stats.outputTokens     += usage["output_tokens"]                   as? Int ?? 0
                stats.cacheWriteTokens += usage["cache_creation_input_tokens"]     as? Int ?? 0
                stats.cacheReadTokens  += usage["cache_read_input_tokens"]         as? Int ?? 0
                stats.messageCount     += 1
                modelStats[model] = stats
            }
        }

        if modelStats.isEmpty {
            return "No Claude Code activity found in the past \(hoursBack) hours (scanned \(filesScanned) log files)."
        }

        // Pricing per million tokens (input, output, cacheWrite, cacheRead)
        let pricing: [String: (Double, Double, Double, Double)] = [
            "claude-opus-4-6":           (15.00, 75.00, 18.75, 1.50),
            "claude-sonnet-4-6":         ( 3.00, 15.00,  3.75, 0.30),
            "claude-haiku-4-5-20251001": ( 0.80,  4.00,  1.00, 0.08),
            "claude-haiku-4-5":          ( 0.80,  4.00,  1.00, 0.08),
        ]

        var lines: [String] = ["CLAUDE CODE USAGE — PAST \(hoursBack) HOURS (from \(filesScanned) log file(s)):"]
        var totalCost = 0.0
        var totalMessages = 0
        var totalInput = 0, totalOutput = 0, totalCacheWrite = 0, totalCacheRead = 0

        for (model, stats) in modelStats.sorted(by: { $0.key < $1.key }) {
            let p = pricing[model] ?? (3.00, 15.00, 3.75, 0.30)
            let cost = (Double(stats.inputTokens)      / 1_000_000 * p.0)
                     + (Double(stats.outputTokens)     / 1_000_000 * p.1)
                     + (Double(stats.cacheWriteTokens) / 1_000_000 * p.2)
                     + (Double(stats.cacheReadTokens)  / 1_000_000 * p.3)
            totalCost    += cost
            totalMessages += stats.messageCount
            totalInput    += stats.inputTokens
            totalOutput   += stats.outputTokens
            totalCacheWrite += stats.cacheWriteTokens
            totalCacheRead  += stats.cacheReadTokens

            let allInput   = stats.inputTokens + stats.cacheReadTokens
            let cacheHit   = allInput > 0 ? Double(stats.cacheReadTokens) / Double(allInput) * 100 : 0

            lines.append("""

            Model: \(model)
              Messages: \(stats.messageCount)
              Input tokens: \(stats.inputTokens)
              Output tokens: \(stats.outputTokens)
              Cache write: \(stats.cacheWriteTokens)
              Cache read: \(stats.cacheReadTokens)
              Cache hit rate: \(String(format: "%.1f", cacheHit))%
              Estimated cost: $\(String(format: "%.4f", cost))
            """)
        }

        let allInput = totalInput + totalCacheRead
        let overallCacheHit = allInput > 0 ? Double(totalCacheRead) / Double(allInput) * 100 : 0

        lines.insert("""

        TOTALS:
          Total messages: \(totalMessages)
          Total input tokens: \(totalInput)
          Total output tokens: \(totalOutput)
          Total cache write: \(totalCacheWrite)
          Total cache read: \(totalCacheRead)
          Overall cache hit rate: \(String(format: "%.1f", overallCacheHit))%
          Total estimated cost: $\(String(format: "%.4f", totalCost))
        """, at: 1)

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting Helpers

    private func formatEvents(_ events: [CalendarEvent]) -> String {
        guard !events.isEmpty else { return "No events scheduled." }
        return events.map { event in
            var line: String
            if event.isAllDay {
                line = "• All day: \(event.summary)"
            } else {
                let start = String(event.startDateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
                let end   = String(event.endDateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
                line = "• \(start) – \(end): \(event.summary)"
            }
            let attendees = event.attendees.prefix(5)
                .map { $0.components(separatedBy: "@").first ?? $0 }
                .joined(separator: ", ")
            if !attendees.isEmpty { line += " (with: \(attendees))" }
            return line
        }.joined(separator: "\n")
    }

    private func formatEmails(_ messages: [GmailMessage]) -> String {
        guard !messages.isEmpty else { return "No emails." }
        return messages.enumerated().map { i, msg in
            """
            [\(i + 1)] FROM: \(msg.from)
                SUBJECT: \(msg.subject)
                DATE: \(msg.dateString)
                SNIPPET: \(msg.snippet.prefix(300))
            """
        }.joined(separator: "\n\n")
    }

    private func formatJiraIssues(_ issues: [JiraIssue]) -> String {
        guard !issues.isEmpty else { return "None." }
        return issues.map { issue in
            let status   = issue.fields.status?.name   ?? "?"
            let priority = issue.fields.priority?.name ?? "?"
            let type_    = issue.fields.issuetype?.name ?? "?"
            let summary  = issue.fields.summary ?? ""
            var line = "• [\(issue.key)](https://boomii.atlassian.net/browse/\(issue.key)) [\(priority)] [\(status)] \(type_): \(summary)"
            if let due = issue.fields.duedate, !due.isEmpty { line += " (due \(due))" }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - System Prompt (EA Persona)

    private func eaPersona(_ appState: AppState) -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
        let nowStr = df.string(from: Date())
        let email  = appState.jiraEmail
        let name   = displayName(appState)
        return """
        You are an expert executive assistant for \(name) (\(email)) at Boomi, \
        a B2B integration software company. You are precise, concise, and professional. \
        You surface only what matters and never pad your responses. \
        Today's date/time: \(nowStr).

        IMPORTANT: Whenever you reference a Jira ticket (any pattern like CAMSRE-1234, SRE-1234, \
        INC-1234, etc.), always format it as a markdown link: \
        [TICKET-ID](https://boomii.atlassian.net/browse/TICKET-ID). \
        Never mention a ticket ID as plain text.
        """
    }

    private func displayName(_ appState: AppState) -> String {
        let local = appState.jiraEmail.components(separatedBy: "@").first ?? "User"
        return local.components(separatedBy: ".")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Private Helpers

    private func setGenerating(_ type: BriefingType, _ value: Bool) {
        isGenerating[type] = value
    }

    private func appendBriefing(_ briefing: Briefing, appState: AppState) {
        briefings.append(briefing)
        saveHistory()
        appState.unreadBriefingCount = unreadCount
        notificationVM?.addBriefingNotification(type: briefing.type)
    }

    private func overnightEmailQuery() -> String {
        // Emails since 10pm yesterday
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.day! -= 1
        comps.hour = 22
        if let cutoff = cal.date(from: comps) {
            let secs = Int(cutoff.timeIntervalSince1970)
            return "after:\(secs)"
        }
        return "newer_than:12h"
    }

    private func parseEventDate(_ isoString: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                             .withColonSeparatorInTime, .withTimeZone]
        if let d = iso.date(from: isoString) { return d }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: String(isoString.prefix(19)))
    }

    // MARK: - History Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([Briefing].self, from: data) else { return }
        // Keep last 7 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        briefings = decoded.filter { $0.generatedAt > cutoff }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(briefings)
            try data.write(to: historyURL)
            saveError = nil
        } catch {
            saveError = "Failed to save briefings: \(error.localizedDescription)"
        }
    }
}

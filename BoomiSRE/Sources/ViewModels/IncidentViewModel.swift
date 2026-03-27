import Foundation
import SwiftUI

@MainActor
final class IncidentViewModel: ObservableObject {

    // MARK: - State

    @Published var incidents: [Incident] = []
    @Published var selectedIncident: Incident?
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastFetched: Date?

    // Filters
    @Published var incidentFilter: IncidentFilter = .active
    @Published var searchText: String = ""

    // Comment state
    @Published var selectedIncidentComments: [JiraComment] = []
    @Published var isLoadingComments = false
    @Published var commentInput = ""
    @Published var isPostingComment = false

    // AI
    @Published var aiOutput: String?
    @Published var isAnalyzing = false
    @Published var aiOutputLabel = ""
    @Published var aiError: String?

    private let claudeService = ClaudeService()
    private let jiraService   = JiraService()
    private var depthHint: String = ""

    // MARK: - Configure

    func configure(with profile: UserProfile) {
        depthHint = profile.experienceLevel.analysisDepthHint
    }

    // MARK: - Derived State

    var filteredIncidents: [Incident] {
        var result = incidents
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.jiraTicketKey ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var activeIncidents: [Incident] { incidents.filter(\.isActive) }
    var activeHighPriorityCount: Int { incidents.filter { $0.isActive && $0.isHighPriority }.count }

    // MARK: - Fetch from Jira

    func fetchIncidents(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira not configured. Set up Jira in Settings."
            return
        }

        isLoading = true
        error = nil
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint

        let jql = buildIncidentJQL(appState: appState)

        var fields = ["summary", "status", "priority", "issuetype", "created", "updated",
                      "resolutiondate", "assignee", "reporter", "labels", "comment"]
        if !appState.incidentProductElementFieldId.isEmpty {
            fields.append(appState.incidentProductElementFieldId)
        }

        do {
            let result = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: jql,
                fields: fields,
                maxResults: 100
            )
            incidents = result.issues.map { mapJiraToIncident($0, appState: appState) }
            lastFetched = Date()
            appState.activeIncidentCount = activeHighPriorityCount
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func buildIncidentJQL(appState: AppState) -> String {
        if appState.useCustomIncidentJQL, !appState.customIncidentJQL.isEmpty {
            return appState.customIncidentJQL
        }

        var clauses = ["project = \"Boomi Incident Management\""]

        // Use product resource map first, then product context, then legacy favorites
        let effectiveElements: [String]
        if !appState.activeIncidentProductElements.isEmpty {
            effectiveElements = appState.activeIncidentProductElements
        } else if let p = appState.selectedProduct, !p.incidentProductElements.isEmpty {
            effectiveElements = p.incidentProductElements
        } else if !appState.favoriteProductElements.isEmpty {
            effectiveElements = appState.favoriteProductElements
        } else {
            effectiveElements = []
        }
        if !effectiveElements.isEmpty {
            let elements = effectiveElements
                .map { "\"\($0)\"" }
                .joined(separator: ", ")
            clauses.append("\"product element[select list (multiple choices)]\" IN (\(elements))")
        }

        switch incidentFilter {
        case .active:
            clauses.append("statusCategory NOT IN (Done)")
        case .recent:
            clauses.append("created >= -30d")
        case .all:
            clauses.append("created >= -90d")
        }

        return clauses.joined(separator: " AND ") + " ORDER BY created DESC, priority DESC"
    }

    private func mapJiraToIncident(_ issue: JiraIssue, appState: AppState) -> Incident {
        let priorityName = issue.fields.priority?.name.lowercased() ?? ""
        let severity: IncidentSeverity = {
            switch priorityName {
            case "highest", "blocker", "p1": return .p1
            case "high", "critical", "p2": return .p2
            case "medium", "p3": return .p3
            default: return .p4
            }
        }()

        let categoryKey = issue.fields.status?.statusCategory?.key ?? ""
        let status: IncidentStatus = {
            switch categoryKey {
            case "done": return .resolved
            case "indeterminate": return .identified
            default: return .investigating
            }
        }()

        let created = parseJiraDate(issue.fields.created) ?? Date()

        var timeline: [TimelineEntry] = [
            TimelineEntry(
                timestamp: created,
                content: "Incident created: \(issue.key) — \(issue.fields.summary ?? "")",
                source: .jira
            )
        ]

        return Incident(
            id: deterministicUUID(from: issue.key),
            title: issue.fields.summary ?? issue.key,
            severity: severity,
            status: status,
            createdAt: created,
            resolvedAt: nil,
            jiraTicketKey: issue.key,
            timeline: timeline,
            affectedServices: [],
            aiAnalysis: nil
        )
    }

    private func deterministicUUID(from key: String) -> UUID {
        var hash = key.utf8.reduce(UInt64(0x811c9dc5)) { acc, byte in
            (acc ^ UInt64(byte)) &* 0x01000193
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(hash & 0xFF); hash >>= 8 }
        hash = key.utf8.reduce(UInt64(0xcbf29ce484222325)) { acc, byte in
            (acc ^ UInt64(byte)) &* 0x100000001b3
        }
        for i in 8..<16 { bytes[i] = UInt8(hash & 0xFF); hash >>= 8 }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: bytes) as UUID
    }

    private func parseJiraDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        let fmts = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
        let fmt = DateFormatter()
        for f in fmts { fmt.dateFormat = f; if let d = fmt.date(from: str) { return d } }
        return nil
    }

    // MARK: - Comments

    func loadComments(for incident: Incident, appState: AppState) async {
        guard let key = incident.jiraTicketKey, appState.isJiraConfigured else { return }
        isLoadingComments = true
        do {
            selectedIncidentComments = try await jiraService.getIssueComments(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                issueKey: key
            )
        } catch {
            selectedIncidentComments = []
        }
        isLoadingComments = false
    }

    func postComment(appState: AppState) async {
        let text = commentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let key = selectedIncident?.jiraTicketKey,
              appState.isJiraConfigured else { return }
        isPostingComment = true
        do {
            try await jiraService.addComment(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                key: key,
                body: text
            )
            commentInput = ""
            if let incident = selectedIncident {
                await loadComments(for: incident, appState: appState)
            }
        } catch {
            aiError = "Failed to post comment: \(error.localizedDescription)"
        }
        isPostingComment = false
    }

    // MARK: - AI Actions

    func analyzeIncident() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiOutput = nil
        aiOutputLabel = "Root Cause Analysis"

        let context = buildIncidentContext(incident)
        do {
            let result = try await claudeService.chat(
                messages: [("user", """
                Analyze this SRE incident and suggest root cause.

                \(context)

                Provide:
                1. **Root Cause Hypothesis** — most likely cause(s) based on the timeline
                2. **Supporting Evidence** — what in the timeline points to this cause
                3. **Immediate Investigation Steps** — what to check right now (specific commands, dashboards, logs)
                4. **Escalation Assessment** — should additional teams be paged? (state who and why)
                5. **Estimated Time to Resolution** — rough ETA based on incident type

                Be specific. Reference timeline entries and affected services directly.
                """)],
                systemPrompt: incidentSystemPrompt,
                maxTokens: 1024
            )
            aiOutput = result
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
        if aiError == nil { ProductivityTracker.shared.log(.aiIncidentAnalysis, detail: incident.title, source: "Incidents") }
    }

    func draftStatusUpdate() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiOutput = nil
        aiOutputLabel = "Stakeholder Status Update"

        let context = buildIncidentContext(incident)
        do {
            aiOutput = try await claudeService.chat(
                messages: [("user", """
                Draft a stakeholder status update for this incident.

                \(context)

                Write a clear, professional status update (under 200 words) for internal Slack / management briefing. Include:
                - **What happened** — brief description of the issue
                - **Current status** — where we are in investigation/resolution
                - **Customer impact** — who is affected and how
                - **Next steps** — what the team is doing right now
                - **ETA** — estimated time to resolution (or "unknown" if unclear)

                Tone: factual, calm, actionable. No jargon.
                """)],
                systemPrompt: incidentSystemPrompt,
                maxTokens: 512
            )
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
        if aiError == nil { ProductivityTracker.shared.log(.aiStatusUpdateDraft, detail: incident.title, source: "Incidents") }
    }

    func draftPostmortem() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiOutput = nil
        aiOutputLabel = "Post-Incident Review Draft"

        let context = buildIncidentContext(incident)
        do {
            aiOutput = try await claudeService.chat(
                messages: [("user", """
                Generate a post-incident review (PIR) document for this incident.

                \(context)

                Structure the document as:

                ## Incident Summary
                (1-2 sentences)

                ## Timeline
                (Key events in chronological order)

                ## Root Cause
                (Technical explanation)

                ## Impact
                (Who was affected, for how long, at what scale)

                ## Contributing Factors
                (What made this possible or worse)

                ## What Went Well
                (Positive aspects of the response)

                ## Action Items
                (Numbered list: what, owner, due date — focus on prevention)

                ## Lessons Learned
                (2-3 key takeaways)

                Use the timeline entries to populate the Timeline section. Be specific about the Boomi APIM SRE context.
                """)],
                systemPrompt: incidentSystemPrompt,
                maxTokens: 2048
            )
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
        if aiError == nil { ProductivityTracker.shared.log(.aiPostmortemDraft, detail: incident.title, source: "Incidents") }
    }

    func suggestRemediation() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiOutput = nil
        aiOutputLabel = "Remediation Suggestions"

        let context = buildIncidentContext(incident)
        do {
            aiOutput = try await claudeService.chat(
                messages: [("user", """
                Suggest remediation steps for this incident.

                \(context)

                Provide:
                1. **Immediate Actions** (now) — steps to stop the bleeding and restore service
                2. **Short-term Fixes** (next 24h) — stabilization and root cause fixes
                3. **Long-term Prevention** (next sprint/quarter) — architectural or process improvements
                4. **Monitoring Improvements** — what alerts or dashboards would have caught this earlier

                Be specific: include actual commands, configuration changes, or runbook steps where possible.
                Reference the affected services: \(incident.affectedServices.joined(separator: ", ")).
                """)],
                systemPrompt: incidentSystemPrompt,
                maxTokens: 1024
            )
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
        if aiError == nil { ProductivityTracker.shared.log(.aiRemediationSuggestion, detail: incident.title, source: "Incidents") }
    }

    // MARK: - Context Builder

    private func buildIncidentContext(_ incident: Incident) -> String {
        var lines = [
            "INCIDENT: \(incident.title)",
            "Severity: \(incident.severity.label) | Status: \(incident.status.rawValue)",
            "Duration: \(incident.elapsedString)",
            "Created: \(incident.createdAt.formatted(date: .abbreviated, time: .shortened))",
        ]
        if !incident.affectedServices.isEmpty {
            lines.append("Affected Services / Product Elements: \(incident.affectedServices.joined(separator: ", "))")
        }
        if let key = incident.jiraTicketKey {
            lines.append("Jira Ticket: \(key) (https://boomii.atlassian.net/browse/\(key))")
        }

        if !selectedIncidentComments.isEmpty {
            lines.append("\nCOMMENTS (\(selectedIncidentComments.count)):")
            let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
            for c in selectedIncidentComments.suffix(10) {
                let dateStr = c.created.prefix(16).replacingOccurrences(of: "T", with: " ")
                lines.append("  [\(dateStr)] \(c.authorName): \(c.bodyText.prefix(500))")
            }
        } else if !incident.timeline.isEmpty {
            lines.append("\nTIMELINE (\(incident.timeline.count) entries):")
            let fmt = DateFormatter(); fmt.timeStyle = .short; fmt.dateStyle = .none
            for entry in incident.timeline {
                lines.append("  [\(fmt.string(from: entry.timestamp))] [\(entry.source.rawValue.uppercased())] \(entry.content)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var incidentSystemPrompt: String {
        let fmt = DateFormatter(); fmt.dateStyle = .long; fmt.timeStyle = .short
        let base = """
        You are an SRE incident commander for Boomi's APIM SRE team. \
        Today is \(fmt.string(from: Date())). \
        You help manage P1-P4 incidents affecting Boomi's Mashery API Management platform. \
        Be specific, calm, and action-oriented. Reference the timeline and affected services directly.
        """
        return depthHint.isEmpty ? base : base + "\n\n" + depthHint
    }
}

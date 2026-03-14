import Foundation
import SwiftUI

@MainActor
final class IncidentViewModel: ObservableObject {

    // MARK: - State

    @Published var incidents: [Incident] = []
    @Published var selectedIncident: Incident?
    @Published var isCreatingNew = false
    @Published var newTitle = ""
    @Published var newSeverity: IncidentSeverity = .p2
    @Published var newAffectedServices = ""
    @Published var entryInput = ""
    @Published var jiraKeyInput = ""
    @Published var isLinkingJira = false
    // AI
    @Published var aiOutput: String?
    @Published var isAnalyzing = false
    @Published var aiOutputLabel = ""
    @Published var aiError: String?

    private let claudeService = ClaudeService()
    private let jiraService   = JiraService()
    private let historyURL: URL
    private var depthHint: String = ""

    // MARK: - Init

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.historyURL = home.appendingPathComponent(".boomi_sre_incidents.json")
        loadIncidents()
    }

    // MARK: - Derived State

    var activeIncidents: [Incident] {
        incidents.filter(\.isActive).sorted { $0.createdAt > $1.createdAt }
    }

    var resolvedIncidents: [Incident] {
        incidents.filter { $0.status.isResolved }.sorted { $0.createdAt > $1.createdAt }
    }

    var activeHighPriorityCount: Int {
        incidents.filter { $0.isActive && $0.isHighPriority }.count
    }

    // MARK: - CRUD

    func configure(with profile: UserProfile) {
        depthHint = profile.experienceLevel.analysisDepthHint
    }

    func createIncident(appState: AppState) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let services = newAffectedServices
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var incident = Incident(title: title, severity: newSeverity, affectedServices: services)
        incident.timeline.append(TimelineEntry(
            content: "Incident declared: \(title) [\(newSeverity.label)]",
            source: "system"
        ))
        incidents.insert(incident, at: 0)
        selectedIncident = incident

        newTitle = ""
        newAffectedServices = ""
        newSeverity = .p2
        isCreatingNew = false

        saveIncidents()
        appState.activeIncidentCount = activeHighPriorityCount
    }

    func updateStatus(_ status: IncidentStatus, appState: AppState) {
        guard let id = selectedIncident?.id,
              let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].status = status
        if status.isResolved { incidents[idx].resolvedAt = Date() }
        incidents[idx].timeline.append(TimelineEntry(
            content: "Status updated to \(status.rawValue)",
            source: "system"
        ))
        selectedIncident = incidents[idx]
        saveIncidents()
        appState.activeIncidentCount = activeHighPriorityCount
    }

    func addTimelineEntry(source: String = "user", appState: AppState) {
        let text = entryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = selectedIncident?.id,
              let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].timeline.append(TimelineEntry(content: text, source: source))
        entryInput = ""
        selectedIncident = incidents[idx]
        saveIncidents()
    }

    func linkJiraTicket(appState: AppState) {
        let key = jiraKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty, let id = selectedIncident?.id,
              let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].jiraTicketKey = key
        incidents[idx].timeline.append(TimelineEntry(
            content: "Linked Jira ticket: \(key)",
            source: "jira"
        ))
        jiraKeyInput = ""
        selectedIncident = incidents[idx]
        saveIncidents()
    }

    func createJiraTicket(appState: AppState) async {
        guard let incident = selectedIncident, appState.isJiraConfigured else { return }
        isLinkingJira = true

        let priority: String
        switch incident.severity {
        case .p1: priority = "Highest"
        case .p2: priority = "High"
        case .p3: priority = "Medium"
        case .p4: priority = "Low"
        }

        let summary = "[\(incident.severity.label) INC] \(incident.title)"
        let description = buildJiraDescription(incident)
        let projectKey = appState.jiraProjectKeys.first ?? "CAMSRE"

        do {
            let key = try await createJiraIssue(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                token: appState.jiraAPIToken,
                projectKey: projectKey,
                summary: summary,
                description: description,
                priority: priority
            )
            if let id = incident.id as UUID?,
               let idx = incidents.firstIndex(where: { $0.id == id }) {
                incidents[idx].jiraTicketKey = key
                incidents[idx].timeline.append(TimelineEntry(
                    content: "Created Jira ticket: \(key)",
                    source: "jira"
                ))
                selectedIncident = incidents[idx]
                saveIncidents()
            }
        } catch {
            aiError = "Failed to create Jira ticket: \(error.localizedDescription)"
        }
        isLinkingJira = false
    }

    func deleteIncident(id: UUID, appState: AppState) {
        incidents.removeAll { $0.id == id }
        if selectedIncident?.id == id { selectedIncident = nil }
        saveIncidents()
        appState.activeIncidentCount = activeHighPriorityCount
    }

    // MARK: - AI Actions

    func analyzeIncident() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.discoverAPIKey() != nil else {
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
            // Save AI analysis to the incident
            if let id = incident.id as UUID?,
               let idx = incidents.firstIndex(where: { $0.id == id }) {
                incidents[idx].aiAnalysis = result
                incidents[idx].timeline.append(TimelineEntry(
                    content: "AI root cause analysis generated",
                    source: "ai"
                ))
                selectedIncident = incidents[idx]
                saveIncidents()
            }
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
    }

    func draftStatusUpdate() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.discoverAPIKey() != nil else {
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
    }

    func draftPostmortem() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.discoverAPIKey() != nil else {
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
    }

    func suggestRemediation() async {
        guard let incident = selectedIncident else { return }
        guard claudeService.discoverAPIKey() != nil else {
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
            lines.append("Affected Services: \(incident.affectedServices.joined(separator: ", "))")
        }
        if let key = incident.jiraTicketKey {
            lines.append("Jira Ticket: \(key) (https://boomii.atlassian.net/browse/\(key))")
        }
        if !incident.timeline.isEmpty {
            lines.append("\nTIMELINE (\(incident.timeline.count) entries):")
            let fmt = DateFormatter(); fmt.timeStyle = .short; fmt.dateStyle = .none
            for entry in incident.timeline {
                lines.append("  [\(fmt.string(from: entry.timestamp))] [\(entry.source.uppercased())] \(entry.content)")
            }
        }
        if let analysis = incident.aiAnalysis {
            lines.append("\nPREVIOUS AI ANALYSIS:\n\(analysis.prefix(500))")
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

    // MARK: - Jira Issue Creation

    private func createJiraIssue(
        baseURL: String, email: String, token: String,
        projectKey: String, summary: String, description: String, priority: String
    ) async throws -> String {
        let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/rest/api/3/issue")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        if let data = "\(email):\(token)".data(using: .utf8) {
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let adfDescription: [String: Any] = [
            "version": 1, "type": "doc",
            "content": [["type": "paragraph", "content": [["type": "text", "text": description]]]]
        ]
        let body: [String: Any] = [
            "fields": [
                "project": ["key": projectKey],
                "summary": summary,
                "description": adfDescription,
                "issuetype": ["name": "Bug"],
                "priority": ["name": priority]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "JiraCreate", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                         userInfo: [NSLocalizedDescriptionKey: body.prefix(300)])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String else {
            throw NSError(domain: "JiraCreate", code: 0,
                         userInfo: [NSLocalizedDescriptionKey: "Could not parse Jira issue key from response"])
        }
        return key
    }

    private func buildJiraDescription(_ incident: Incident) -> String {
        var parts = ["Incident: \(incident.title)", "Severity: \(incident.severity.label)"]
        if !incident.affectedServices.isEmpty {
            parts.append("Affected Services: \(incident.affectedServices.joined(separator: ", "))")
        }
        parts.append("Duration: \(incident.elapsedString)")
        if !incident.timeline.isEmpty {
            parts.append("\nTimeline:")
            let fmt = DateFormatter(); fmt.timeStyle = .short
            for entry in incident.timeline {
                parts.append("  [\(fmt.string(from: entry.timestamp))] \(entry.content)")
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func loadIncidents() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([Incident].self, from: data) else { return }
        incidents = decoded
    }

    private func saveIncidents() {
        if let data = try? JSONEncoder().encode(incidents) {
            try? data.write(to: historyURL)
        }
    }
}

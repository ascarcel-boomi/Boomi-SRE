import SwiftUI

/// Production Change Request generator sheet.
/// Loads SOPs from the KB GitHub repo and uses Claude to generate PCR content.
struct PCRGeneratorView: View {
    let ticketKey: String
    let ticketSummary: String
    let ticketPriority: String
    let ticketStatus: String
    let ticketAssignee: String
    let ticketDescription: String
    let ticketComments: [JiraComment]

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // SOP selection
    @State private var sopOptions: [SOPOption] = []
    @State private var selectedSOP: SOPOption? = nil
    @State private var isLoadingSOPs = false
    @State private var sopLoadError: String?

    // PCR fields (user-editable / AI-generated)
    @State private var changeDescription = ""
    @State private var justification = ""
    @State private var impactAssessment = ""
    @State private var rollbackPlan = ""
    @State private var testingPlan = ""
    @State private var scheduledDate = Date().addingTimeInterval(86400)
    @State private var estimatedDuration = "2 hours"
    @State private var riskLevel: RiskLevel = .medium

    // AI generation
    @State private var isGenerating = false
    @State private var generationError: String?

    // Actions
    @State private var showCopyConfirm = false
    @State private var isPostingComment = false
    @State private var actionMessage: String?
    @State private var actionIsError = false

    private let claudeService = ClaudeService()
    private let jiraService   = JiraService()

    enum RiskLevel: String, CaseIterable {
        case low      = "Low"
        case medium   = "Medium"
        case high     = "High"
        case critical = "Critical"

        var color: Color {
            switch self {
            case .low:      return .green
            case .medium:   return .yellow
            case .high:     return .orange
            case .critical: return .red
            }
        }
    }

    struct SOPOption: Identifiable, Hashable {
        let id: String     // file path
        let title: String
        let content: String

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: SOPOption, rhs: SOPOption) -> Bool { lhs.id == rhs.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(Color.accentColor)
                Text("Generate Production Change Request")
                    .font(.title3.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Ticket info (read-only)
                    ticketInfoSection

                    Divider()

                    // SOP picker
                    sopSection

                    Divider()

                    // AI generate button
                    aiGenerateSection

                    if let err = generationError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }

                    Divider()

                    // Editable PCR fields
                    pcrFieldsSection

                    Divider()

                    // Schedule / risk
                    scheduleSection

                    Divider()

                    // Actions
                    actionSection

                    if let msg = actionMessage {
                        HStack {
                            Image(systemName: actionIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            Text(msg).textSelection(.enabled)
                        }
                        .font(.callout)
                        .foregroundStyle(actionIsError ? .red : .green)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill((actionIsError ? Color.red : Color.green).opacity(0.1)))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            Task { await loadSOPs() }
        }
    }

    // MARK: - Ticket Info

    private var ticketInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ticket Information").font(.headline)
            HStack(spacing: 16) {
                infoRow("Ticket", value: ticketKey)
                infoRow("Priority", value: ticketPriority)
                infoRow("Status", value: ticketStatus)
                infoRow("Assignee", value: ticketAssignee)
            }
            Text(ticketSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.2)))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.tertiary)
            Text(value).font(.caption.bold())
        }
    }

    // MARK: - SOP Section

    private var sopSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Standard Operating Procedure").font(.headline)
                Spacer()
                if isLoadingSOPs {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { Task { await loadSOPs() } } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Reload SOPs from Knowledge Base")
                }
            }
            if let err = sopLoadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Picker("SOP", selection: $selectedSOP) {
                Text("Custom / No SOP").tag(Optional<SOPOption>.none)
                ForEach(sopOptions) { sop in
                    Text(sop.title).tag(Optional(sop))
                }
            }
            .labelsHidden()

            if let sop = selectedSOP {
                Text("SOP: \(sop.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.1)))
            }
        }
    }

    // MARK: - AI Generate

    private var aiGenerateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Generation").font(.headline)
            HStack {
                Button {
                    Task { await generateWithAI() }
                } label: {
                    Label(isGenerating ? "Generating…" : "Generate with AI",
                          systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                if isGenerating { ProgressView().scaleEffect(0.8) }

                Text("Claude will analyze the ticket and SOP to fill in all PCR fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - PCR Fields

    private var pcrFieldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PCR Details").font(.headline)

            labeledEditor("Change Description", text: $changeDescription,
                          placeholder: "Describe what change is being made…")
            labeledEditor("Justification / Business Reason", text: $justification,
                          placeholder: "Why is this change necessary?")
            labeledEditor("Impact Assessment", text: $impactAssessment,
                          placeholder: "Which services or customers are affected?")
            labeledEditor("Rollback Plan", text: $rollbackPlan,
                          placeholder: "How will you roll back if something goes wrong?")
            labeledEditor("Testing Plan", text: $testingPlan,
                          placeholder: "How will you verify the change succeeded?")
        }
    }

    private func labeledEditor(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout.bold()).foregroundStyle(.secondary)
            if text.wrappedValue.isEmpty {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: text)
                        .font(.body)
                        .frame(minHeight: 70)
                        .border(Color.secondary.opacity(0.3))
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            } else {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 70)
                    .border(Color.secondary.opacity(0.3))
            }
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule & Risk").font(.headline)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled Date/Time").font(.callout.bold()).foregroundStyle(.secondary)
                    DatePicker("", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated Duration").font(.callout.bold()).foregroundStyle(.secondary)
                    TextField("e.g. 2 hours", text: $estimatedDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Risk Level").font(.callout.bold()).foregroundStyle(.secondary)
                    Picker("Risk", selection: $riskLevel) {
                        ForEach(RiskLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions").font(.headline)
            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(buildPCRMarkdown(), forType: .string)
                    actionMessage = "PCR copied to clipboard"
                    actionIsError = false
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    isPostingComment = true
                    Task {
                        await postAsComment()
                        isPostingComment = false
                    }
                } label: {
                    Label(isPostingComment ? "Posting…" : "Post as Comment", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .disabled(isPostingComment)
            }
        }
    }

    // MARK: - Logic

    private func loadSOPs() async {
        guard !appState.githubToken.isEmpty else {
            sopLoadError = "GitHub token not configured — add it in Settings → GitHub"
            return
        }
        isLoadingSOPs = true
        sopLoadError = nil
        do {
            let service = GitHubService()
            let owner = appState.kbRepoOwner
            let repo  = appState.kbRepoName
            let token = appState.githubToken
            // Get tree
            let treeURL = "https://api.github.com/repos/\(owner)/\(repo)/git/trees/main?recursive=1"
            var req = URLRequest(url: URL(string: treeURL)!, timeoutInterval: 15)
            req.addBearerAuth(token: token)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (treeData, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: treeData) as? [String: Any],
                  let tree = json["tree"] as? [[String: Any]] else {
                isLoadingSOPs = false; return
            }
            // Filter SOPs
            let sopPaths = tree.compactMap { node -> String? in
                guard let path = node["path"] as? String,
                      path.hasPrefix("sops/") && path.hasSuffix(".md") else { return nil }
                return path
            }
            // Fetch each SOP content in parallel
            var options: [SOPOption] = []
            await withTaskGroup(of: SOPOption?.self) { group in
                for path in sopPaths {
                    group.addTask {
                        let contentURL = "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)"
                        var r = URLRequest(url: URL(string: contentURL)!, timeoutInterval: 15)
                        r.addBearerAuth(token: token)
                        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                        guard let (d, _) = try? await URLSession.shared.data(for: r),
                              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let encoded = j["content"] as? String else { return nil }
                        let decoded = encoded.replacingOccurrences(of: "\n", with: "")
                        guard let contentData = Data(base64Encoded: decoded),
                              let contentStr = String(data: contentData, encoding: .utf8) else { return nil }
                        // Extract title from first # heading or filename
                        let title: String
                        if let firstLine = contentStr.components(separatedBy: "\n").first(where: { $0.hasPrefix("# ") }) {
                            title = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        } else {
                            title = (path as NSString).lastPathComponent
                                .replacingOccurrences(of: ".md", with: "")
                                .replacingOccurrences(of: "-", with: " ")
                                .capitalized
                        }
                        return SOPOption(id: path, title: title, content: contentStr)
                    }
                }
                for await option in group {
                    if let opt = option { options.append(opt) }
                }
            }
            _ = service  // suppress unused warning
            sopOptions = options.sorted { $0.title < $1.title }
            isLoadingSOPs = false
        } catch {
            sopLoadError = error.localizedDescription
            isLoadingSOPs = false
        }
    }

    private func generateWithAI() async {
        guard claudeService.isAIAvailable else {
            generationError = "No Anthropic API key configured."
            return
        }
        isGenerating = true
        generationError = nil

        let ticketContext = """
        Ticket: \(ticketKey) — \(ticketSummary)
        Priority: \(ticketPriority) | Status: \(ticketStatus) | Assignee: \(ticketAssignee)
        Description: \(ticketDescription.prefix(1500))
        """
        let sopContext = selectedSOP.map {
            "SOP: \($0.title)\n\n\($0.content.prefix(3000))"
        } ?? "No SOP selected — generate based on ticket context alone."

        let pcrTemplate = buildPCRMarkdown()

        let prompt = """
        You are generating a Production Change Request (PCR) for a Boomi APIM SRE team change.

        TICKET CONTEXT:
        \(ticketContext)

        \(sopContext)

        CURRENT PCR TEMPLATE (fill in the bracketed fields):
        \(pcrTemplate)

        Generate each section of the PCR:
        1. CHANGE_DESCRIPTION: A precise technical description of what change is being made (2-3 sentences)
        2. JUSTIFICATION: Business/technical reason why this change is needed (1-2 sentences)
        3. IMPACT_ASSESSMENT: Affected services, customers, expected downtime (2-4 bullet points)
        4. ROLLBACK_PLAN: Specific, actionable steps to undo the change if needed (numbered steps)
        5. TESTING_PLAN: How to verify the change succeeded (numbered steps)
        6. RISK_LEVEL: One of: Low, Medium, High, Critical

        Respond in this exact format:
        CHANGE_DESCRIPTION: ...
        JUSTIFICATION: ...
        IMPACT_ASSESSMENT: ...
        ROLLBACK_PLAN: ...
        TESTING_PLAN: ...
        RISK_LEVEL: ...
        """

        do {
            let response = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an SRE generating a Production Change Request. Be thorough and conservative. The rollback plan must be specific and actionable. The risk assessment must consider blast radius and customer impact.",
                maxTokens: 2048
            )
            parseAIResponse(response)
        } catch {
            generationError = error.localizedDescription
        }
        isGenerating = false
    }

    private func parseAIResponse(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        var current: String = ""
        var buffer: [String] = []

        func flush() {
            let value = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            switch current {
            case "CHANGE_DESCRIPTION": changeDescription = value
            case "JUSTIFICATION": justification = value
            case "IMPACT_ASSESSMENT": impactAssessment = value
            case "ROLLBACK_PLAN": rollbackPlan = value
            case "TESTING_PLAN": testingPlan = value
            case "RISK_LEVEL":
                let v = value.trimmingCharacters(in: .whitespaces)
                if let rl = RiskLevel.allCases.first(where: { v.lowercased().contains($0.rawValue.lowercased()) }) {
                    riskLevel = rl
                }
            default: break
            }
            buffer = []
        }

        for line in lines {
            let keys = ["CHANGE_DESCRIPTION", "JUSTIFICATION", "IMPACT_ASSESSMENT",
                        "ROLLBACK_PLAN", "TESTING_PLAN", "RISK_LEVEL"]
            var matched = false
            for key in keys {
                if line.hasPrefix("\(key):") {
                    flush()
                    current = key
                    let value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { buffer.append(value) }
                    matched = true
                    break
                }
            }
            if !matched && !current.isEmpty {
                buffer.append(line)
            }
        }
        flush()
    }

    private func buildPCRMarkdown() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let dateStr = df.string(from: scheduledDate)
        let sopTitle = selectedSOP?.title ?? "Custom / No SOP"

        return """
        # Production Change Request

        **Ticket:** \(ticketKey) — \(ticketSummary)
        **SOP:** \(sopTitle)
        **Requested by:** \(ticketAssignee)
        **Date:** \(dateStr)
        **Estimated Duration:** \(estimatedDuration)

        ## Change Description
        \(changeDescription.isEmpty ? "(not yet generated)" : changeDescription)

        ## Justification
        \(justification.isEmpty ? "(not yet generated)" : justification)

        ## Procedure
        \(selectedSOP?.content.prefix(2000).description ?? "See SOP: \(sopTitle)")

        ## Impact Assessment
        \(impactAssessment.isEmpty ? "(not yet generated)" : impactAssessment)

        ## Risk Assessment
        - **Risk Level:** \(riskLevel.rawValue)

        ## Rollback Plan
        \(rollbackPlan.isEmpty ? "(not yet generated)" : rollbackPlan)

        ## Testing Plan
        \(testingPlan.isEmpty ? "(not yet generated)" : testingPlan)

        ## Approvals
        - [ ] SRE Lead
        - [ ] Service Owner
        - [ ] Change Manager
        """
    }

    private func postAsComment() async {
        guard appState.isJiraConfigured else {
            actionMessage = "Jira not configured"
            actionIsError = true
            return
        }
        actionMessage = nil
        do {
            try await jiraService.addComment(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                key: ticketKey,
                body: "[PCR] — Auto-generated by Boomi SRE\n\n\(buildPCRMarkdown())"
            )
            actionMessage = "PCR posted as comment on \(ticketKey)"
            actionIsError = false
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }
    }
}

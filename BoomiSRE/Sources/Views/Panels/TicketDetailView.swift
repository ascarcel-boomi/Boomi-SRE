import SwiftUI

struct TicketDetailView: View {
    let ticketKey: String
    let onDismiss: () -> Void

    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = TicketDetailViewModel()
    @State private var commentText = ""
    @State private var isAddingComment = false
    @State private var showAssignSearch = false
    @State private var assignSearchQuery = ""
    @State private var assignSearchResults: [JiraAssignableUser] = []
    @State private var selectedSection = "ai"
    @State private var showPCRGenerator = false

    private let jiraService = JiraService()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if viewModel.isLoading && viewModel.detail == nil {
                VStack { Spacer(); ProgressView("Loading \(ticketKey)..."); Spacer() }
            } else if let d = viewModel.detail {
                HSplitView {
                    // Left: section tabs
                    VStack(alignment: .leading, spacing: 2) {
                        sectionTab("ai", label: "AI Analysis", icon: "sparkles")
                        sectionTab("details", label: "Details", icon: "doc.text")
                        sectionTab("actions", label: "Actions", icon: "bolt.circle")
                        sectionTab("description", label: "Description", icon: "text.alignleft")
                        sectionTab("comments", label: "Comments (\(d.comments.count))", icon: "bubble.left.and.bubble.right")
                        sectionTab("subtasks", label: "Subtasks (\(d.subtasks.count))", icon: "list.bullet.indent")
                        sectionTab("devinfo", label: "PRs & Commits", icon: "chevron.left.forwardslash.chevron.right")
                        sectionTab("history", label: "History (\(d.history.count))", icon: "clock.arrow.circlepath")
                        Spacer()
                    }
                    .frame(width: 180)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))

                    // Right: content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ticketHeader(d)
                            messageBanner

                            switch selectedSection {
                            case "ai": aiAnalysisSection(d)
                            case "details": detailsSection(d)
                            case "actions": actionsSection(d)
                            case "description": descriptionSection(d)
                            case "comments": commentsSection(d)
                            case "subtasks": subtasksSection(d)
                            case "devinfo": devInfoSection
                            case "history": historySection(d)
                            default: EmptyView()
                            }
                        }
                        .padding(20)
                    }
                }
            } else if let msg = viewModel.actionMessage {
                VStack { Spacer(); Text(msg).foregroundStyle(.red).textSelection(.enabled); Spacer() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            Task {
                await viewModel.load(key: ticketKey, appState: appState)
                // Auto-analyze once ticket is loaded
                if viewModel.detail != nil && viewModel.aiAnalysis == nil {
                    await viewModel.analyzeWithAI()
                }
            }
        }
        .sheet(isPresented: $showPCRGenerator) {
            if let d = viewModel.detail {
                PCRGeneratorView(
                    ticketKey: d.key,
                    ticketSummary: d.summary,
                    ticketPriority: d.priority,
                    ticketStatus: d.status,
                    ticketAssignee: d.assignee,
                    ticketDescription: d.description,
                    ticketComments: d.comments
                )
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .buttonStyle(.plain)

            Spacer()

            if viewModel.detail != nil {
                Button {
                    showPCRGenerator = true
                } label: {
                    Label("Generate PCR", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .help("Generate a Production Change Request from this ticket")

                Button {
                    Task { await viewModel.load(key: ticketKey, appState: appState) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Link(destination: viewModel.detail!.url) {
                    Label("Open in Jira", systemImage: "safari")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Section tabs

    private func sectionTab(_ id: String, label: String, icon: String) -> some View {
        Button { selectedSection = id } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18)
                Text(label).font(.callout)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .fill(selectedSection == id ? Color.accentColor.opacity(0.15) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func ticketHeader(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(d.key).font(.title2.bold().monospaced())
                PillBadge(text: d.issueType, color: .blue)
                PillBadge(text: d.status, color: statusColor(d.statusCategory))
                PillBadge(text: d.priority, color: priorityColor(d.priority))
            }
            Text(d.summary).font(.title3)
        }
    }

    // MARK: - AI Analysis

    private func aiAnalysisSection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Analysis")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.analyzeWithAI() }
                } label: {
                    Label(viewModel.isAnalyzing ? "Analyzing..." : "Analyze",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(viewModel.isAnalyzing)
            }

            if viewModel.isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Claude is reviewing this ticket...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let analysis = viewModel.aiAnalysis {
                AIAnalysisBox(text: analysis, tintColor: .purple)

                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.postAnalysisAsComment(key: ticketKey, appState: appState) }
                    } label: {
                        Label("Post as Comment to Ticket", systemImage: "paperplane")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.lastCommentIsAIAnalysis)

                    if viewModel.lastCommentIsAIAnalysis {
                        Label("Last comment is already an AI analysis", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Divider()
                aiActionButtons(d)
            } else if let error = viewModel.aiError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(.orange.opacity(0.08)))
            } else {
                VStack(spacing: 8) {
                    Text("Click \"Analyze\" to get AI-powered insights on this ticket")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Claude will review the ticket details, comments, and history to provide current status and recommended next steps.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
            }
        }
        .sectionCard()
    }

    // MARK: - Details

    private func detailsSection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Key Details").font(.headline).padding(.bottom, 8)

            let rows: [(String, String)] = [
                ("Status", d.status),
                ("Priority", d.priority),
                ("Type", d.issueType),
                ("Assignee", d.assignee),
                ("Reporter", d.reporter),
                ("Creator", d.creator),
                ("Created", d.created),
                ("Updated", d.updated),
                ("Start Date", d.startDate.isEmpty ? "—" : d.startDate),
                ("Due Date", d.dueDate.isEmpty ? "—" : d.dueDate),
                ("Sprint", d.sprint?.name ?? "—"),
                ("Labels", d.labels.isEmpty ? "—" : d.labels.joined(separator: ", ")),
                ("Parent", d.parentKey.isEmpty ? "—" : "\(d.parentKey) — \(d.parentSummary)"),
            ]

            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    Text(row.1)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(i % 2 == 0 ? Color(nsColor: .controlBackgroundColor) : .clear)
            }
        }
        .sectionCard()
    }

    // MARK: - Actions

    private func actionsSection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Transitions
            VStack(alignment: .leading, spacing: 8) {
                Text("Change Status").font(.headline)
                HStack(spacing: 8) {
                    ForEach(viewModel.transitions) { t in
                        Button {
                            Task { await viewModel.transition(to: t, key: ticketKey, appState: appState) }
                        } label: {
                            Label(t.name, systemImage: transitionIcon(t))
                        }
                        .buttonStyle(.bordered)
                        .tint(transitionColor(t))
                    }
                }
            }
            .sectionCard()

            // Assignment
            VStack(alignment: .leading, spacing: 8) {
                Text("Assignment").font(.headline)
                Text("Currently: \(d.assignee)").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        Task { await viewModel.assignToMe(key: ticketKey, appState: appState) }
                    } label: {
                        Label("Assign to Me", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button { showAssignSearch.toggle() } label: {
                        Label("Assign...", systemImage: "person.2")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showAssignSearch) { assignPopover }
                }
            }
            .sectionCard()

            // Add comment
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Comment").font(.headline)
                TextEditor(text: $commentText)
                    .font(.body).frame(minHeight: 80, maxHeight: 150)
                    .border(Color.secondary.opacity(0.3))
                HStack {
                    Button {
                        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        isAddingComment = true
                        let text = commentText; commentText = ""
                        Task {
                            await viewModel.addComment(text: text, key: ticketKey, appState: appState)
                            isAddingComment = false
                        }
                    } label: {
                        Label("Post Comment", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingComment)
                    if isAddingComment { ProgressView().scaleEffect(0.7) }
                }
            }
            .sectionCard()
        }
    }

    // MARK: - Description

    private func descriptionSection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description").font(.headline)
            if d.description.isEmpty {
                Text("No description").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(d.description)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sectionCard()
    }

    // MARK: - Comments

    private func commentsSection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comments (\(d.comments.count))").font(.headline)
            if d.comments.isEmpty {
                Text("No comments").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(d.comments) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.authorName).font(.callout.bold())
                            Spacer()
                            Text(c.created).font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(c.bodyText).font(.body).textSelection(.enabled)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
        }
        .sectionCard()
    }

    // MARK: - Subtasks

    private func subtasksSection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtasks / Child Issues (\(d.subtasks.count))").font(.headline)
            if d.subtasks.isEmpty {
                Text("No subtasks").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(d.subtasks.enumerated()), id: \.offset) { _, st in
                    HStack(spacing: 10) {
                        Button(st.key) {
                            appState.selectedTicketKey = st.key
                        }
                        .buttonStyle(.plain)
                        .font(.body.monospaced().bold())
                        .foregroundStyle(.blue)
                        .frame(width: 130, alignment: .leading)

                        Text(st.summary)
                            .font(.body)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(st.status)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.secondary.opacity(0.15)))
                    }
                    .padding(.vertical, 4)
                }
            }

            if !d.parentKey.isEmpty {
                Divider()
                HStack(spacing: 10) {
                    Text("Parent:").font(.callout).foregroundStyle(.secondary)
                    Button(d.parentKey) {
                        appState.selectedTicketKey = d.parentKey
                    }
                    .buttonStyle(.plain)
                    .font(.body.monospaced().bold())
                    .foregroundStyle(.blue)
                    Text(d.parentSummary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .sectionCard()
    }

    // MARK: - Dev Info (PRs & Commits)

    private var devInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let dev = viewModel.devInfo {
                // Pull Requests
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pull Requests (\(dev.pullRequests.count))").font(.headline)
                    if dev.pullRequests.isEmpty {
                        Text("No linked pull requests").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(dev.pullRequests) { pr in
                            HStack(spacing: 10) {
                                Image(systemName: prStatusIcon(pr.status))
                                    .foregroundStyle(prStatusColor(pr.status))
                                VStack(alignment: .leading, spacing: 2) {
                                    Link(pr.name, destination: URL(string: pr.url)!)
                                        .font(.body.bold())
                                    HStack(spacing: 8) {
                                        Text(pr.status)
                                            .font(.caption)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(prStatusColor(pr.status).opacity(0.15)))
                                            .foregroundStyle(prStatusColor(pr.status))
                                        Text("\(pr.sourceBranch) → \(pr.destBranch)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("by \(pr.author)")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .sectionCard()

                // Commits
                VStack(alignment: .leading, spacing: 8) {
                    Text("Commits (\(dev.commits.count))").font(.headline)
                    if dev.commits.isEmpty {
                        Text("No linked commits").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(dev.commits) { commit in
                            HStack(spacing: 10) {
                                Text(commit.hash)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Link(commit.message.prefix(80) + (commit.message.count > 80 ? "..." : ""),
                                         destination: URL(string: commit.url)!)
                                        .font(.callout)
                                    HStack {
                                        Text(commit.author).font(.caption).foregroundStyle(.secondary)
                                        Text(commit.date).font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .sectionCard()
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading dev info...").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    private func prStatusIcon(_ status: String) -> String {
        switch status.uppercased() {
        case "MERGED": return "checkmark.circle.fill"
        case "OPEN": return "arrow.triangle.pull"
        case "DECLINED": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private func prStatusColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "MERGED": return .purple
        case "OPEN": return .green
        case "DECLINED": return .red
        default: return .secondary
        }
    }

    // MARK: - History

    private func historySection(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History / Audit Trail (\(d.history.count) changes)").font(.headline)
            if d.history.isEmpty {
                Text("No history available").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(d.history) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.date)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 130, alignment: .leading)
                        Text(entry.author)
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                        Text(entry.field)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .frame(width: 100, alignment: .leading)
                        if !entry.from.isEmpty || !entry.to.isEmpty {
                            Text(entry.from.isEmpty ? "—" : entry.from)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.to.isEmpty ? "—" : entry.to)
                                .font(.caption)
                                .foregroundStyle(.green)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .sectionCard()
    }

    // MARK: - Assign popover

    private var assignPopover: some View {
        VStack(spacing: 8) {
            TextField("Search users...", text: $assignSearchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { searchUsers() }
            if assignSearchResults.isEmpty {
                Text("Type a name and press Enter").font(.caption).foregroundStyle(.secondary).padding()
            } else {
                List(assignSearchResults) { user in
                    Button {
                        Task {
                            await viewModel.assign(accountId: user.accountId, key: ticketKey, appState: appState)
                            showAssignSearch = false
                        }
                    } label: { Text(user.displayName) }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }

    private func searchUsers() {
        Task {
            assignSearchResults = (try? await jiraService.searchUsers(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, query: assignSearchQuery)) ?? []
        }
    }

    // MARK: - Message banner

    @ViewBuilder
    private var messageBanner: some View {
        if let msg = viewModel.actionMessage {
            HStack {
                Image(systemName: viewModel.actionIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                Text(msg).textSelection(.enabled)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(viewModel.actionIsError ? .red : .green)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .fill((viewModel.actionIsError ? Color.red : Color.green).opacity(0.1)))
        }
    }

    // MARK: - AI Extended Action Buttons

    @State private var followUpInput: String = ""

    @ViewBuilder
    private func aiActionButtons(_ d: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Action button row
            Text("AI Actions")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    aiActionButton("Draft Comment",      icon: "bubble.left",
                        loading: viewModel.isGeneratingDraft && viewModel.draftedContentType == "Draft Comment") {
                        Task { await viewModel.draftComment() }
                    }
                    aiActionButton("Draft PR Desc",      icon: "arrow.triangle.branch",
                        loading: viewModel.isGeneratingDraft && viewModel.draftedContentType == "Draft PR Description") {
                        Task { await viewModel.draftPRDescription() }
                    }
                    aiActionButton("Estimate Effort",    icon: "chart.bar.xaxis",
                        loading: viewModel.isGeneratingDraft && viewModel.draftedContentType == "Effort Estimate") {
                        Task { await viewModel.estimateEffort() }
                    }
                    aiActionButton("Generate Subtasks",  icon: "list.bullet.indent",
                        loading: viewModel.isGeneratingDraft && viewModel.draftedContentType == "Suggested Subtasks") {
                        Task { await viewModel.generateSubtasks() }
                    }
                }
            }

            // Draft error
            if let err = viewModel.draftError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            // Draft result
            if let content = viewModel.draftedContent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(viewModel.draftedContentType ?? "Draft")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy to clipboard")
                        Button { viewModel.draftedContent = nil } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear")
                    }
                    MarkdownView(markdown: content)
                        .frame(minHeight: 200)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.accentColor.opacity(0.05)))
                }
            }

            Divider()

            // Follow-up conversation
            Text("Ask a Follow-up Question")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            // Conversation history
            if !viewModel.followUpHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(viewModel.followUpHistory.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q: \(entry.question)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            InlineMarkdownText(text: entry.answer)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if viewModel.followUpHistory.last?.question != entry.question { Divider() }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.secondary.opacity(0.05)))
            }

            // Follow-up input row
            HStack(spacing: 8) {
                TextField("Ask anything about this ticket…", text: $followUpInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let q = followUpInput
                        followUpInput = ""
                        Task { await viewModel.askFollowUp(question: q) }
                    }
                    .disabled(viewModel.isAnsweringFollowUp)

                if viewModel.isAnsweringFollowUp {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        let q = followUpInput
                        followUpInput = ""
                        Task { await viewModel.askFollowUp(question: q) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(followUpInput.isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(followUpInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func aiActionButton(_ title: String, icon: String, loading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if loading {
                    Label("…", systemImage: icon)
                } else {
                    Label(title, systemImage: icon)
                }
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isGeneratingDraft)
    }

    // MARK: - Helpers

    private func transitionIcon(_ t: JiraTransition) -> String {
        switch t.toCategory {
        case "In Progress": return "play.circle"
        case "Done": return "checkmark.circle"
        case "To Do": return "circle"
        default: return "arrow.right.circle"
        }
    }
    private func transitionColor(_ t: JiraTransition) -> Color {
        switch t.toCategory {
        case "In Progress": return .blue; case "Done": return .green
        case "To Do": return .orange; default: return .secondary
        }
    }
    private func statusColor(_ name: String) -> Color {
        switch name {
        case "In Progress": return .blue; case "To Do": return .orange
        case "Done": return .green; default: return .secondary
        }
    }
    private func priorityColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "highest": return .red; case "high": return .orange
        case "medium": return .yellow; case "low": return .blue
        case "lowest": return .gray; default: return .secondary
        }
    }
}

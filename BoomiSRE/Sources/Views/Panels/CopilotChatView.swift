import SwiftUI

struct CopilotChatView: View {
    @EnvironmentObject var appState: AppState
    @Environment(ChatViewModel.self) var viewModel
    @Environment(SkillsViewModel.self) var skillsVM
    @FocusState private var isInputFocused: Bool
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showSkillsBrowser = false

    var body: some View {
        @Bindable var viewModel = viewModel
        @Bindable var skillsVM = skillsVM
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Label("AI Copilot", systemImage: "sparkles")
                    .font(.title3.bold())
                Spacer()
                if !viewModel.messages.isEmpty {
                    Button {
                        viewModel.clearHistory()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // AI Preferences summary bar
            aiPreferencesBar

            Divider()

            // Context chips bar
            contextChipsBar

            Divider()

            // Messages list
            if viewModel.messages.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                messageRow(msg)
                                    .id(msg.id)
                            }
                            if viewModel.isGatheringContext {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Gathering context…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 12)
                                .id("gathering")
                            }
                            if viewModel.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Thinking…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 12)
                                .id("loading")
                            }
                            // Scroll anchor
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: viewModel.messages.count) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: viewModel.isLoading) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }

            // Error banner
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { viewModel.error = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }

            Divider()

            // Input bar
            inputBar
        }
        .onAppear {
            isInputFocused = true
            // Accept pre-filled prompt from feed actions (e.g. "Investigate" / "Start Incident")
            if let prompt = appState.pendingCopilotPrompt {
                viewModel.activeContextTypes = [.jiraTickets, .grafanaAlerts, .jenkinsBuilds]
                viewModel.inputText = prompt
                appState.pendingCopilotPrompt = nil
            }
        }
    }

    // MARK: - AI Preferences Bar

    private var aiPreferencesBar: some View {
        HStack(spacing: 6) {
            // Model badge
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundStyle(appState.themeAccent)
                Text(shortModelName)
                    .font(.caption.bold())
                    .foregroundStyle(appState.themeAccent)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(appState.themeAccent.opacity(0.12)))

            // Separator
            Text("·").font(.caption2).foregroundStyle(.tertiary)

            // Analysis depth badge
            HStack(spacing: 4) {
                Image(systemName: analysisDepthIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(appState.analysisDepth.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.08)))

            // Auto-context indicator
            if appState.autoContextEnabled {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("Auto")
                        .font(.caption)
                }
                .foregroundStyle(appState.themeSuccess)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(appState.themeSuccess.opacity(0.10)))
            }

            Spacer()

            Button {
                appState.showSettings = true
                appState.selectedSettingsTab = "ai"
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                    Text("Customize")
                        .font(.caption)
                }
                .foregroundStyle(appState.themeAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(appState.appTheme == "boomi" ? BoomiColors.boomiPurple.opacity(0.04) : Color.clear)
    }

    private var shortModelName: String {
        let m = appState.claudeModel
        if m.contains("opus") { return "Opus" }
        if m.contains("haiku") { return "Haiku" }
        return "Sonnet"
    }

    private var analysisDepthIcon: String {
        switch appState.analysisDepth {
        case "brief":    return "gauge.with.dots.needle.33percent"
        case "thorough": return "gauge.with.dots.needle.100percent"
        default:         return "gauge.with.dots.needle.67percent"
        }
    }

    // MARK: - Context Chips Bar

    private var contextChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Context:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(ContextType.allCases, id: \.self) { type in
                    ContextChip(
                        type: type,
                        isActive: viewModel.activeContextTypes.contains(type),
                        label: viewModel.contextLabels[type]
                    ) {
                        if viewModel.activeContextTypes.contains(type) {
                            viewModel.activeContextTypes.remove(type)
                        } else {
                            viewModel.activeContextTypes.insert(type)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("AI Copilot")
                    .font(.title2.bold())
                Text("Ask anything about your tickets, costs, meetings, and infrastructure.\nUse the context chips above to include live data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Quick action grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick actions:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(QuickAction.allCases, id: \.self) { action in
                        Button {
                            viewModel.executeQuickAction(action)
                            isInputFocused = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                Text(action.rawValue)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 500)

            // Skills section
            if !skillsVM.skills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Skills:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(skillsVM.frequentSkills.prefix(4)) { skill in
                            Button {
                                if skill.variables.isEmpty {
                                    // No variables — run directly
                                    viewModel.inputText = skill.promptTemplate
                                    isInputFocused = true
                                    var updated = skill
                                    updated.useCount += 1
                                    updated.lastUsedAt = Date()
                                    skillsVM.updateSkill(updated)
                                } else {
                                    skillsVM.prepareToRun(skill)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: skill.icon)
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                    Text(skill.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.purple.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        showSkillsBrowser = true
                    } label: {
                        Text("See all skills →")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .frame(maxWidth: 500)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: Bindable(skillsVM).isRunnerPresented) {
            SkillRunnerSheet(skillsVM: skillsVM, chatVM: viewModel)
                .environmentObject(appState)
        }
        .sheet(isPresented: Bindable(skillsVM).isEditorPresented) {
            SkillEditorSheet(skillsVM: skillsVM)
        }
        .sheet(isPresented: $showSkillsBrowser) {
            SkillsManagerView()
                .environmentObject(appState)
                .environment(skillsVM)
                .environment(viewModel)
                .frame(minWidth: 700, minHeight: 500)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(alignment: .bottom, spacing: 8) {
            // Quick actions menu
            Menu {
                ForEach(QuickAction.allCases, id: \.self) { action in
                    Button {
                        viewModel.executeQuickAction(action)
                        isInputFocused = true
                    } label: {
                        Label(action.rawValue, systemImage: action.icon)
                    }
                }

                Divider()

                // Skills submenu
                Menu("Skills") {
                    ForEach(skillsVM.frequentSkills.prefix(6)) { skill in
                        Button {
                            if skill.variables.isEmpty {
                                viewModel.inputText = skill.promptTemplate
                                isInputFocused = true
                            } else {
                                skillsVM.prepareToRun(skill)
                            }
                        } label: {
                            Label(skill.name, systemImage: skill.icon)
                        }
                    }
                    Divider()
                    Button {
                        showSkillsBrowser = true
                    } label: {
                        Label("All Skills…", systemImage: "list.bullet")
                    }
                }

                // Save conversation as skill
                if let firstUserMsg = viewModel.messages.first(where: { $0.role == .user }) {
                    Divider()
                    Button {
                        skillsVM.createSkillFromMessage(firstUserMsg.content)
                    } label: {
                        Label("Save as Skill…", systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "bolt.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Quick actions & skills")
            .accessibilityLabel("Quick actions and skills")

            // Text input
            TextField("Ask anything about your SRE environment…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit {
                    if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Send button
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || viewModel.isLoading
                || viewModel.isGatheringContext
            )
            .help("Send (Return)")
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Message Row Dispatcher

    @ViewBuilder
    private func messageRow(_ msg: CopilotMessage) -> some View {
        switch msg.role {
        case .user, .assistant:
            MessageBubble(message: msg)
        case .system:
            if let event = msg.toolEvent {
                ToolEventChip(event: event)
                    .padding(.leading, 12)
            } else if let action = msg.pendingAction {
                CommentConfirmationCard(
                    action: action,
                    isLoading: viewModel.isLoading,
                    onConfirm: {
                        let state = appState
                        Task { await viewModel.confirmPostComment(appState: state) }
                    },
                    onCancel: {
                        let state = appState
                        Task { await viewModel.cancelPostComment(appState: state) }
                    }
                )
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Helpers

    private func sendMessage() {
        let state = appState
        Task { await viewModel.send(appState: state) }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: CopilotMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Context sources chips (for user messages with context)
                if !message.contextSources.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.contextSources) { source in
                            Label(source.label, systemImage: source.type.icon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                                .help(source.summary)
                        }
                    }
                }

                // Message content
                if message.role == .assistant {
                    // Assistant messages use full MarkdownView for proper headings, lists, code blocks
                    MarkdownView(markdown: message.content)
                        .frame(minHeight: max(60, CGFloat(message.content.components(separatedBy: "\n").count) * 20))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    InlineMarkdownText(text: message.content, font: .body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Timestamp
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return Color(nsColor: .controlBackgroundColor)
        case .system: return .clear
        }
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .primary
    }

    private var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: message.timestamp)
    }
}

// MARK: - Tool Event Chip

private struct ToolEventChip: View {
    let event: ToolCallEvent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(iconColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let detail = event.detail, event.succeeded, event.eventType == .postedComment {
                if let url = URL(string: detail) {
                    Link("View in Jira ↗", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch event.eventType {
        case .fetchedTicket:    return event.succeeded ? "arrow.down.circle" : "exclamationmark.circle"
        case .postedComment:    return "checkmark.circle.fill"
        case .commentCancelled: return "xmark.circle"
        case .commentFailed:    return "exclamationmark.triangle.fill"
        case .fetchedAlerts:    return "bell.badge"
        case .fetchedBuilds:    return "hammer"
        case .searchedDocs:     return "doc.text.magnifyingglass"
        case .fetchedOnCall:    return "person.2.badge.clock"
        case .fetchedCosts:     return "dollarsign.circle"
        case .fetchedInstances: return "server.rack"
        case .searchedJira:     return "magnifyingglass"
        case .createdTicket:    return "plus.circle.fill"
        }
    }

    private var iconColor: Color {
        switch event.eventType {
        case .fetchedTicket:    return event.succeeded ? Color.accentColor : .red
        case .postedComment:    return .green
        case .commentCancelled: return .secondary
        case .commentFailed:    return .red
        case .fetchedAlerts:    return .orange
        case .fetchedBuilds:    return .blue
        case .searchedDocs:     return .purple
        case .fetchedOnCall:    return .teal
        case .fetchedCosts:     return .green
        case .fetchedInstances: return .indigo
        case .searchedJira:     return .blue
        case .createdTicket:    return .green
        }
    }

    private var label: String {
        switch event.eventType {
        case .fetchedTicket:
            return event.succeeded
                ? "Fetched \(event.ticketKey) from Jira"
                : "Failed to fetch \(event.ticketKey)"
        case .postedComment:
            return "Comment posted to \(event.ticketKey)"
        case .commentCancelled:
            return "Comment to \(event.ticketKey) cancelled"
        case .commentFailed:
            return "Failed to post to \(event.ticketKey)"
        case .fetchedAlerts:
            return "Checked Grafana alerts"
        case .fetchedBuilds:
            return "Checked Jenkins builds"
        case .searchedDocs:
            return "Searched Confluence: \"\(event.ticketKey)\""
        case .fetchedOnCall:
            return "Checked on-call schedules"
        case .fetchedCosts:
            return "Fetched AWS costs"
        case .fetchedInstances:
            return "Checked AWS infrastructure"
        case .searchedJira:
            return "Searched Jira: \"\(event.ticketKey)\""
        case .createdTicket:
            return event.succeeded
                ? "Created ticket \(event.ticketKey)"
                : "Failed to create ticket"
        }
    }

    private var backgroundColor: Color {
        switch event.eventType {
        case .fetchedTicket:    return Color.accentColor.opacity(0.08)
        case .postedComment:    return Color.green.opacity(0.10)
        case .commentCancelled: return Color.secondary.opacity(0.10)
        case .commentFailed:    return Color.red.opacity(0.08)
        case .fetchedAlerts:    return Color.orange.opacity(0.08)
        case .fetchedBuilds:    return Color.blue.opacity(0.08)
        case .searchedDocs:     return Color.purple.opacity(0.08)
        case .fetchedOnCall:    return Color.teal.opacity(0.08)
        case .fetchedCosts:     return Color.green.opacity(0.08)
        case .fetchedInstances: return Color.indigo.opacity(0.08)
        case .searchedJira:     return Color.blue.opacity(0.08)
        case .createdTicket:    return Color.green.opacity(0.08)
        }
    }
}

// MARK: - Comment Confirmation Card

private struct CommentConfirmationCard: View {
    let action: PendingCommentConfirmation
    let isLoading: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Post comment to Jira?")
                        .font(.subheadline.bold())
                    if let url = URL(string: "https://boomii.atlassian.net/browse/\(action.ticketKey)") {
                        Link(action.ticketKey, destination: url)
                            .font(.caption)
                    }
                }
                Spacer()
            }

            Divider()

            // Comment preview (markdown rendered)
            ScrollView {
                InlineMarkdownText(text: action.commentMarkdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            Divider()

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(isLoading)

                Button(action: onConfirm) {
                    Group {
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Post to Jira", systemImage: "paperplane.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.vertical, 7)
                .background(isLoading ? Color.secondary : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(isLoading)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

}

// MARK: - Context Chip

private struct ContextChip: View {
    let type: ContextType
    let isActive: Bool
    let label: String?
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.caption)
                Text(label ?? type.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

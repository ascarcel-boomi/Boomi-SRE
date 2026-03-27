import SwiftUI

struct AIBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatVM: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            collapsedBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .focusAIBar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isInputFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIBar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            if isExpanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isInputFocused = true }
            } else {
                isInputFocused = false
            }
        }
        .onExitCommand {
            // Escape key collapses the bar
            if isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                isInputFocused = false
            }
        }
    }

    // MARK: - Collapsed bar (always visible)

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)

            TextField("Ask anything... (⌘/)", text: $chatVM.inputText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isInputFocused)
                .onSubmit {
                    Task { await chatVM.send(appState: appState) }
                }

            if chatVM.isLoading || chatVM.isGatheringContext {
                ProgressView().scaleEffect(0.6)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse chat" : "Expand chat history")
            .accessibilityLabel(isExpanded ? "Collapse chat" : "Expand chat history")

            if !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await chatVM.send(appState: appState) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(chatVM.isLoading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Expanded view (chat history)

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI Copilot")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !chatVM.messages.isEmpty {
                    Button("Clear") { chatVM.clearHistory() }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            Divider()

            if chatVM.messages.isEmpty {
                Text("Ask me anything about your infrastructure, tickets, alerts, or procedures.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(chatVM.messages) { msg in
                                compactMessageRow(msg).id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .onChange(of: chatVM.messages.count) {
                        if let last = chatVM.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMsg = chatVM.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                    Text(errorMsg).font(.caption).foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
        .frame(maxHeight: 300)
    }

    // MARK: - Compact message row

    private func compactMessageRow(_ msg: CopilotMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.caption).foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "sparkles")
                    .font(.caption).foregroundStyle(.purple)
            }
            Text(msg.content)
                .font(.caption)
                .foregroundStyle(msg.role == .user ? Color.primary : Color.secondary)
                .textSelection(.enabled)
                .lineLimit(msg.role == .user ? 2 : 8)
        }
    }
}

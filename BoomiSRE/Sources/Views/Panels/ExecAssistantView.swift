import SwiftUI

struct ExecAssistantView: View {
    @EnvironmentObject var appState: AppState
    @Environment(NotificationViewModel.self) var notificationVM
    @State private var viewModel = ExecAssistantViewModel()
    @State private var selectedBriefing: Briefing?
    @State private var showingDetail = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Executive Assistant", systemImage: "person.crop.circle.badge.clock")
                    .font(.title3.bold())
                Spacer()
                generateAllButton
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Card grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(BriefingType.allCases, id: \.self) { type in
                        BriefingCard(
                            type: type,
                            lastBriefing: viewModel.lastBriefing(of: type),
                            isGenerating: viewModel.isGenerating[type] ?? false,
                            error: viewModel.errors[type],
                            onGenerate: {
                                let state = appState
                                Task { await generate(type: type, appState: state) }
                            },
                            onOpen: { briefing in
                                viewModel.markAsRead(briefing, appState: appState)
                                selectedBriefing = briefing
                                showingDetail = true
                            }
                        )
                    }
                }
                .padding(14)
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let briefing = selectedBriefing {
                BriefingDetailView(briefing: briefing, onRegenerate: {
                    showingDetail = false
                    let state = appState
                    Task { await generate(type: briefing.type, appState: state) }
                })
            }
        }
        .onAppear {
            appState.unreadBriefingCount = viewModel.unreadCount
            viewModel.notificationVM = notificationVM
        }
    }

    // MARK: - Generate All Button

    private var generateAllButton: some View {
        let isAnyGenerating = BriefingType.allCases.contains { viewModel.isGenerating[$0] ?? false }
        return Button {
            let state = appState
            Task { await viewModel.generateAll(appState: state) }
        } label: {
            if isAnyGenerating {
                Label("Generating…", systemImage: "arrow.clockwise")
                    .font(.caption)
            } else {
                Label("Generate All", systemImage: "sparkles")
                    .font(.caption)
            }
        }
        .disabled(isAnyGenerating)
    }

    // MARK: - Dispatch to correct generate method

    private func generate(type: BriefingType, appState: AppState) async {
        switch type {
        case .morningBrief:    await viewModel.generateMorningBrief(appState: appState)
        case .emailTriage:     await viewModel.generateEmailTriage(appState: appState)
        case .preMeetingBrief: await viewModel.generatePreMeetingBrief(appState: appState)
        case .actionTracker:   await viewModel.generateActionTracker(appState: appState)
        case .eodDigest:       await viewModel.generateEODDigest(appState: appState)
        case .dailyTicketBrief: await viewModel.generateDailyTicketBrief(appState: appState)
        case .claudeUsage:     await viewModel.generateClaudeUsage(appState: appState)
        }
    }
}

// MARK: - Briefing Card

private struct BriefingCard: View {
    let type: BriefingType
    let lastBriefing: Briefing?
    let isGenerating: Bool
    let error: String?
    let onGenerate: () -> Void
    let onOpen: (Briefing) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon + title row
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(type.title)
                            .font(.subheadline.bold())
                        if let b = lastBriefing, !b.isRead {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                        }
                    }
                    if let b = lastBriefing {
                        Text(relativeTime(b.generatedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not yet generated")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }

            // Preview or description
            if let b = lastBriefing {
                Button {
                    onOpen(b)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(previewText(b.content))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isHovered {
                            Label("View Report", systemImage: "arrow.right.circle.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Error
            if let err = error {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Generate button
            Button(action: onGenerate) {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(lastBriefing == nil ? "Generate" : "Regenerate",
                          systemImage: lastBriefing == nil ? "sparkles" : "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(isGenerating ? .secondary : Color.accentColor)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(isGenerating ? 0.05 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(isGenerating)
        }
        .padding(12)
        .frame(minHeight: 160)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.85) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered && lastBriefing != nil ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15), lineWidth: isHovered && lastBriefing != nil ? 1.5 : 1)
        )
        .scaleEffect(isHovered && lastBriefing != nil ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60  { return "Just now" }
        if diff < 3600 {
            let m = Int(diff / 60)
            return "\(m)m ago"
        }
        if diff < 86400 {
            let h = Int(diff / 3600)
            return "\(h)h ago"
        }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        return df.string(from: date)
    }

    private func previewText(_ markdown: String) -> String {
        // Strip markdown markers for preview
        markdown
            .replacingOccurrences(of: "#+ ", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "^- ", with: "• ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Briefing Detail View

private struct BriefingDetailView: View {
    let briefing: Briefing
    let onRegenerate: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: briefing.type.icon)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(briefing.title)
                            .font(.headline)
                        Text(timestampStr)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(briefing.content, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy to clipboard")

                    Button {
                        onRegenerate()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .help("Regenerate this briefing")

                    Button("Done") { dismiss() }
                        .keyboardShortcut(.escape)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content — MarkdownView is a WKWebView that handles its own scrolling
            MarkdownView(markdown: briefing.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)

            // Context summary footer
            if !briefing.contextSummary.isEmpty {
                Divider()
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Based on: \(briefing.contextSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 640, minHeight: 500)
    }

    private var timestampStr: String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        return "Generated \(df.string(from: briefing.generatedAt))"
    }
}

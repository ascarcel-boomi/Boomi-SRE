import SwiftUI

/// Detail pane for the notification HSplitView right side.
struct NotificationDetailPane: View {
    let notification: SRENotification
    @EnvironmentObject var appState: AppState
    @State private var viewModel = NotificationDetailViewModel()

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                // Header card — always visible from metadata
                headerCard
                Divider()
                // Rich content — enriched by API data when available
                detailContent
                // Error
                if let err = viewModel.loadError {
                    errorView(err)
                }
                // AI analysis — available for all types
                aiSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .task(id: notification.id) {
            await viewModel.loadDetail(for: notification, appState: appState)
            // Safety net: bounce window appearance to flush any types where
            // @Observable property tracking doesn't trigger a CALayer update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                let saved = window.appearance
                window.appearance = NSAppearance(named: .aqua)
                DispatchQueue.main.async { window.appearance = saved }
            }
        }
    }

    // MARK: - Shared Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: notification.type.icon)
                    .font(.title2)
                    .foregroundStyle(notification.type.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.title3.bold())
                        .lineLimit(3)
                    Text(notification.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                externalLink
            }

            Text(notification.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            HStack(spacing: 10) {
                typeBadge
                Text(notification.relativeTime)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }

    @ViewBuilder
    private var externalLink: some View {
        switch notification.type {
        case .jenkinsBuildFailed, .jenkinsBuildRecovered:
            if let url = notification.metadata["buildURL"].flatMap({ URL(string: $0) }) {
                Link(destination: url) {
                    Label("Open in Jenkins", systemImage: "safari").font(.caption)
                }
            }
        case .jiraAssigned, .jiraStatusChange, .jiraNewComment, .jiraMentioned:
            if let key = notification.metadata["ticketKey"], !key.isEmpty {
                HStack(spacing: 8) {
                    if let url = URL(string: "\(appState.jiraBaseURL)/browse/\(key)") {
                        Link(destination: url) {
                            Label("Open in Jira", systemImage: "safari").font(.caption)
                        }
                    }
                    Button("View Full Ticket") {
                        appState.pushNavigation()
                        appState.selectedTicketKey = key
                    }
                    .font(.caption).buttonStyle(.bordered)
                }
            }
        case .githubPRReview, .githubPRMerged, .githubWorkflowFailed:
            if let url = notification.metadata["htmlURL"].flatMap({ URL(string: $0) }) {
                Link(destination: url) {
                    Label("Open on GitHub", systemImage: "safari").font(.caption)
                }
            }
        case .confluencePageUpdated:
            if let url = notification.metadata["pageURL"].flatMap({ URL(string: $0) }) {
                Link(destination: url) {
                    Label("Open in Confluence", systemImage: "safari").font(.caption)
                }
            }
        case .grafanaAlertFiring, .grafanaAlertResolved:
            if !appState.grafanaURL.isEmpty, let url = URL(string: appState.grafanaURL) {
                Link(destination: url) {
                    Label("Open Grafana", systemImage: "safari").font(.caption)
                }
            }
        case .briefingGenerated:
            Button("View Full Briefing") {
                appState.selectedReport = ReportCatalog.all.first { $0.id == "exec_assistant" }
                appState.showSettings = false
            }
            .font(.caption).buttonStyle(.bordered)
        case .awsCostAnomaly:
            Button("Open Cost Explorer") {
                appState.selectedReport = ReportCatalog.all.first { $0.id == "aws_cost_explorer" }
                appState.showSettings = false
            }
            .font(.caption).buttonStyle(.bordered)
        case .appUpdate:
            Button("Open Settings") { appState.showSettings = true }
                .font(.caption).buttonStyle(.bordered)
        }
    }

    private var typeBadge: some View {
        Text(notification.type.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(notification.type.color.opacity(0.12))
            .foregroundStyle(notification.type.color)
            .clipShape(Capsule())
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg).font(.callout).foregroundStyle(.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch notification.type {
        case .jenkinsBuildFailed, .jenkinsBuildRecovered:
            jenkinsDetailView
        case .jiraAssigned, .jiraStatusChange, .jiraNewComment, .jiraMentioned:
            jiraDetailView
        case .grafanaAlertFiring, .grafanaAlertResolved:
            grafanaDetailView
        case .githubPRReview, .githubPRMerged, .githubWorkflowFailed:
            githubDetailView
        case .briefingGenerated:
            briefingDetailView
        case .awsCostAnomaly:
            awsCostDetailView
        case .confluencePageUpdated:
            confluenceDetailView
        case .appUpdate:
            appUpdateDetailView
        }
    }

    // MARK: - Jenkins Detail

    private var jenkinsDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Console Output", icon: "terminal")

            if let output = viewModel.consoleOutput {
                let lines = output.components(separatedBy: "\n")
                let preview = lines.suffix(80).joined(separator: "\n")
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !viewModel.isLoading {
                emptyContent("Console output unavailable")
            }
        }
    }

    // MARK: - Jira Detail

    private var jiraDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let key      = notification.metadata["ticketKey"] ?? ""
            let status   = viewModel.jiraIssue?.status ?? notification.metadata["status"] ?? ""
            let priority = viewModel.jiraIssue?.priority ?? notification.metadata["priority"] ?? ""
            let oldSt    = notification.metadata["oldStatus"]
            let newSt    = notification.metadata["newStatus"]

            // Status badges
            HStack(spacing: 8) {
                if !status.isEmpty { resultBadge(status, color: .blue) }
                if !priority.isEmpty { resultBadge(priority, color: .orange) }
            }

            // Status transition
            if let old = oldSt, let new = newSt {
                HStack(spacing: 6) {
                    Text("Status:").font(.caption.bold()).foregroundStyle(.secondary)
                    resultBadge(old, color: .secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    resultBadge(new, color: .green)
                }
            }

            // Description
            if let desc = viewModel.jiraIssue?.description, !desc.isEmpty {
                sectionHeader("Description", icon: "doc.text")
                Text(LocalizedStringKey(desc))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor).opacity(0.4)))
            }

            // Quick Comment
            if !key.isEmpty {
                Divider()
                sectionHeader("Quick Comment", icon: "text.bubble")
                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $viewModel.commentText)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    Button {
                        Task { await viewModel.submitComment(for: key, appState: appState) }
                    } label: {
                        Label("Send", systemImage: "paperplane.fill").font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.commentText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSubmittingComment)
                }
                if let msg = viewModel.commentSuccess {
                    Text(msg).font(.caption).foregroundStyle(.green)
                }
            }

            // Transitions
            if !key.isEmpty && !viewModel.transitions.isEmpty {
                Divider()
                sectionHeader("Transition", icon: "arrow.right.circle")
                HStack(spacing: 8) {
                    ForEach(viewModel.transitions) { transition in
                        Button {
                            Task { await viewModel.transitionIssue(key: key, transitionId: transition.id, appState: appState) }
                        } label: {
                            Text(transition.name).font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isTransitioning)
                    }
                }
                if let msg = viewModel.transitionSuccess {
                    Text(msg).font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Grafana Detail

    private var grafanaDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let isResolved = notification.type == .grafanaAlertResolved
            let summary    = notification.metadata["alertSummary"] ?? ""

            HStack(spacing: 8) {
                resultBadge(isResolved ? "RESOLVED" : "FIRING", color: isResolved ? .green : .red)
            }

            if !summary.isEmpty {
                sectionHeader("Summary", icon: "doc.text")
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor).opacity(0.4)))
            }

            if let alert = viewModel.grafanaAlert, !alert.labels.isEmpty {
                sectionHeader("Labels", icon: "tag")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(alert.labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 6) {
                            Text(key).font(.caption.bold().monospaced()).foregroundStyle(.secondary)
                            Text("=").font(.caption).foregroundStyle(.tertiary)
                            Text(value).font(.caption.monospaced()).foregroundStyle(.primary)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor).opacity(0.4)))
            }
        }
    }

    // MARK: - GitHub Detail

    private var githubDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let owner  = notification.metadata["owner"] ?? ""
            let repo   = notification.metadata["repo"] ?? ""
            let author = notification.metadata["authorLogin"] ?? ""

            // Metadata row
            HStack(spacing: 12) {
                if !author.isEmpty {
                    Label("@\(author)", systemImage: "person")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !owner.isEmpty && !repo.isEmpty {
                    Text("\(owner)/\(repo)")
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }

            // PR enriched data
            if let pr = viewModel.githubPR {
                HStack(spacing: 8) {
                    resultBadge(pr.state.uppercased(), color: pr.state == "open" ? .green : .purple)
                    if pr.isDraft { resultBadge("DRAFT", color: .secondary) }
                }

                sectionHeader("Branch", icon: "arrow.triangle.branch")
                HStack(spacing: 6) {
                    Text(pr.headBranch).font(.callout.monospaced())
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(pr.baseBranch).font(.callout.monospaced())
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor).opacity(0.4)))

                if !pr.body.isEmpty {
                    sectionHeader("Description", icon: "doc.text")
                    Text(pr.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor).opacity(0.4)))
                }
            }
        }
    }

    // MARK: - Briefing Detail

    private var briefingDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            emptyContent("Click \"View Full Briefing\" above to see the full content.")
        }
    }

    // MARK: - AWS Cost Detail

    private var awsCostDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = notification.metadata["currentMonthCost"],
               let last    = notification.metadata["lastMonthCost"],
               let pct     = notification.metadata["percentIncrease"] {
                sectionHeader("Cost Comparison", icon: "chart.bar")
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Month").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("$\(current)").font(.title2.bold()).foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Month").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("$\(last)").font(.title2.bold())
                    }
                    resultBadge("+\(pct)%", color: .red)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.15)))
            }
        }
    }

    // MARK: - Confluence Detail

    private var confluenceDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let author   = notification.metadata["authorName"] ?? ""
            let spaceKey = notification.metadata["spaceKey"] ?? ""

            HStack(spacing: 12) {
                if !author.isEmpty {
                    Label("Updated by \(author)", systemImage: "person")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !spaceKey.isEmpty {
                    resultBadge(spaceKey, color: .blue)
                }
            }
        }
    }

    // MARK: - App Update Detail

    private var appUpdateDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let version = notification.metadata["version"] {
                sectionHeader("Version", icon: "number")
                Text(version).font(.title3.monospaced())
            }
        }
    }

    // MARK: - AI Section

    @ViewBuilder
    private var aiSection: some View {
        let context = aiContext
        if !context.isEmpty {
            Divider()
            sectionHeader("AI Analysis", icon: "sparkles")
            if viewModel.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Analyzing…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let err = viewModel.aiError {
                Label(err, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
            } else if let analysis = viewModel.aiAnalysis {
                InlineMarkdownText(text: analysis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.15)))
            } else {
                Button {
                    Task { await viewModel.analyzeWithAI(context: context) }
                } label: {
                    Label("Analyze with AI", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasAPIKey)
            }
        }
    }

    private var aiContext: String {
        switch notification.type {
        case .jenkinsBuildFailed, .jenkinsBuildRecovered:
            let job = notification.metadata["jobName"] ?? "?"
            let build = notification.metadata["buildNumber"] ?? "?"
            let out = viewModel.consoleOutput ?? "(console not available)"
            let head = String(out.prefix(1500))
            let tail = String(out.suffix(2000))
            let ctx = head == tail ? head : head + "\n...\n" + tail
            return "Job: \(job) Build #\(build)\n\nConsole:\n\(ctx)"
        case .jiraAssigned, .jiraStatusChange, .jiraNewComment, .jiraMentioned:
            let key = notification.metadata["ticketKey"] ?? ""
            let summary = notification.metadata["summary"] ?? notification.body
            let status = viewModel.jiraIssue?.status ?? ""
            let priority = viewModel.jiraIssue?.priority ?? ""
            return "Jira ticket \(key): \(summary)\nStatus: \(status), Priority: \(priority)"
        case .grafanaAlertFiring, .grafanaAlertResolved:
            let title = notification.metadata["alertTitle"] ?? notification.title
            let summary = notification.metadata["alertSummary"] ?? ""
            let state = notification.type == .grafanaAlertResolved ? "RESOLVED" : "FIRING"
            return "Grafana alert '\(title)': \(state). \(summary)"
        case .githubPRReview, .githubPRMerged, .githubWorkflowFailed:
            let prNum = notification.metadata["prNumber"] ?? ""
            let owner = notification.metadata["owner"] ?? ""
            let repo = notification.metadata["repo"] ?? ""
            let title = notification.metadata["prTitle"] ?? notification.body
            let author = notification.metadata["authorLogin"] ?? ""
            return "GitHub PR #\(prNum) in \(owner)/\(repo): \(title) by @\(author)"
        default:
            return ""
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func resultBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func emptyContent(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Note: JiraIssueDetail, GrafanaAlertDetail, GitHubPRDetail are defined in
// NotificationDetailModels.swift (shared with NotificationDetailViewModel)

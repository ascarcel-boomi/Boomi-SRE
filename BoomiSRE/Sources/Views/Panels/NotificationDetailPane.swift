import SwiftUI

/// Inline expandable detail pane shown below a notification row.
struct NotificationDetailPane: View {
    let notification: SRENotification
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = NotificationDetailViewModel()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoading {
                loadingView
            } else if let err = viewModel.loadError {
                errorView(err)
            } else {
                detailContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task { await viewModel.loadDetail(for: notification, appState: appState) }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8)
            Text("Loading details…").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private func errorView(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.orange)
            .padding(.vertical, 8)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch notification.type {
        case .jenkinsBuildFailed, .jenkinsBuildRecovered:
            jenkinsDetailView
        case .jiraAssigned, .jiraStatusChange:
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
        VStack(alignment: .leading, spacing: 10) {
            let jobName     = notification.metadata["jobName"] ?? "Unknown job"
            let buildNumber = notification.metadata["buildNumber"] ?? "?"
            let duration    = notification.metadata["duration"] ?? ""
            let buildURL    = notification.metadata["buildURL"] ?? ""

            HStack(spacing: 8) {
                Image(systemName: notification.type == .jenkinsBuildFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notification.type == .jenkinsBuildFailed ? .red : .green)
                Text("\(jobName)  #\(buildNumber)")
                    .font(.callout.bold())
                if !duration.isEmpty {
                    Text(duration).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = URL(string: buildURL), !buildURL.isEmpty {
                    Link(destination: url) {
                        Label("Open in Jenkins", systemImage: "safari")
                            .font(.caption)
                    }
                }
            }

            resultBadge(notification.type == .jenkinsBuildFailed ? "FAILURE" : "SUCCESS",
                        color: notification.type == .jenkinsBuildFailed ? .red : .green)

            if let output = viewModel.consoleOutput {
                let lines = output.components(separatedBy: "\n")
                let preview = lines.suffix(50).joined(separator: "\n")
                ScrollView {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Console output unavailable (Jenkins not configured or inaccessible)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            aiButtonRow(context: jenkinsAIContext())
        }
    }

    private func jenkinsAIContext() -> String {
        let jobName = notification.metadata["jobName"] ?? "?"
        let build   = notification.metadata["buildNumber"] ?? "?"
        let out     = viewModel.consoleOutput ?? "(console not available)"
        let head    = String(out.prefix(1500))
        let tail    = String(out.suffix(2000))
        let ctx     = head == tail ? head : head + "\n...\n" + tail
        return "Job: \(jobName) Build #\(build)\n\nConsole:\n\(ctx)"
    }

    // MARK: - Jira Detail

    private var jiraDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let key      = notification.metadata["ticketKey"] ?? ""
            let summary  = notification.metadata["summary"] ?? notification.body
            let status   = viewModel.jiraIssue?.status ?? notification.metadata["status"] ?? ""
            let priority = viewModel.jiraIssue?.priority ?? notification.metadata["priority"] ?? ""
            let oldSt    = notification.metadata["oldStatus"]
            let newSt    = notification.metadata["newStatus"]

            HStack(spacing: 8) {
                Text(key).font(.callout.bold().monospaced()).foregroundStyle(Color.accentColor)
                Spacer()
                if !key.isEmpty, let url = URL(string: "\(appState.jiraBaseURL)/browse/\(key)") {
                    Link(destination: url) {
                        Label("Open in Jira", systemImage: "safari").font(.caption)
                    }
                }
                if !key.isEmpty {
                    Button("View Full Ticket") {
                        appState.selectedTicketKey = key
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            Text(summary).font(.callout).lineLimit(3)

            HStack(spacing: 8) {
                if !status.isEmpty {
                    resultBadge(status, color: .blue)
                }
                if !priority.isEmpty {
                    resultBadge(priority, color: .orange)
                }
            }

            if let old = oldSt, let new = newSt {
                HStack(spacing: 6) {
                    Text("Status:").font(.caption).foregroundStyle(.secondary)
                    resultBadge(old, color: .secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    resultBadge(new, color: .green)
                }
            }

            if let desc = viewModel.jiraIssue?.description, !desc.isEmpty {
                Text(String(desc.prefix(400))).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }

            aiButtonRow(context: "Jira ticket \(key): \(summary)\nStatus: \(status), Priority: \(priority)")
        }
    }

    // MARK: - Grafana Detail

    private var grafanaDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let uid        = notification.metadata["alertUID"] ?? ""
            let title      = notification.metadata["alertTitle"] ?? notification.title
            let summary    = notification.metadata["alertSummary"] ?? ""
            let isResolved = notification.type == .grafanaAlertResolved

            HStack(spacing: 8) {
                Image(systemName: isResolved ? "checkmark.circle.fill" : "bell.badge.fill")
                    .foregroundStyle(isResolved ? .green : .red)
                Text(title).font(.callout.bold())
                Spacer()
                Link(destination: URL(string: appState.grafanaURL.isEmpty ? "https://grafana.io" : appState.grafanaURL)!) {
                    Label("Open Grafana", systemImage: "safari").font(.caption)
                }
            }

            resultBadge(isResolved ? "RESOLVED" : "FIRING", color: isResolved ? .green : .red)

            if !summary.isEmpty {
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }

            if let alert = viewModel.grafanaAlert {
                if !alert.labels.isEmpty {
                    let labels = alert.labels.map { "\($0.key)=\($0.value)" }.joined(separator: "  ")
                    Text(labels).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                }
            } else if uid.isEmpty {
                Text("Alert details unavailable for older notifications")
                    .font(.caption).foregroundStyle(.secondary)
            }

            aiButtonRow(context: "Grafana alert '\(title)': \(isResolved ? "RESOLVED" : "FIRING"). \(summary)")
        }
    }

    // MARK: - GitHub Detail

    private var githubDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let owner   = notification.metadata["owner"] ?? ""
            let repo    = notification.metadata["repo"] ?? ""
            let prNum   = notification.metadata["prNumber"] ?? ""
            let prTitle = notification.metadata["prTitle"] ?? notification.body
            let author  = notification.metadata["authorLogin"] ?? ""
            let htmlURL = notification.metadata["htmlURL"] ?? ""

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull").foregroundStyle(Color.purple)
                Text("#\(prNum) \(prTitle)").font(.callout.bold()).lineLimit(2)
                Spacer()
                if !htmlURL.isEmpty, let url = URL(string: htmlURL) {
                    Link(destination: url) {
                        Label("Open on GitHub", systemImage: "safari").font(.caption)
                    }
                }
            }

            HStack(spacing: 8) {
                if !author.isEmpty {
                    Label("@\(author)", systemImage: "person").font(.caption).foregroundStyle(.secondary)
                }
                if !owner.isEmpty && !repo.isEmpty {
                    Text("\(owner)/\(repo)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }

            if let pr = viewModel.githubPR {
                HStack(spacing: 8) {
                    resultBadge(pr.state.uppercased(), color: pr.state == "open" ? .green : .purple)
                    if pr.isDraft { resultBadge("DRAFT", color: .secondary) }
                    Text("\(pr.headBranch) → \(pr.baseBranch)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if !pr.body.isEmpty {
                    Text(String(pr.body.prefix(300))).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }

            aiButtonRow(context: "GitHub PR #\(prNum) in \(owner)/\(repo): \(prTitle) by @\(author)")
        }
    }

    // MARK: - Briefing Detail

    private var briefingDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.text").foregroundStyle(Color.accentColor)
                Text("Briefing Generated").font(.callout.bold())
                Spacer()
                Button("View Full Briefing") {
                    appState.selectedReport = ReportCatalog.all.first { $0.id == "exec_assistant" }
                    appState.showSettings = false
                }
                .font(.caption).buttonStyle(.bordered)
            }
            Text(notification.body).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - AWS Cost Detail

    private var awsCostDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                Text("Cost Anomaly Detected").font(.callout.bold())
                Spacer()
                Button("Open Cost Explorer") {
                    appState.selectedReport = ReportCatalog.all.first { $0.id == "aws_cost_explorer" }
                    appState.showSettings = false
                }
                .font(.caption).buttonStyle(.bordered)
            }
            Text(notification.body).font(.callout).foregroundStyle(.secondary)
            if let current = notification.metadata["currentMonthCost"],
               let last    = notification.metadata["lastMonthCost"],
               let pct     = notification.metadata["percentIncrease"] {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This month").font(.caption).foregroundStyle(.secondary)
                        Text("$\(current)").font(.callout.bold()).foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last month").font(.caption).foregroundStyle(.secondary)
                        Text("$\(last)").font(.callout.bold())
                    }
                    resultBadge("+\(pct)%", color: .red)
                }
            }
        }
    }

    // MARK: - Confluence Detail

    private var confluenceDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let pageTitle = notification.metadata["pageTitle"] ?? notification.title
            let author    = notification.metadata["authorName"] ?? ""
            let spaceKey  = notification.metadata["spaceKey"] ?? ""
            let pageURL   = notification.metadata["pageURL"] ?? ""

            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill").foregroundStyle(Color.blue)
                Text(pageTitle).font(.callout.bold()).lineLimit(2)
                Spacer()
                if !pageURL.isEmpty, let url = URL(string: pageURL) {
                    Link(destination: url) {
                        Label("Open in Confluence", systemImage: "safari").font(.caption)
                    }
                }
            }
            HStack(spacing: 8) {
                if !author.isEmpty {
                    Label("Updated by \(author)", systemImage: "person").font(.caption).foregroundStyle(.secondary)
                }
                if !spaceKey.isEmpty {
                    Text(spaceKey).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - AI Analysis

    private func aiButtonRow(context: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if viewModel.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Analyzing…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let err = viewModel.aiError {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            } else if let analysis = viewModel.aiAnalysis {
                InlineMarkdownText(text: analysis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.15)))
            } else {
                Button {
                    Task { await viewModel.analyzeWithAI(context: context) }
                } label: {
                    Label("Analyze with AI", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasAPIKey)
            }
        }
    }

    // MARK: - Shared helper

    private func resultBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    // MARK: - App Update Detail

    private var appUpdateDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                Text("Boomi SRE Update Available").font(.callout.bold())
                Spacer()
                Button("Open Settings") {
                    appState.showSettings = true
                }
                .font(.caption).buttonStyle(.bordered)
            }
            Text(notification.body).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// Note: JiraIssueDetail, GrafanaAlertDetail, GitHubPRDetail are defined in
// NotificationDetailModels.swift (shared with NotificationDetailViewModel)

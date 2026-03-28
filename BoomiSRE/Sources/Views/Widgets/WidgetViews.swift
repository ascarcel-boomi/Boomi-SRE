import SwiftUI
import Charts

// MARK: - Shared Widget Card

struct WidgetCard<Content: View>: View {
    let type: WidgetType
    var navigateTo: String? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            if let nav = navigateTo {
                appState.navigate(to: nav)
            }
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: type.icon).foregroundStyle(.secondary)
                    Text(type.title).font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    if navigateTo != nil || onTap != nil {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service Health Widget

struct ServiceHealthWidget: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .serviceHealth, navigateTo: "settings_integrations") {
            HStack(spacing: 12) {
                serviceIcon("AWS",        "cloud",         appState.awsAuthStatus)
                serviceIcon("Jira",       "ticket",        appState.jiraAuthStatus)
                serviceIcon("GitHub",     "chevron.left.forwardslash.chevron.right", appState.githubAuthStatus)
                serviceIcon("Jenkins",    "hammer",        appState.jenkinsAuthStatus)
                serviceIcon("Grafana",    "chart.bar",     appState.grafanaAuthStatus)
                serviceIcon("Google",     "envelope",      appState.googleAuthStatus)
                serviceIcon("Confluence", "doc.richtext",  appState.confluenceAuthStatus)
            }
        }
    }

    private func serviceIcon(_ name: String, _ icon: String, _ status: AuthStatus) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon).font(.callout).foregroundStyle(.secondary)
                Circle().fill(status.color).frame(width: 7, height: 7)
                    .offset(x: 3, y: 3)
            }
        }
        .help("\(name): \(status.label)")
    }
}

// MARK: - Active Incidents Widget

struct ActiveIncidentsWidget: View {
    let incidents: [Incident]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .activeIncidents, navigateTo: "incidents") {
            if incidents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("No active incidents").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(incidents.count) active").font(.title3.bold())
                            .foregroundStyle(incidents.contains { $0.severity == .p1 } ? .red : .orange)
                        Spacer()
                    }
                    ForEach(incidents.prefix(4)) { inc in
                        HStack(spacing: 6) {
                            Image(systemName: inc.severity.icon).foregroundStyle(inc.severity.color).font(.caption)
                            Text(inc.title).font(.caption).lineLimit(1)
                            Spacer()
                            Text(inc.elapsedString).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - My Tickets Widget

struct MyTicketsWidget: View {
    let tickets: [JiraIssue]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .myTickets, navigateTo: "jira_todo") {
            if tickets.isEmpty {
                Text("No open tickets").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(tickets.count) open").font(.title3.bold())
                    ForEach(tickets.prefix(5), id: \.key) { issue in
                        HStack(spacing: 6) {
                            Circle().fill(priorityColor(issue.fields.priority?.name ?? ""))
                                .frame(width: 6, height: 6)
                            Text(issue.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(issue.fields.summary ?? "").font(.caption).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "highest": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .secondary
        }
    }
}

// MARK: - Recent PRs Widget

struct RecentPRsWidget: View {
    let prs: [GitHubPR]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .recentPRs, navigateTo: "github_browser") {
            if prs.isEmpty {
                Text(appState.githubToken.isEmpty ? "Configure GitHub in Settings" : "No open PRs")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(prs.count) open PR\(prs.count == 1 ? "" : "s")").font(.title3.bold())
                    ForEach(prs.prefix(4), id: \.id) { pr in
                        HStack(spacing: 6) {
                            Image(systemName: pr.isDraft ? "doc" : "arrow.triangle.pull")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(pr.title).font(.caption).lineLimit(1)
                            Spacer()
                            Text("@\(pr.authorLogin)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Jenkins Builds Widget

struct JenkinsBuildsWidget: View {
    let builds: [(jobName: String, build: JenkinsBuild)]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .jenkinsBuilds, navigateTo: "jenkins_browser") {
            if builds.isEmpty {
                Text(appState.jenkinsToken.isEmpty ? "Configure Jenkins in Settings" : "No recent builds")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let failed = builds.filter { $0.build.result == "FAILURE" }.count
                VStack(alignment: .leading, spacing: 6) {
                    if failed > 0 {
                        Text("\(failed) failed").font(.title3.bold()).foregroundStyle(.red)
                    } else {
                        Text("All passing").font(.title3.bold()).foregroundStyle(.green)
                    }
                    ForEach(Array(builds.prefix(4).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Circle().fill(buildColor(item.build.result)).frame(width: 8, height: 8)
                            Text(item.jobName).font(.caption).lineLimit(1)
                            Spacer()
                            Text("#\(item.build.number)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func buildColor(_ result: String?) -> Color {
        switch result {
        case "SUCCESS": return .green
        case "FAILURE": return .red
        case "UNSTABLE": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Grafana Alerts Widget

struct GrafanaAlertsWidget: View {
    let alerts: [GrafanaAlertRule]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .grafanaAlerts, navigateTo: "grafana_browser") {
            if alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(appState.grafanaToken.isEmpty ? "Configure Grafana in Settings" : "All clear")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(alerts.count) firing").font(.title3.bold()).foregroundStyle(.red)
                    ForEach(alerts.prefix(4), id: \.uid) { alert in
                        HStack(spacing: 6) {
                            Image(systemName: "bell.badge.fill").font(.caption).foregroundStyle(.red)
                            Text(alert.title).font(.caption).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - JSM Ops Alerts Widget

struct JSMOpsAlertsWidget: View {
    let alerts: [OpsAlert]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .jsmOpsAlerts, navigateTo: "oncall") {
            if alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(appState.isJiraConfigured ? "No active alerts" : "Configure Jira in Settings")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                let openCount    = alerts.filter { $0.status.lowercased() == "open" && !$0.acknowledged }.count
                let ackedCount   = alerts.filter { $0.acknowledged }.count
                let assignedCount = alerts.filter { !$0.owner.isEmpty && $0.owner.lowercased() == appState.jiraEmail.lowercased() }.count

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        if openCount > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("\(openCount) open").font(.callout.bold()).foregroundStyle(.red)
                            }
                        }
                        if ackedCount > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(.orange).frame(width: 8, height: 8)
                                Text("\(ackedCount) acked").font(.callout.bold()).foregroundStyle(.orange)
                            }
                        }
                        if assignedCount > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(.blue).frame(width: 8, height: 8)
                                Text("\(assignedCount) mine").font(.callout.bold()).foregroundStyle(.blue)
                            }
                        }
                    }

                    ForEach(alerts.prefix(5)) { alert in
                        HStack(spacing: 6) {
                            Text(alert.priority)
                                .font(.caption2.bold())
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Capsule().fill(alertPriorityColor(alert.priority).opacity(0.15)))
                                .foregroundStyle(alertPriorityColor(alert.priority))
                            Text(alert.message)
                                .font(.caption).lineLimit(1).foregroundStyle(.primary)
                            Spacer()
                            if !alert.source.isEmpty {
                                Text(alert.source).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if alerts.count > 5 {
                        Text("+ \(alerts.count - 5) more")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func alertPriorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red; case "P2": return .orange
        case "P3": return .yellow; case "P4": return .blue
        default:   return .secondary
        }
    }
}

// MARK: - Notifications Widget

struct NotificationsWidget: View {
    let notifications: [SRENotification]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .notifications, navigateTo: "notifications") {
            let unread = notifications.filter { !$0.isRead }.count
            if notifications.isEmpty {
                Text("No notifications").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if unread > 0 {
                        Text("\(unread) unread").font(.callout.bold()).foregroundStyle(.red)
                    }
                    ForEach(notifications.prefix(4)) { n in
                        HStack(spacing: 6) {
                            if !n.isRead { Circle().fill(.blue).frame(width: 6, height: 6) }
                            Image(systemName: n.type.icon).font(.caption2).foregroundStyle(n.type.color)
                            Text(n.title).font(.caption).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - On-Call Widget

struct OnCallWidget: View {
    let schedules: [OpsSchedule]
    let participants: [String: [OnCallParticipant]]
    let displayNames: [String: String]
    @EnvironmentObject var appState: AppState

    var activeSchedules: [OpsSchedule] {
        let effectiveIds = appState.activeJSMTeamIds.isEmpty ? appState.favoriteJSMTeams : appState.activeJSMTeamIds
        return schedules.filter { s in effectiveIds.contains(s.teamId ?? "") }
    }

    var body: some View {
        WidgetCard(type: .onCallSchedule, navigateTo: "oncall") {
            if activeSchedules.isEmpty {
                Text(appState.activeJSMTeamIds.isEmpty && appState.favoriteJSMTeams.isEmpty ? "Map teams in Products & Resources" : "No schedules found")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activeSchedules.prefix(4)) { schedule in
                        let people = participants[schedule.id] ?? []
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill").font(.caption2).foregroundStyle(Color.accentColor)
                            Text(schedule.name).font(.caption).lineLimit(1)
                            Spacer()
                            if let primary = people.first {
                                Text(displayNames[primary.name] ?? primary.name)
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("—").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Calendar Widget

struct CalendarWidget: View {
    let events: [CalendarEvent]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .upcomingCalendar, navigateTo: "google_calendar") {
            if events.isEmpty {
                Text(appState.googleCredentials == nil ? "Configure Google in Settings" : "No upcoming events")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(events.prefix(3)), id: \.id) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(eventTimeLabel(event.startDateTime))
                                .font(.caption2.bold()).foregroundColor(.accentColor)
                                .frame(width: 40)
                            Text(event.summary).font(.caption).lineLimit(2)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func eventTimeLabel(_ dateTime: String) -> String {
        let str = String(dateTime.prefix(16)).replacingOccurrences(of: "T", with: " ")
        return String(str.suffix(5))
    }
}

// MARK: - Email Widget

struct EmailWidget: View {
    let emails: [GmailMessage]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .unreadEmails, navigateTo: "google_gmail") {
            if emails.isEmpty {
                Text(appState.googleCredentials == nil ? "Configure Google in Settings" : "No unread emails")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(emails.count)+ unread").font(.title3.bold())
                    ForEach(emails.prefix(4), id: \.id) { msg in
                        HStack(spacing: 6) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(msg.subject.isEmpty ? "(no subject)" : msg.subject)
                                    .font(.caption).lineLimit(1)
                                Text(msg.from.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces) ?? msg.from)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quick Actions Widget

struct QuickActionsWidget: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .quickActions, navigateTo: "copilot_chat") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton("Ask Copilot", icon: "sparkles") {
                        appState.navigate(to: "copilot_chat")
                    }
                    actionButton("New Incident", icon: "exclamationmark.shield") {
                        appState.navigate(to: "incidents")
                    }
                }
                HStack(spacing: 8) {
                    actionButton("Check Services", icon: "arrow.clockwise") {
                        appState.checkAllServices()
                    }
                    actionButton("Settings", icon: "gear") {
                        appState.showSettings = true
                        appState.selectedReport = nil
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - AI Daily Summary Widget

struct AIDailySummaryWidget: View {
    let summary: String?
    let summaryDate: Date?
    let isLoading: Bool
    let onRegenerate: () -> Void

    private func truncatedSummary(_ text: String, sentences: Int) -> String {
        var count = 0
        var result = ""
        for char in text {
            result.append(char)
            if char == "." {
                count += 1
                if count >= sentences { break }
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        WidgetCard(type: .aiDailySummary, navigateTo: "exec_assistant") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let date = summaryDate {
                        Text("Generated \(date, style: .relative) ago")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(isLoading)
                }
                if isLoading && summary == nil {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Claude is analyzing your SRE state...").font(.callout).foregroundStyle(.secondary)
                    }
                } else if let text = summary {
                    let displayText = truncatedSummary(text, sentences: 3)
                    InlineMarkdownText(text: displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Click the refresh button to generate your AI daily summary")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - AWS Cost Trend Widget

struct AWSCostTrendWidget: View {
    let total: Double
    let previous: Double
    let profile: String
    @EnvironmentObject var appState: AppState

    private var changePercent: Double {
        guard previous > 0 else { return 0 }
        return ((total - previous) / previous) * 100
    }

    var body: some View {
        WidgetCard(type: .awsCostTrend, navigateTo: "aws_cost_explorer") {
            if total == 0 && previous == 0 {
                Text("No cost data — check AWS profile").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "$%.0f", total))
                        .font(.title.bold().monospacedDigit())
                    HStack(spacing: 4) {
                        Text("this month")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if previous > 0 {
                            let up = changePercent > 0
                            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                                .foregroundStyle(up ? .red : .green)
                            Text(String(format: "%.1f%%", abs(changePercent)))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(up ? .red : .green)
                            Text("vs last month")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Confluence Recent Widget

struct ConfluenceRecentWidget: View {
    let pages: [(title: String, spaceKey: String, url: String)]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .confluenceRecent, navigateTo: "confluence_browser") {
            if pages.isEmpty {
                Text("No recent pages").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pages.prefix(4), id: \.url) { page in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.richtext").font(.caption2).foregroundStyle(.blue)
                            Text(page.title).font(.caption).lineLimit(1)
                            Spacer()
                            Text(page.spaceKey).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

import SwiftUI
import Charts

// MARK: - Shared Widget Card

struct WidgetCard<Content: View>: View {
    let type: WidgetType
    let size: WidgetSize
    var navigateTo: String? = nil
    var onTap: (() -> Void)? = nil
    var onResize: ((Int) -> Void)? = nil   // callback(newColumnSpan)
    var widgetColumnSpan: Int = 1
    var maxColumns: Int = 3
    @ViewBuilder let content: () -> Content
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    @State private var showFilterPopover = false
    @State private var resizeDragStart: Int = 0

    private var hasActiveFilters: Bool {
        !(appState.widgetFilters[type.rawValue] ?? [:]).isEmpty
    }

    init(type: WidgetType, size: WidgetSize = .medium, navigateTo: String? = nil, onTap: (() -> Void)? = nil,
         onResize: ((Int) -> Void)? = nil, widgetColumnSpan: Int = 1, maxColumns: Int = 3,
         @ViewBuilder content: @escaping () -> Content) {
        self.type = type
        self.size = size
        self.navigateTo = navigateTo
        self.onTap = onTap
        self.onResize = onResize
        self.widgetColumnSpan = widgetColumnSpan
        self.maxColumns = maxColumns
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .foregroundStyle(.secondary)
                Text(type.title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if type.hasFilters {
                    Button { showFilterPopover.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.caption2)
                            .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFilterPopover) {
                        widgetFilterPopover.padding(12).frame(width: 240)
                    }
                }
                if navigateTo != nil || onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: size == .small ? 90 : size == .medium ? 220 : .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        // Drag handle on hover (left)
        .overlay(alignment: .leading) {
            if isHovering {
                Image(systemName: "line.3.horizontal")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
        }
        // Resize handle on hover (bottom-right corner) — drag to change column span
        .overlay(alignment: .bottomTrailing) {
            if isHovering && onResize != nil {
                Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let threshold: CGFloat = 80
                                let delta = Int(value.translation.width / threshold)
                                let newSpan = max(1, min(maxColumns, resizeDragStart + delta))
                                onResize?(newSpan)
                            }
                            .onEnded { _ in resizeDragStart = widgetColumnSpan }
                    )
                    .onAppear { resizeDragStart = widgetColumnSpan }
                    .transition(.opacity)
            }
        }
        // Inline size controls on hover (top-right)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                HStack(spacing: 2) {
                    ForEach([WidgetSize.small, .medium, .large], id: \.self) { sz in
                        let label = sz == .small ? "S" : sz == .medium ? "M" : "L"
                        Button {
                            if let idx = appState.dashboardWidgets.firstIndex(where: { $0.type == type }) {
                                appState.dashboardWidgets[idx].size = sz
                                appState.saveConfig()
                            }
                        } label: { Text(label).font(.caption2) }
                        .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture {
            if let action = onTap { action(); return }
            if let reportId = navigateTo {
                appState.selectedReport = ReportCatalog.all.first { $0.id == reportId }
            }
        }
    }

    @ViewBuilder
    private var widgetFilterPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter: \(type.title)").font(.subheadline.bold())
            Divider()
            // Common filters based on widget type
            switch type {
            case .jsmOpsAlerts:
                filterSection("Priority") {
                    filterToggle("P1", key: "priority", value: "P1")
                    filterToggle("P2", key: "priority", value: "P2")
                    filterToggle("P3", key: "priority", value: "P3")
                }
                filterSection("Status") {
                    filterToggle("Open only", key: "status", value: "open")
                    filterToggle("Unacknowledged", key: "acked", value: "false")
                }
            case .jenkinsBuilds:
                filterSection("Result") {
                    filterToggle("Failed only", key: "result", value: "FAILURE")
                    filterToggle("All", key: "result", value: "")
                }
            case .myTickets:
                filterSection("Status") {
                    filterToggle("In Progress only", key: "status", value: "indeterminate")
                    filterToggle("All active", key: "status", value: "")
                }
            default:
                Text("No filters available").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button("Reset Filters") {
                appState.widgetFilters.removeValue(forKey: type.rawValue)
                appState.saveConfig()
                showFilterPopover = false
            }
            .font(.caption).buttonStyle(.bordered).controlSize(.small).tint(.red)
        }
    }

    private func filterSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func filterToggle(_ label: String, key: String, value: String) -> some View {
        let current = appState.widgetFilters[type.rawValue]?[key] ?? ""
        return Button {
            if current == value {
                appState.widgetFilters[type.rawValue, default: [:]][key] = ""
            } else {
                appState.widgetFilters[type.rawValue, default: [:]][key] = value
            }
            if appState.widgetFilters[type.rawValue]?.values.allSatisfy({ $0.isEmpty }) == true {
                appState.widgetFilters.removeValue(forKey: type.rawValue)
            }
            appState.saveConfig()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(current == value ? Color.accentColor : .secondary)
                    .font(.caption)
                Text(label).font(.caption)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service Health Widget

struct ServiceHealthWidget: View {
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(size: WidgetSize = .medium) {
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .serviceHealth, size: size) {
            if size == .small {
                HStack(spacing: 8) {
                    Circle().fill(appState.awsAuthStatus.color).frame(width: 10, height: 10).help("AWS")
                    Circle().fill(appState.jiraAuthStatus.color).frame(width: 10, height: 10).help("Jira")
                    Circle().fill(appState.githubAuthStatus.color).frame(width: 10, height: 10).help("GitHub")
                    Circle().fill(appState.jenkinsAuthStatus.color).frame(width: 10, height: 10).help("Jenkins")
                    Circle().fill(appState.grafanaAuthStatus.color).frame(width: 10, height: 10).help("Grafana")
                }
            } else {
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(incidents: [Incident], size: WidgetSize = .medium) {
        self.incidents = incidents
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .activeIncidents, size: size, navigateTo: "incidents") {
            if incidents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("No active incidents").font(.callout).foregroundStyle(.secondary)
                }
            } else if size == .small {
                let p1Count = incidents.filter { $0.severity == .p1 }.count
                Text("\(p1Count > 0 ? "\(p1Count) P1 · " : "")\(incidents.count) active")
                    .font(.callout.bold())
                    .foregroundStyle(p1Count > 0 ? .red : .orange)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(incidents.count) active").font(.title3.bold())
                            .foregroundStyle(incidents.contains { $0.severity == .p1 } ? .red : .orange)
                        Spacer()
                    }
                    let limit = size == .large ? 8 : 3
                    ForEach(incidents.prefix(limit)) { inc in
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(tickets: [JiraIssue], size: WidgetSize = .medium) {
        self.tickets = tickets
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .myTickets, size: size, navigateTo: "jira_todo") {
            if tickets.isEmpty {
                Text("No open tickets").font(.callout).foregroundStyle(.secondary)
            } else if size == .small {
                Text("\(tickets.count) ticket\(tickets.count == 1 ? "" : "s")")
                    .font(.callout.bold())
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(tickets.count) open").font(.title3.bold())
                    let limit = size == .large ? 10 : 5
                    ForEach(tickets.prefix(limit), id: \.key) { issue in
                        HStack(spacing: 6) {
                            Circle().fill(priorityColor(issue.fields.priority?.name ?? ""))
                                .frame(width: 6, height: 6)
                            Text(issue.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(issue.fields.summary ?? "").font(.caption).lineLimit(1)
                            if size == .large, let due = issue.fields.duedate, !due.isEmpty {
                                Spacer()
                                Text(due).font(.caption2).foregroundStyle(.secondary)
                            }
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(prs: [GitHubPR], size: WidgetSize = .medium) {
        self.prs = prs
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .recentPRs, size: size, navigateTo: "github_browser") {
            if prs.isEmpty {
                Text(appState.githubToken.isEmpty ? "Configure GitHub in Settings" : "No open PRs")
                    .font(.callout).foregroundStyle(.secondary)
            } else if size == .small {
                Text("\(prs.count) open PR\(prs.count == 1 ? "" : "s")")
                    .font(.callout.bold())
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(prs.count) open PR\(prs.count == 1 ? "" : "s")").font(.title3.bold())
                    let limit = size == .large ? 8 : 3
                    ForEach(prs.prefix(limit), id: \.id) { pr in
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(builds: [(jobName: String, build: JenkinsBuild)], size: WidgetSize = .medium) {
        self.builds = builds
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .jenkinsBuilds, size: size, navigateTo: "jenkins_browser") {
            if builds.isEmpty {
                Text(appState.jenkinsToken.isEmpty ? "Configure Jenkins in Settings" : "No recent builds")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let failed = builds.filter { $0.build.result == "FAILURE" }.count
                if size == .small {
                    Text(failed > 0 ? "\(failed) failed" : "All passing")
                        .font(.callout.bold())
                        .foregroundStyle(failed > 0 ? .red : .green)
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if failed > 0 {
                            Text("\(failed) failed").font(.title3.bold()).foregroundStyle(.red)
                        } else {
                            Text("All passing").font(.title3.bold()).foregroundStyle(.green)
                        }
                        let limit = size == .large ? 8 : 3
                        ForEach(Array(builds.prefix(limit).enumerated()), id: \.offset) { _, item in
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(alerts: [GrafanaAlertRule], size: WidgetSize = .medium) {
        self.alerts = alerts
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .grafanaAlerts, size: size, navigateTo: "grafana_browser") {
            if alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(appState.grafanaToken.isEmpty ? "Configure Grafana in Settings" : "All clear")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if size == .small {
                Text("\(alerts.count) firing")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(alerts.count) firing").font(.title3.bold()).foregroundStyle(.red)
                    let limit = size == .large ? 8 : 4
                    ForEach(alerts.prefix(limit), id: \.uid) { alert in
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(alerts: [OpsAlert], size: WidgetSize = .medium) {
        self.alerts = alerts
        self.size = size
    }

    // Tint card based on highest priority alert
    private var cardTint: Color? {
        if alerts.contains(where: { $0.priority == "P1" }) { return .red }
        if alerts.contains(where: { $0.priority == "P2" }) { return .orange }
        return nil
    }

    var body: some View {
        WidgetCard(type: .jsmOpsAlerts, size: size, navigateTo: "oncall") {
            if alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(appState.isJiraConfigured ? "No active alerts" : "Configure Jira in Settings")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                let openCount    = alerts.filter { $0.status.lowercased() == "open" && !$0.acknowledged }.count
                let p1Count      = alerts.filter { $0.priority == "P1" }.count
                let ackedCount   = alerts.filter { $0.acknowledged }.count
                let assignedCount = alerts.filter { !$0.owner.isEmpty && $0.owner.lowercased() == appState.jiraEmail.lowercased() }.count

                if size == .small {
                    Text("\(openCount) open\(p1Count > 0 ? " · \(p1Count) P1" : "")")
                        .font(.callout.bold())
                        .foregroundStyle(p1Count > 0 ? .red : .orange)
                        .lineLimit(1)
                } else {
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

                        let limit = size == .large ? 10 : 5
                        ForEach(alerts.prefix(limit)) { alert in
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
                                if size == .large {
                                    if !alert.integrationName.isEmpty {
                                        Text(alert.integrationName).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if alerts.count > limit {
                            Text("+ \(alerts.count - limit) more")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .notifications, size: size, navigateTo: "notifications") {
            let unread = notifications.filter { !$0.isRead }.count
            switch size {
            case .small:
                HStack(spacing: 6) {
                    Text("\(unread)").font(.title2.bold()).foregroundStyle(unread > 0 ? .red : .green)
                    Text("unread").font(.caption).foregroundStyle(.secondary)
                }
            case .medium:
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
            case .large:
                if notifications.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("No recent notifications").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(notifications.count) recent · \(unread) unread").font(.callout.bold())
                        ForEach(notifications.prefix(8)) { n in
                            HStack(spacing: 6) {
                                if !n.isRead { Circle().fill(.blue).frame(width: 6, height: 6) }
                                Image(systemName: n.type.icon).font(.caption2).foregroundStyle(n.type.color)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.title).font(.caption).lineLimit(1)
                                    Text(n.body).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    var favSchedules: [OpsSchedule] {
        schedules.filter { s in appState.favoriteJSMTeams.contains(s.teamId ?? "") }
    }

    var body: some View {
        WidgetCard(type: .onCallSchedule, size: size, navigateTo: "oncall") {
            switch size {
            case .small:
                HStack(spacing: 6) {
                    Text("\(favSchedules.count)").font(.title2.bold())
                    Text("on-call").font(.caption).foregroundStyle(.secondary)
                }
            case .medium:
                if favSchedules.isEmpty {
                    Text(appState.favoriteJSMTeams.isEmpty ? "Add favorites in Settings → JSM" : "No schedules found")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(favSchedules.prefix(4)) { schedule in
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
            case .large:
                if favSchedules.isEmpty {
                    Text("No favorite teams configured — add them in Settings → JSM Operations")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(favSchedules.prefix(6)) { schedule in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(schedule.name).font(.caption.bold())
                                let people = participants[schedule.id] ?? []
                                if people.isEmpty {
                                    Text("No one on call").font(.caption2).foregroundStyle(.tertiary)
                                } else {
                                    ForEach(Array(people.prefix(3).enumerated()), id: \.offset) { i, p in
                                        HStack(spacing: 6) {
                                            Image(systemName: i == 0 ? "person.fill" : "person")
                                                .font(.caption2)
                                                .foregroundStyle(i == 0 ? Color.accentColor : .secondary)
                                            Text(displayNames[p.name] ?? p.name).font(.caption)
                                            if i == 0 {
                                                Text("Primary").font(.caption2)
                                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                        }
                                    }
                                }
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(events: [CalendarEvent], size: WidgetSize = .medium) {
        self.events = events
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .upcomingCalendar, size: size, navigateTo: "google_calendar") {
            if events.isEmpty {
                Text(appState.googleCredentials == nil ? "Configure Google in Settings" : "No upcoming events")
                    .font(.callout).foregroundStyle(.secondary)
            } else if size == .small {
                if let next = events.first {
                    Text("Next: \(next.summary)")
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    let limit = size == .large ? 5 : 3
                    ForEach(Array(events.prefix(limit)), id: \.id) { event in
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(emails: [GmailMessage], size: WidgetSize = .medium) {
        self.emails = emails
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .unreadEmails, size: size, navigateTo: "google_gmail") {
            if emails.isEmpty {
                Text(appState.googleCredentials == nil ? "Configure Google in Settings" : "No unread emails")
                    .font(.callout).foregroundStyle(.secondary)
            } else if size == .small {
                Text("\(emails.count) unread")
                    .font(.callout.bold())
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(emails.count)+ unread").font(.title3.bold())
                    let limit = size == .large ? 8 : 3
                    ForEach(emails.prefix(limit), id: \.id) { msg in
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
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    init(size: WidgetSize = .medium) {
        self.size = size
    }

    var body: some View {
        WidgetCard(type: .quickActions, size: size) {
            if size == .small {
                HStack(spacing: 8) {
                    Button {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "copilot_chat" }
                    } label: {
                        Image(systemName: "sparkles").font(.callout)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .help("Ask Copilot")

                    Button {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "incidents" }
                    } label: {
                        Image(systemName: "exclamationmark.shield").font(.callout)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .help("New Incident")
                }
            } else if size == .large {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        largeActionButton("Ask Copilot", icon: "sparkles", description: "Chat with AI assistant") {
                            appState.selectedReport = ReportCatalog.all.first { $0.id == "copilot_chat" }
                        }
                        largeActionButton("New Incident", icon: "exclamationmark.shield", description: "Create an incident") {
                            appState.selectedReport = ReportCatalog.all.first { $0.id == "incidents" }
                        }
                    }
                    HStack(spacing: 8) {
                        largeActionButton("Check Services", icon: "arrow.clockwise", description: "Refresh all service statuses") {
                            appState.checkAllServices()
                        }
                        largeActionButton("Settings", icon: "gear", description: "Open app preferences") {
                            appState.showSettings = true
                            appState.selectedReport = nil
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        actionButton("Ask Copilot", icon: "sparkles") {
                            appState.selectedReport = ReportCatalog.all.first { $0.id == "copilot_chat" }
                        }
                        actionButton("New Incident", icon: "exclamationmark.shield") {
                            appState.selectedReport = ReportCatalog.all.first { $0.id == "incidents" }
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

    private func largeActionButton(_ title: String, icon: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Label(title, systemImage: icon).font(.caption.bold())
                Text(description).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - AI Daily Summary Widget

struct AIDailySummaryWidget: View {
    let summary: String?
    let summaryDate: Date?
    let isLoading: Bool
    let size: WidgetSize
    let onRegenerate: () -> Void

    init(summary: String?, summaryDate: Date?, isLoading: Bool, size: WidgetSize = .medium, onRegenerate: @escaping () -> Void) {
        self.summary = summary
        self.summaryDate = summaryDate
        self.isLoading = isLoading
        self.size = size
        self.onRegenerate = onRegenerate
    }

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
        WidgetCard(type: .aiDailySummary, size: size) {
            if size == .small {
                if isLoading && summary == nil {
                    ProgressView().scaleEffect(0.8)
                } else if let text = summary {
                    Text(truncatedSummary(text, sentences: 1))
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                } else {
                    Text("Tap refresh to generate summary")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
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
                        let displayText = size == .medium ? truncatedSummary(text, sentences: 3) : text
                        Text((try? AttributedString(markdown: displayText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(displayText))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Click the refresh button to generate your AI daily summary")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

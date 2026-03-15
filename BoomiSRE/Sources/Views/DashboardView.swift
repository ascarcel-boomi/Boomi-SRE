import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel
    @StateObject private var vm = DashboardViewModel()
    @State private var showCustomize = false
    @State private var draggedWidget: DashboardWidget?

    // MOTD state
    @State private var currentMOTD = MOTDLibrary.messageOfTheMoment()
    @State private var motdOpacity: Double = 1.0

    var greeting: String { appState.userProfile.greeting }

    var enabledWidgets: [DashboardWidget] {
        if appState.dashboardMode == "auto" {
            return autoWidgets()   // builds its own list from ALL WidgetType.allCases
        }
        return appState.dashboardWidgets
            .filter(\.isEnabled)
            .sorted { $0.position < $1.position }
    }

    private func widgetIsConfigured(_ widget: DashboardWidget) -> Bool {
        switch widget.type {
        case .recentPRs: return !appState.githubToken.isEmpty
        case .jenkinsBuilds: return !appState.jenkinsToken.isEmpty
        case .grafanaAlerts: return !appState.grafanaToken.isEmpty
        case .jsmOpsAlerts: return appState.isJiraConfigured
        case .awsCostTrend: return !appState.awsSSOProfile.isEmpty
        case .upcomingCalendar, .unreadEmails: return appState.googleCredentials != nil
        case .confluenceRecent: return !appState.confluenceAPIToken.isEmpty
        case .myTickets, .activeIncidents: return appState.isJiraConfigured
        default: return true
        }
    }

    private func urgencyScore(for type: WidgetType) -> Int {
        var base: Int
        switch type {
        case .activeIncidents:
            let count = vm.activeIncidents.count
            if count == 0 { base = 5 }
            else { base = vm.activeIncidents.contains { $0.isHighPriority } ? 100 : 70 + min(count * 5, 25) }
        case .jsmOpsAlerts:
            let open = vm.jsmOpsAlerts.filter { $0.status.lowercased() == "open" && !$0.acknowledged }
            if open.isEmpty { base = 10 }
            else if open.contains(where: { $0.priority == "P1" }) { base = 95 }
            else if open.contains(where: { $0.priority == "P2" }) { base = 75 }
            else { base = 50 + min(open.count * 3, 20) }
        case .grafanaAlerts:
            base = vm.firingAlerts.isEmpty ? 8 : 60 + min(vm.firingAlerts.count * 10, 30)
        case .myTickets:
            if vm.myTickets.isEmpty { base = 5 }
            else {
                let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
                let overdue = vm.myTickets.filter { t in
                    guard let d = t.fields.duedate, !d.isEmpty else { return false }
                    return d < today
                }.count
                base = overdue > 0 ? 55 + min(overdue * 5, 20) : 30 + min(vm.myTickets.count * 2, 15)
            }
        case .jenkinsBuilds:
            let failed = vm.recentBuilds.filter { $0.build.result == "FAILURE" }.count
            base = failed == 0 ? 8 : 50 + min(failed * 10, 30)
        case .recentPRs:
            base = vm.recentPRs.isEmpty ? 5 : 20 + min(vm.recentPRs.count * 3, 15)
        case .unreadEmails:
            base = vm.unreadEmails.isEmpty ? 3 : 15 + min(vm.unreadEmails.count, 15)
        case .upcomingCalendar: base = vm.upcomingEvents.isEmpty ? 5 : 25
        case .quickActions: base = 20
        case .serviceHealth:
            let down = [appState.jiraAuthStatus, appState.githubAuthStatus,
                        appState.jenkinsAuthStatus, appState.grafanaAuthStatus]
                .filter { !$0.isOK }.count
            base = down > 0 ? 40 + down * 10 : 5
        case .awsCostTrend: base = 10
        case .confluenceRecent: base = 5
        case .aiDailySummary: base = 15
        case .notifications:
            let unread = vm.recentNotifications.filter { !$0.isRead }.count
            let highPri = vm.recentNotifications.filter { !$0.isRead && $0.type.isHighPriority }.count
            if highPri > 0 { base = 60 + min(highPri * 10, 20) } else if unread > 0 { base = 20 + min(unread * 2, 15) } else { base = 5 }
        case .onCallSchedule: base = 25
        }
        // Time-based escalation (Phase 37F)
        if let firstAlerted = vm.widgetFirstAlerted[type] {
            let mins = Date().timeIntervalSince(firstAlerted) / 60
            if mins > 480 { base += 20 } else if mins > 240 { base += 15 } else if mins > 60 { base += 10 }
        }
        return min(100, base)
    }

    private func widgetIsConfiguredByType(_ type: WidgetType) -> Bool {
        switch type {
        case .recentPRs: return !appState.githubToken.isEmpty
        case .jenkinsBuilds: return !appState.jenkinsToken.isEmpty
        case .grafanaAlerts: return !appState.grafanaToken.isEmpty
        case .jsmOpsAlerts: return appState.isJiraConfigured
        case .awsCostTrend: return !appState.awsSSOProfile.isEmpty
        case .upcomingCalendar, .unreadEmails: return appState.googleCredentials != nil
        case .confluenceRecent: return !appState.confluenceAPIToken.isEmpty
        case .myTickets, .activeIncidents: return appState.isJiraConfigured
        case .onCallSchedule: return appState.isJiraConfigured && !appState.favoriteJSMTeams.isEmpty
        case .notifications: return true
        default: return true
        }
    }

    private func widgetHasData(_ type: WidgetType) -> Bool {
        switch type {
        case .activeIncidents: return !vm.activeIncidents.isEmpty
        case .jsmOpsAlerts:    return !vm.jsmOpsAlerts.isEmpty
        case .grafanaAlerts:   return !vm.firingAlerts.isEmpty
        case .myTickets:       return !vm.myTickets.isEmpty
        case .jenkinsBuilds:   return !vm.recentBuilds.isEmpty
        case .recentPRs:       return !vm.recentPRs.isEmpty
        case .upcomingCalendar: return !vm.upcomingEvents.isEmpty
        case .unreadEmails:    return !vm.unreadEmails.isEmpty
        case .notifications:   return !vm.recentNotifications.isEmpty
        case .onCallSchedule:  return !vm.onCallSchedules.isEmpty
        case .confluenceRecent, .awsCostTrend: return false
        default: return true
        }
    }

    private func autoWidgets() -> [DashboardWidget] {
        // Auto mode builds its own list from ALL widget types — ignores user's custom config
        let configuredTypes = WidgetType.allCases.filter { widgetIsConfiguredByType($0) }

        var scored: [(type: WidgetType, urgency: Int)] = configuredTypes.map { t in
            (t, urgencyScore(for: t))
        }
        scored.sort { $0.urgency > $1.urgency }

        // Special: promote AI Summary to top when health is 95+
        if overallHealthScore >= 95,
           let aiIdx = scored.firstIndex(where: { $0.type == .aiDailySummary }) {
            scored.move(fromOffsets: IndexSet(integer: aiIdx), toOffset: 0)
        }

        return scored.enumerated().map { idx, pair in
            let hasData = widgetHasData(pair.type)
            let size: WidgetSize
            if !hasData {
                size = .small
            } else if pair.urgency >= 80 {
                size = .large
            } else if pair.urgency >= 40 {
                size = .medium
            } else {
                size = .small
            }
            if pair.type == .aiDailySummary && overallHealthScore >= 95 {
                return DashboardWidget(type: pair.type, position: idx, size: .large, isEnabled: true)
            }
            return DashboardWidget(type: pair.type, position: idx, size: size, isEnabled: true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(.title.bold())
                    Text(Date(), style: .date).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isLoading {
                    ProgressView().scaleEffect(0.8)
                }
                Button {
                    Task { await vm.refreshAll(appState: appState, notificationVM: notificationVM) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh all widgets")
                Button {
                    showCustomize = true
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Health score bar
            healthScoreBar

            ScrollView {
                VStack(spacing: 0) {
                    widgetGrid
                        .padding(20)

                    // MOTD — subtle footer card
                    MOTDView(message: currentMOTD) { cycleMOTD() }
                        .opacity(motdOpacity)
                        .animation(.easeInOut(duration: 0.3), value: motdOpacity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            currentMOTD = MOTDLibrary.messageOfTheMoment()
            Task { await vm.refreshAll(appState: appState, notificationVM: notificationVM) }
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            rotateMOTD(to: MOTDLibrary.messageOfTheMoment())
        }
        .onChange(of: appState.refreshTrigger) {
            rotateMOTD(to: MOTDLibrary.nextRandom(excluding: currentMOTD))
        }
        .sheet(isPresented: $showCustomize) {
            DashboardCustomizeView()
                .environmentObject(appState)
                .frame(minWidth: 560, minHeight: 720, maxHeight: 920)
        }
    }

    // MARK: - MOTD helpers

    private func cycleMOTD() {
        rotateMOTD(to: MOTDLibrary.nextRandom(excluding: currentMOTD))
    }

    private func rotateMOTD(to next: MOTDMessage) {
        withAnimation(.easeInOut(duration: 0.3)) { motdOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            currentMOTD = next
            withAnimation(.easeInOut(duration: 0.3)) { motdOpacity = 1 }
        }
    }

    // MARK: - Health Score

    var overallHealthScore: Int {
        var score = 100
        score -= vm.activeIncidents.filter(\.isHighPriority).count * 30
        for alert in vm.jsmOpsAlerts where alert.status == "open" && !alert.acknowledged {
            switch alert.priority {
            case "P1": score -= 15; case "P2": score -= 10; default: score -= 5
            }
        }
        score -= vm.firingAlerts.count * 10
        score -= vm.recentBuilds.filter { $0.build.result == "FAILURE" }.count * 5
        let statuses = [appState.jiraAuthStatus, appState.githubAuthStatus,
                        appState.jenkinsAuthStatus, appState.grafanaAuthStatus,
                        appState.confluenceAuthStatus, appState.bitbucketAuthStatus]
        score -= statuses.filter { if case .error = $0 { return true }; return false }.count * 5
        return max(0, min(100, score))
    }

    private var healthLabel: String {
        switch overallHealthScore {
        case 90...100: return "Excellent — all systems go 🟢"
        case 75..<90:  return "Good — a few items need attention 🟡"
        case 50..<75:  return "Needs Attention ⚠️"
        case 25..<50:  return "Critical — multiple issues 🔴"
        default:       return "Emergency — immediate action required 🚨"
        }
    }

    private var healthColor: Color {
        switch overallHealthScore {
        case 80...100: return .green
        case 50..<80:  return .yellow
        case 25..<50:  return .orange
        default:       return .red
        }
    }

    /// Build a concise summary of all alert sources that have issues
    private var alertSummaryParts: [(label: String, destination: String)] {
        var parts: [(String, String)] = []
        let jsmOpen = vm.jsmOpsAlerts.filter { $0.status.lowercased() == "open" && !$0.acknowledged }
        if !jsmOpen.isEmpty {
            let p1 = jsmOpen.filter { $0.priority == "P1" }.count
            let detail = p1 > 0 ? "\(jsmOpen.count) JSM (\(p1) P1)" : "\(jsmOpen.count) JSM alert\(jsmOpen.count == 1 ? "" : "s")"
            parts.append((detail, "oncall"))
        }
        if !vm.firingAlerts.isEmpty {
            parts.append(("\(vm.firingAlerts.count) Grafana alert\(vm.firingAlerts.count == 1 ? "" : "s")", "grafana_browser"))
        }
        let failed = vm.recentBuilds.filter { $0.build.result == "FAILURE" }.count
        if failed > 0 { parts.append(("\(failed) failed build\(failed == 1 ? "" : "s")", "jenkins_browser")) }
        let p12 = vm.activeIncidents.filter { $0.isHighPriority }.count
        if p12 > 0 { parts.append(("\(p12) P1/P2 incident\(p12 == 1 ? "" : "s")", "incidents")) }
        return parts
    }

    private var healthScoreBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.fill").foregroundStyle(healthColor)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("SRE Health").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(overallHealthScore)%").font(.caption.bold()).foregroundStyle(healthColor)
                    if overallHealthScore == 100 {
                        Text("· Perfect Score 🎉").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("· \(healthLabel)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                ProgressView(value: Double(overallHealthScore), total: 100)
                    .tint(healthColor).scaleEffect(x: 1, y: 1.5)
                // Alert summary line — clickable sources
                if !alertSummaryParts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(alertSummaryParts.enumerated()), id: \.offset) { _, part in
                            Button {
                                appState.selectedReport = ReportCatalog.all.first { $0.id == part.destination }
                                appState.showSettings = false
                            } label: {
                                Text(part.label).font(.caption2).foregroundStyle(.secondary)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            if part.label != alertSummaryParts.last?.label {
                                Text("·").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(healthColor.opacity(0.05))
    }

    // MARK: - Widget grid

    // Group consecutive non-large widgets into pairs for side-by-side layout
    private func widgetRows(from widgets: [DashboardWidget]) -> [[DashboardWidget]] {
        var rows: [[DashboardWidget]] = []
        var i = 0
        while i < widgets.count {
            if widgets[i].size == .large {
                rows.append([widgets[i]]); i += 1
            } else if i + 1 < widgets.count && widgets[i + 1].size != .large {
                rows.append([widgets[i], widgets[i + 1]]); i += 2
            } else {
                rows.append([widgets[i]]); i += 1
            }
        }
        return rows
    }

    @ViewBuilder
    private var widgetGrid: some View {
        LazyVStack(spacing: 16) {
            ForEach(widgetRows(from: enabledWidgets).indices, id: \.self) { rowIdx in
                let row = widgetRows(from: enabledWidgets)[rowIdx]
                if row.count == 2 {
                    HStack(spacing: 16) {
                        ForEach(row) { w in
                            draggableWidget(w)
                        }
                    }
                } else if let w = row.first {
                    draggableWidget(w)
                }
            }
        }
    }

    @ViewBuilder
    private func draggableWidget(_ widget: DashboardWidget) -> some View {
        widgetView(for: widget)
            .onDrag {
                draggedWidget = widget
                return NSItemProvider(object: widget.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: WidgetDropDelegate(
                item: widget,
                items: $appState.dashboardWidgets,
                draggedItem: $draggedWidget
            ))
            .opacity(draggedWidget?.id == widget.id ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: draggedWidget?.id)
    }

    @ViewBuilder
    private func widgetView(for widget: DashboardWidget) -> some View {
        switch widget.type {
        case .serviceHealth:
            ServiceHealthWidget(size: widget.size).environmentObject(appState)
        case .activeIncidents:
            ActiveIncidentsWidget(incidents: vm.activeIncidents, size: widget.size).environmentObject(appState)
        case .myTickets:
            MyTicketsWidget(tickets: vm.myTickets, size: widget.size).environmentObject(appState)
        case .recentPRs:
            RecentPRsWidget(prs: vm.recentPRs, size: widget.size).environmentObject(appState)
        case .jenkinsBuilds:
            JenkinsBuildsWidget(builds: vm.recentBuilds, size: widget.size).environmentObject(appState)
        case .grafanaAlerts:
            GrafanaAlertsWidget(alerts: vm.firingAlerts, size: widget.size).environmentObject(appState)
        case .jsmOpsAlerts:
            JSMOpsAlertsWidget(alerts: vm.jsmOpsAlerts, size: widget.size).environmentObject(appState)
        case .upcomingCalendar:
            CalendarWidget(events: vm.upcomingEvents, size: widget.size).environmentObject(appState)
        case .unreadEmails:
            EmailWidget(emails: vm.unreadEmails, size: widget.size).environmentObject(appState)
        case .quickActions:
            QuickActionsWidget(size: widget.size).environmentObject(appState)
        case .aiDailySummary:
            AIDailySummaryWidget(summary: vm.aiSummary, summaryDate: vm.aiSummaryDate, isLoading: vm.isLoading, size: widget.size) {
                Task { await vm.generateAISummary(appState: appState) }
            }
        case .awsCostTrend:
            WidgetCard(type: widget.type, size: widget.size) {
                Text("AWS cost trend — click Cost Explorer to view").font(.callout).foregroundStyle(.secondary)
            }
            .environmentObject(appState)
        case .confluenceRecent:
            WidgetCard(type: widget.type, size: widget.size) {
                Text("Recently updated Confluence pages").font(.callout).foregroundStyle(.secondary)
            }
            .environmentObject(appState)
        case .notifications:
            NotificationsWidget(notifications: vm.recentNotifications, size: widget.size)
                .environmentObject(appState)
        case .onCallSchedule:
            OnCallWidget(schedules: vm.onCallSchedules,
                         participants: vm.onCallParticipants,
                         displayNames: vm.onCallDisplayNames,
                         size: widget.size)
                .environmentObject(appState)
        }
    }
}

// MARK: - Widget Drop Delegate

struct WidgetDropDelegate: DropDelegate {
    let item: DashboardWidget
    @Binding var items: [DashboardWidget]
    @Binding var draggedItem: DashboardWidget?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem,
              dragged.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            for i in items.indices { items[i].position = i }
        }
        // Persist new order
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Dashboard Customize View

struct DashboardCustomizeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            HStack {
                Text("Customize Dashboard").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            // Fixed-height mode picker section
            VStack(alignment: .leading, spacing: 8) {
                Picker("Dashboard Mode", selection: $appState.dashboardMode) {
                    Text("Auto (AI-managed)").tag("auto")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.dashboardMode) { appState.saveConfig() }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
            Divider()

            // Remaining space: List (Custom) or scrollable explanation (Auto)
            if appState.dashboardMode == "auto" {
                ScrollView {
                    autoModeExplanation
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable/disable widgets and set sizes. Drag to reorder.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal).padding(.top, 8)
                    List {
                        ForEach($appState.dashboardWidgets
                            .sorted(by: { $0.position.wrappedValue < $1.position.wrappedValue }),
                                id: \.id) { $widget in
                            HStack(spacing: 12) {
                                Image(systemName: widget.type.icon).foregroundStyle(.secondary).frame(width: 20)
                                Toggle(widget.type.title, isOn: $widget.isEnabled)
                                    .toggleStyle(.switch)
                                    .onChange(of: widget.isEnabled) { appState.saveConfig() }
                                Spacer()
                                Picker("", selection: $widget.size) {
                                    Text("S").tag(WidgetSize.small)
                                    Text("M").tag(WidgetSize.medium)
                                    Text("L").tag(WidgetSize.large)
                                }
                                .pickerStyle(.segmented).frame(width: 90)
                                .onChange(of: widget.size) { appState.saveConfig() }
                            }
                        }
                        .onMove { source, destination in
                            appState.dashboardWidgets.move(fromOffsets: source, toOffset: destination)
                            for i in appState.dashboardWidgets.indices {
                                appState.dashboardWidgets[i].position = i
                            }
                            appState.saveConfig()
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func widgetDataSummary(_ type: WidgetType) -> String {
        switch type {
        case .activeIncidents:
            let count = appState.activeIncidentCount
            return count == 0 ? "No incidents" : "\(count) active"
        case .jsmOpsAlerts:
            let open = appState.dashboardWidgets.isEmpty ? 0 : 0  // placeholder
            return "\(open) alerts"
        case .grafanaAlerts:
            return "Grafana alerts"
        case .myTickets: return "My tickets"
        case .jenkinsBuilds: return "Jenkins builds"
        case .recentPRs: return "Open PRs"
        case .notifications: return "Notifications"
        case .onCallSchedule: return "On-call schedules"
        case .upcomingCalendar: return "Calendar events"
        case .unreadEmails: return "Unread emails"
        case .serviceHealth: return "Service health"
        case .quickActions: return "Quick actions"
        case .aiDailySummary: return "AI summary"
        default: return ""
        }
    }

    private var autoModeExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Dashboard Manager").font(.subheadline.bold())
            Text("Widgets are scored by urgency (0-100) and sorted automatically. Critical items appear large at the top; calm items shrink.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text("Live priorities:").font(.caption.bold()).foregroundStyle(.secondary)

            // Show all configured widget types with their current urgency
            let allTypes = WidgetType.allCases
            let scoredTypes = allTypes
                .map { t in (type: t, score: 0) }  // scores shown visually via dot
                .prefix(15)

            ForEach(allTypes.prefix(15), id: \.self) { wType in
                let size = appState.dashboardWidgets.first(where: { $0.type == wType })?.size ?? .small
                let sizeLabel = size == .large ? "Large" : size == .medium ? "Medium" : "Small"
                let sizeColor: Color = size == .large ? .red : size == .medium ? .orange : .green
                let dot: String = size == .large ? "🔴" : size == .medium ? "🟡" : "🟢"
                HStack(spacing: 6) {
                    Text(dot).font(.caption2)
                    Image(systemName: wType.icon).foregroundStyle(.secondary).frame(width: 14)
                    Text(wType.title).font(.caption)
                    Spacer()
                    Text(sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(sizeColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(sizeColor.opacity(0.1)))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }
}

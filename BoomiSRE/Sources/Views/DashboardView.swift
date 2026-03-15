import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel
    @StateObject private var vm = DashboardViewModel()
    @State private var showCustomize = false

    // MOTD state
    @State private var currentMOTD = MOTDLibrary.messageOfTheMoment()
    @State private var motdOpacity: Double = 1.0

    var greeting: String { appState.userProfile.greeting }

    var enabledWidgets: [DashboardWidget] {
        if appState.dashboardMode == "auto" {
            return autoWidgets()
        }
        return appState.dashboardWidgets
            .filter(\.isEnabled)
            .sorted { $0.position < $1.position }
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
        case .aiDailySummary: base = 25
        case .notifications:
            let unread = vm.recentNotifications.filter { !$0.isRead }.count
            let highPri = vm.recentNotifications.filter { !$0.isRead && $0.type.isHighPriority }.count
            if highPri > 0 { base = 60 + min(highPri * 10, 20) } else if unread > 0 { base = 20 + min(unread * 2, 15) } else { base = 5 }
        case .onCallSchedule: base = 25
        }
        // Time-based escalation
        if let firstAlerted = vm.widgetFirstAlerted[type] {
            let mins = Date().timeIntervalSince(firstAlerted) / 60
            if mins > 480 { base += 20 } else if mins > 240 { base += 15 } else if mins > 60 { base += 10 }
        }
        return min(100, base)
    }

    private func autoWidgets() -> [DashboardWidget] {
        let configured = WidgetType.allCases.filter { widgetIsConfiguredByType($0) }
        var scored = configured.map { (type: $0, urgency: urgencyScore(for: $0)) }
        scored.sort { $0.urgency > $1.urgency }
        if overallHealthScore >= 95, let aiIdx = scored.firstIndex(where: { $0.type == .aiDailySummary }) {
            scored.move(fromOffsets: IndexSet(integer: aiIdx), toOffset: 0)
        }
        return scored.enumerated().map { idx, pair in
            DashboardWidget(type: pair.type, position: idx, isEnabled: true)
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
                    switch appState.dashboardMode {
                    case "feed":
                        FeedView(items: vm.feedItems)
                            .environmentObject(appState)
                            .padding(20)
                    default:
                        widgetGrid.padding(20)
                    }

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
            appState.currentScreenContext = "Viewing Home Dashboard"
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            rotateMOTD(to: MOTDLibrary.messageOfTheMoment())
        }
        .onChange(of: appState.refreshTrigger) {
            rotateMOTD(to: MOTDLibrary.nextRandom(excluding: currentMOTD))
        }
        .onChange(of: appState.selectedProductId) {
            Task { await vm.refreshAll(appState: appState, notificationVM: notificationVM) }
        }
        .sheet(isPresented: $showCustomize) {
            DashboardCustomizeView()
                .environmentObject(appState)
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
            if let product = appState.selectedProduct, product.id != "all" {
                HStack(spacing: 4) {
                    Image(systemName: product.icon)
                        .font(.caption)
                    Text(product.shortName).font(.caption.bold())
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            }
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
                    let minsSaved = ProductivityTracker.shared.minutesSavedToday
                    if minsSaved > 0 {
                        Button {
                            appState.showSettings = true
                            appState.selectedSettingsTab = "productivity"
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath").font(.caption2)
                                Text("Saved \(ProductivityTracker.shared.timeSavedTodayFormatted)").font(.caption.bold())
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help("Estimated time saved today — click to see breakdown")
                    }
                }
                ProgressView(value: Double(overallHealthScore), total: 100)
                    .tint(healthColor).scaleEffect(x: 1, y: 1.5)
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

    private var widgetGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: appState.dashboardColumns)
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(enabledWidgets) { widget in
                widgetView(for: widget)
            }
        }
    }

    @ViewBuilder
    private func widgetView(for widget: DashboardWidget) -> some View {
        switch widget.type {
        case .serviceHealth:
            ServiceHealthWidget().environmentObject(appState)
        case .activeIncidents:
            ActiveIncidentsWidget(incidents: vm.activeIncidents).environmentObject(appState)
        case .myTickets:
            MyTicketsWidget(tickets: vm.myTickets).environmentObject(appState)
        case .recentPRs:
            RecentPRsWidget(prs: vm.recentPRs).environmentObject(appState)
        case .jenkinsBuilds:
            JenkinsBuildsWidget(builds: vm.recentBuilds).environmentObject(appState)
        case .grafanaAlerts:
            GrafanaAlertsWidget(alerts: vm.firingAlerts).environmentObject(appState)
        case .jsmOpsAlerts:
            JSMOpsAlertsWidget(alerts: vm.jsmOpsAlerts).environmentObject(appState)
        case .upcomingCalendar:
            CalendarWidget(events: vm.upcomingEvents).environmentObject(appState)
        case .unreadEmails:
            EmailWidget(emails: vm.unreadEmails).environmentObject(appState)
        case .quickActions:
            QuickActionsWidget().environmentObject(appState)
        case .aiDailySummary:
            AIDailySummaryWidget(summary: vm.aiSummary, summaryDate: vm.aiSummaryDate, isLoading: vm.isLoading) {
                Task { await vm.generateAISummary(appState: appState) }
            }
        case .awsCostTrend:
            WidgetCard(type: widget.type) {
                Text("AWS cost trend — click Cost Explorer to view").font(.callout).foregroundStyle(.secondary)
            }.environmentObject(appState)
        case .confluenceRecent:
            WidgetCard(type: widget.type) {
                Text("Recently updated Confluence pages").font(.callout).foregroundStyle(.secondary)
            }.environmentObject(appState)
        case .notifications:
            NotificationsWidget(notifications: vm.recentNotifications).environmentObject(appState)
        case .onCallSchedule:
            OnCallWidget(schedules: vm.onCallSchedules, participants: vm.onCallParticipants,
                         displayNames: vm.onCallDisplayNames).environmentObject(appState)
        }
    }
}

// MARK: - Dashboard Customize View

struct DashboardCustomizeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customize Dashboard").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            HStack(spacing: 20) {
                Picker("Mode", selection: $appState.dashboardMode) {
                    Text("Feed").tag("feed")
                    Text("Auto").tag("auto")
                    Text("Custom").tag("widgets")
                }
                .pickerStyle(.segmented).frame(width: 240)
                .onChange(of: appState.dashboardMode) { appState.saveConfig() }

                Picker("Columns", selection: $appState.dashboardColumns) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented).frame(width: 160)
                .onChange(of: appState.dashboardColumns) { appState.saveConfig() }

                Spacer()

                Button("Reset") {
                    appState.dashboardWidgets = DashboardWidget.defaults
                    appState.dashboardColumns = 3
                    appState.dashboardMode = "feed"
                    appState.saveConfig()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal).padding(.vertical, 10)
            Divider()

            if appState.dashboardMode == "feed" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Intelligent Feed — your default view.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("A single prioritized stream of everything that needs your attention. Critical alerts at the top, with inline actions. AI analysis is added automatically for the top items.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
                Spacer()
            } else if appState.dashboardMode == "auto" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI manages your dashboard automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Widgets are sorted by urgency — critical items at the top, calm items at the bottom.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
                Spacer()
            } else {
                List {
                    ForEach($appState.dashboardWidgets
                        .sorted(by: { $0.position.wrappedValue < $1.position.wrappedValue }),
                        id: \.id) { $widget in
                        HStack(spacing: 12) {
                            Image(systemName: widget.type.icon)
                                .foregroundStyle(widget.isEnabled ? Color.accentColor : .secondary)
                                .frame(width: 20)
                            Text(widget.type.title)
                                .foregroundStyle(widget.isEnabled ? .primary : .secondary)
                            Spacer()
                            Toggle("", isOn: $widget.isEnabled)
                                .toggleStyle(.switch).labelsHidden()
                                .onChange(of: widget.isEnabled) { appState.saveConfig() }
                        }
                    }
                    .onMove { source, destination in
                        appState.dashboardWidgets.move(fromOffsets: source, toOffset: destination)
                        for i in appState.dashboardWidgets.indices { appState.dashboardWidgets[i].position = i }
                        appState.saveConfig()
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 500)
    }
}

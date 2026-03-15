import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @State private var showCustomize = false
    @State private var draggedWidget: DashboardWidget?

    // MOTD state
    @State private var currentMOTD = MOTDLibrary.messageOfTheMoment()
    @State private var motdOpacity: Double = 1.0

    var greeting: String { appState.userProfile.greeting }

    var enabledWidgets: [DashboardWidget] {
        let widgets = appState.dashboardWidgets.filter(\.isEnabled)
            .sorted { $0.position < $1.position }
        if appState.dashboardMode == "auto" {
            return autoWidgets(from: widgets)
        }
        return widgets
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
        }
        // Time-based escalation added in Phase 37F
        return min(100, base)
    }

    private func autoWidgets(from widgets: [DashboardWidget]) -> [DashboardWidget] {
        let filtered = widgets.filter { widgetIsConfigured($0) }
        let sorted = filtered.map { (w: $0, s: urgencyScore(for: $0.type)) }
            .sorted { $0.s > $1.s }
        return sorted.enumerated().map { idx, pair in
            var w = pair.w; w.position = idx
            if pair.s >= 80 { w.size = .large }
            else if pair.s >= 40 { w.size = .medium }
            else { w.size = .small }
            return w
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
                    Task { await vm.refreshAll(appState: appState) }
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
            Task { await vm.refreshAll(appState: appState) }
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
                .frame(minWidth: 480, minHeight: 520)
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
            }
            .environmentObject(appState)
        case .confluenceRecent:
            WidgetCard(type: widget.type) {
                Text("Recently updated Confluence pages").font(.callout).foregroundStyle(.secondary)
            }
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
            HStack {
                Text("Customize Dashboard").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Dashboard Mode", selection: $appState.dashboardMode) {
                        Text("Auto (AI-managed)").tag("auto")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: appState.dashboardMode) { appState.saveConfig() }

                    if appState.dashboardMode == "auto" {
                        Text("AI automatically selects and prioritizes widgets based on your connected services and current activity.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Enable/disable widgets:").font(.subheadline.bold())
                        ForEach($appState.dashboardWidgets.sorted(by: { $0.position.wrappedValue < $1.position.wrappedValue }), id: \.id) { $widget in
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
                                .pickerStyle(.segmented)
                                .frame(width: 90)
                                .onChange(of: widget.size) { appState.saveConfig() }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}

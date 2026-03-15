import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @State private var showCustomize = false

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

    private func autoWidgets(from widgets: [DashboardWidget]) -> [DashboardWidget] {
        var result = widgets
        // If any P1/P2 incidents, promote incidents widget to top and make it large
        if appState.activeIncidentCount > 0,
           let idx = result.firstIndex(where: { $0.type == .activeIncidents }) {
            result[idx].size = .large
            let promoted = result.remove(at: idx)
            result.insert(promoted, at: 0)
        }
        // Remove widgets for unconfigured services
        result = result.filter { widget in
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
        return result
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

    @ViewBuilder
    private var widgetGrid: some View {
        let small  = enabledWidgets.filter { $0.size == .small }
        let medium = enabledWidgets.filter { $0.size == .medium }
        let large  = enabledWidgets.filter { $0.size == .large }

        VStack(spacing: 16) {
            // Small widgets in 2-col grid
            if !small.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(small) { widget in
                        widgetView(for: widget)
                    }
                }
            }
            // Medium widgets in 2-col grid
            if !medium.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(medium) { widget in
                        widgetView(for: widget)
                    }
                }
            }
            // Large widgets full width
            ForEach(large) { widget in
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

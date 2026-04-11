import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(NotificationViewModel.self) var notificationVM
    @Environment(UpdateViewModel.self) var updateVM
    @Environment(TeamPresenceViewModel.self) var presenceVM

    @State private var showGlobalSearch = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: appState.sidebarCollapsed ? 52 : 220)
                    .animation(.easeInOut(duration: 0.2), value: appState.sidebarCollapsed)

                Divider()

                VStack(spacing: 0) {
                    // Update available banner
                    if updateVM.showBanner, let update = updateVM.availableUpdate {
                        UpdateBanner(update: update, vm: updateVM)
                    }
                    BreadcrumbView()
                    detailContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(appState.appTheme == "boomi" ? BoomiColors.boomiPurple : nil)
        .onChange(of: appState.selectedSidebarItem) {
            // Clear ticket overlay when navigating via sidebar — prevents overlay from blocking
            if appState.selectedTicketKey != nil {
                appState.selectedTicketKey = nil
            }
            Task { await presenceVM.updatePresence(appState: appState) }
        }
        .onChange(of: appState.activeProductIds) {
            Task { await presenceVM.updatePresence(appState: appState) }
        }
        .task {
            if appState.peerPresenceEnabled { await presenceVM.start(appState: appState) }
        }
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "sidebar", placement: .navigation) {
                Button { appState.sidebarCollapsed.toggle() } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar (⌘⌥S)")
                .accessibilityLabel("Toggle Sidebar")
            }

            ToolbarItem(id: "back", placement: .navigation) {
                Button { appState.popNavigation() } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .accessibilityLabel("Navigate Back")
                .disabled(!appState.canGoBack)
            }

            ToolbarItem(id: "productContext", placement: .navigation) {
                Menu {
                    ForEach(appState.products.filter { $0.id != "all" }) { product in
                        Button {
                            if appState.activeProductIds.contains(product.id) {
                                appState.activeProductIds.remove(product.id)
                            } else {
                                appState.activeProductIds.insert(product.id)
                            }
                            appState.saveConfig()
                            ProductivityTracker.shared.log(.productContextSwitch, detail: "Toggled \(product.name)", source: "Product Context")
                        } label: {
                            Label(
                                appState.activeProductIds.contains(product.id) ? "✓ \(product.name)" : product.name,
                                systemImage: product.icon
                            )
                        }
                    }
                    Divider()
                    Button("Show All Teams") {
                        appState.activeProductIds = []
                        appState.saveConfig()
                    }
                    .disabled(appState.activeProductIds.isEmpty)
                    if !appState.userProfile.myProducts.isEmpty {
                        Button("My Teams") {
                            appState.activeProductIds = appState.userProfile.myProducts
                            appState.saveConfig()
                        }
                        .disabled(appState.activeProductIds == appState.userProfile.myProducts)
                    }
                    Divider()
                    Button("Manage Teams...") {
                        appState.showSettings = true
                        appState.selectedSettingsTab = "products"
                    }
                } label: {
                    HStack(spacing: 5) {
                        let count = appState.activeProductIds.count
                        if count == 0 {
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundStyle(.secondary)
                            Text("All Teams")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if count == 1, let product = appState.selectedProduct {
                            Image(systemName: product.icon)
                            Text(product.shortName)
                                .font(.callout.bold())
                        } else {
                            Image(systemName: "square.grid.2x2.fill")
                            Text("\(count) Teams")
                                .font(.callout.bold())
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(appState.activeProductIds.isEmpty
                                  ? Color.secondary.opacity(0.08)
                                  : Color.accentColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(appState.activeProductIds.isEmpty
                                    ? Color.clear
                                    : Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
                }
            }

            ToolbarItem(id: "refresh", placement: .primaryAction) {
                Button { appState.refreshTrigger = UUID() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh")
            }

            ToolbarItem(id: "search", placement: .primaryAction) {
                Button { showGlobalSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search (⌘F) — Navigate sections, search Jira & Confluence")
                .accessibilityLabel("Search")
                .keyboardShortcut("f", modifiers: .command)
            }

            ToolbarItem(id: "copilot", placement: .primaryAction) {
                Button {
                    appState.navigate(to: "copilot_chat")
                } label: {
                    Image(systemName: "sparkles")
                }
                .help("AI Copilot (⌘/)")
                .accessibilityLabel("AI Copilot")
            }

            ToolbarItem(id: "notifications", placement: .primaryAction) {
                Button {
                    appState.navigate(to: "notifications")
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                        if notificationVM.unreadCount > 0 {
                            Text("\(min(notificationVM.unreadCount, 99))")
                                .font(.system(size: 9).bold())
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .help("Notifications")
                .accessibilityLabel(notificationVM.unreadCount > 0
                    ? "Notifications, \(notificationVM.unreadCount) unread"
                    : "Notifications")
            }
        }
        .toolbarRole(.editor)
        .onChange(of: appState.selectedReport) { _, newValue in
            // Bridge deep links from feed/notifications to the correct sidebar section
            if let report = newValue {
                switch report.id {
                case "oncall", "notifications":
                    appState.selectedSidebarItem = "alerts"
                case "incidents":
                    appState.selectedSidebarItem = "incidents"
                case "jira_todo", "jira_filters", "jira_boards":
                    appState.selectedSidebarItem = "mywork"
                case "github_browser", "aws_health", "aws_cost_explorer", "bitbucket_browser", "jenkins_browser":
                    appState.selectedSidebarItem = "infra"
                case "knowledge_base", "confluence_browser", "exec_assistant":
                    appState.selectedSidebarItem = "knowledge"
                case "google_gmail", "google_calendar":
                    appState.selectedSidebarItem = "communicate"
                default:
                    break
                }
            }
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutTab)) { _ in
            appState.showSettings = true
            appState.selectedReport = nil
            appState.selectedSettingsTab = "about"
        }
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        if let ticketKey = appState.selectedTicketKey {
            TicketDetailView(ticketKey: ticketKey) {
                appState.selectedTicketKey = nil
            }
            .onAppear { ProductivityTracker.shared.log(.ticketViewedInApp, detail: ticketKey, source: "Jira") }
        } else if appState.showSettings {
            SettingsView()
        } else {
            // All navigation now goes through selectedSidebarItem.
            // selectedReport is cleared by navigate(to:) before setting selectedSidebarItem.
            switch appState.selectedSidebarItem {
            case "home":
                HomePanel()
            case "alerts":
                AlertsOnCallPanel()
            case "incidents":
                IncidentCommandView()
            case "mywork":
                MyWorkPanel()
            case "infra":
                InfrastructurePanel()
            case "knowledge":
                KnowledgeToolsPanel()
            case "communicate":
                CommunicatePanel()
            default:
                CopilotChatView()
            }
        }
    }

}

// MARK: - Global Search

private struct GlobalSearchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var jiraResults: [JiraIssue] = []
    @State private var confluenceResults: [ConfluenceService.ConfluencePage] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private let jiraService = JiraService()
    private let confluenceService = ConfluenceService()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Navigate sections or search Jira & Confluence…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { performSearch() }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(16)

            Divider()

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyPrompt
            } else {
                searchResults
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            jiraResults = []
            confluenceResults = []
            isSearching = false
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Navigate sections instantly, or press Enter to search Jira & Confluence")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Quick navigation matches
                let navMatches = ReportCatalog.all.filter {
                    $0.title.localizedCaseInsensitiveContains(query) ||
                    $0.description.localizedCaseInsensitiveContains(query)
                }
                if !navMatches.isEmpty {
                    Text("Navigation").font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 8)
                    ForEach(navMatches) { report in
                        Button {
                            appState.selectedReport = report
                            appState.showSettings = false
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: report.icon).frame(width: 20).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.title).font(.callout)
                                    Text(report.description).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.secondary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 8)
                    }
                }

                // Loading indicator
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching services...").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                }

                // Jira results
                if !jiraResults.isEmpty {
                    Text("Jira Tickets").font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 12)
                    ForEach(jiraResults, id: \.key) { issue in
                        Button {
                            appState.pushNavigation()
                            appState.selectedTicketKey = issue.key
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "ticket").frame(width: 20).foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(issue.key).font(.caption.bold())
                                        if let statusName = issue.fields.status?.name {
                                            Text(statusName).font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(issue.fields.summary ?? "").font(.callout).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Confluence results
                if !confluenceResults.isEmpty {
                    Text("Confluence Pages").font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 12)
                    ForEach(confluenceResults, id: \.id) { page in
                        Button {
                            if let url = URL(string: page.url) { NSWorkspace.shared.open(url) }
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.richtext").frame(width: 20).foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title).font(.callout).lineLimit(1)
                                    Text(page.spaceKey).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if navMatches.isEmpty && jiraResults.isEmpty && confluenceResults.isEmpty && !isSearching {
                    VStack(spacing: 8) {
                        Spacer(minLength: 40)
                        Text("No quick navigation matches for \"\(query)\"")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Press Enter to search Jira & Confluence")
                            .font(.caption).foregroundStyle(.tertiary)
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            defer { if !Task.isCancelled { isSearching = false } }

            async let jiraTask: [JiraIssue] = {
                guard appState.isJiraConfigured else { return [] }
                let isTicketKey = q.range(of: #"^[A-Z]+-\d+$"#, options: .regularExpression) != nil
                let jql = isTicketKey
                    ? "key = \"\(q)\""
                    : "text ~ \"\(q)\" ORDER BY updated DESC"
                do {
                    let result = try await jiraService.searchIssues(
                        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken, jql: jql,
                        fields: ["summary", "status", "priority", "issuetype", "assignee"],
                        maxResults: 8)
                    return result.issues
                } catch { return [] }
            }()

            async let confTask: [ConfluenceService.ConfluencePage] = {
                guard appState.isJiraConfigured else { return [] }
                do {
                    return try await confluenceService.searchPages(
                        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken, query: q, limit: 5)
                } catch { return [] }
            }()

            let (jira, conf) = await (jiraTask, confTask)
            guard !Task.isCancelled else { return }
            jiraResults = jira
            confluenceResults = conf
        }
    }
}

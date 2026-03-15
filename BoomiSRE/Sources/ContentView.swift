import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var updateVM: UpdateViewModel

    @State private var navigationHistory: [ReportItem?] = []
    @State private var showGlobalSearch = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: appState.sidebarCollapsed ? 50 : 220)
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
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "sidebar", placement: .navigation) {
                Button { appState.sidebarCollapsed.toggle() } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar (⌘⌥S)")
            }

            ToolbarItem(id: "back", placement: .navigation) {
                Button { navigateBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .disabled(navigationHistory.isEmpty)
            }

            ToolbarItem(id: "productContext", placement: .navigation) {
                Menu {
                    ForEach(appState.products) { product in
                        Button {
                            appState.selectedProductId = product.id
                            appState.saveConfig()
                        } label: {
                            Label(product.name, systemImage: product.icon)
                        }
                    }
                    Divider()
                    Button("Manage Products...") {
                        appState.showSettings = true
                        appState.selectedSettingsTab = "products"
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let product = appState.selectedProduct {
                            Image(systemName: product.icon)
                            Text(product.shortName)
                                .font(.callout.bold())
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
                }
            }

            ToolbarItem(id: "refresh", placement: .primaryAction) {
                Button { appState.refreshTrigger = UUID() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh (⌘R)")
            }

            ToolbarItem(id: "search", placement: .primaryAction) {
                Button { showGlobalSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
            }

            ToolbarItem(id: "copilot", placement: .primaryAction) {
                Button {
                    navigateTo("copilot_chat")
                } label: {
                    Image(systemName: "sparkles")
                }
                .help("AI Copilot (⌘/)")
            }

            ToolbarItem(id: "notifications", placement: .primaryAction) {
                Button {
                    navigateTo("notifications")
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
            }
        }
        .toolbarRole(.editor)
        .onChange(of: appState.selectedReport) { oldValue, newValue in
            // Push old value onto history stack (limit 20)
            if oldValue != newValue {
                navigationHistory.append(oldValue)
                if navigationHistory.count > 20 { navigationHistory.removeFirst() }
            }
            // Bridge deep links from feed/notifications to the correct sidebar section
            if let report = newValue {
                switch report.id {
                case "oncall", "notifications":
                    appState.selectedSidebarItem = "alerts"
                case "incidents":
                    appState.selectedSidebarItem = "incidents"
                case "jira_todo", "jira_filters", "jira_boards", "github_browser", "jenkins_browser":
                    appState.selectedSidebarItem = "mywork"
                case "aws_health", "aws_cost_explorer", "bitbucket_browser":
                    appState.selectedSidebarItem = "infra"
                case "knowledge_base", "confluence_browser", "copilot_chat", "exec_assistant":
                    appState.selectedSidebarItem = "knowledge"
                case "google_gmail", "google_calendar", "google_chat":
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
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        if let ticketKey = appState.selectedTicketKey {
            TicketDetailView(ticketKey: ticketKey) {
                appState.selectedTicketKey = nil
            }
        } else if appState.showSettings {
            SettingsView()
        } else if let report = appState.selectedReport {
            switch report.id {
            case "notifications":
                NotificationCenterView()
            case "knowledge_base":
                KnowledgeBaseView()
            case "oncall":
                OnCallView()
            case "incidents":
                IncidentCommandView()
            case "copilot_chat":
                CopilotChatView()
            case "exec_assistant":
                ExecAssistantView()
            case "github_browser":
                GitHubBrowserView()
            case "jenkins_browser":
                JenkinsBrowserView()
            case "grafana_browser":
                GrafanaBrowserView()
            case "confluence_browser":
                ConfluenceBrowserView()
            case "bitbucket_browser":
                BitbucketBrowserView()
            case "jira_todo":
                TodoDashboardView()
            case "jira_filters":
                SavedFiltersView()
            case "jira_boards":
                BoardsView()
            case "aws_health":
                AWSHealthView()
            case "aws_cost_explorer":
                CostExplorerView()
            case "google_gmail":
                GmailView()
            case "google_calendar":
                CalendarView()
            case "google_chat":
                ChatView()
            default:
                ReportDetailView(report: report)
            }
        } else {
            switch appState.selectedSidebarItem {
            case "home":
                DashboardView()
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
                DashboardView()
            }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ reportId: String) {
        appState.showSettings = false
        appState.selectedTicketKey = nil
        appState.selectedReport = ReportCatalog.all.first { $0.id == reportId }
    }

    private func navigateBack() {
        guard !navigationHistory.isEmpty else { return }
        let previous = navigationHistory.removeLast()
        appState.showSettings = false
        appState.selectedTicketKey = nil
        appState.selectedReport = previous
    }
}

// MARK: - Global Search

private struct GlobalSearchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Jira, GitHub, Jenkins, Confluence…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
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
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Search across Jira, GitHub, Jenkins, and Confluence")
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

                if navMatches.isEmpty {
                    VStack(spacing: 8) {
                        Spacer(minLength: 40)
                        Text("No quick navigation matches for \"\(query)\"")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Open a service (Jira, GitHub, etc.) to search within it.")
                            .font(.caption).foregroundStyle(.tertiary)
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

import SwiftUI

/// Combined My Work panel — Jira TODO, Saved Filters, Boards, Jenkins.
struct MyWorkPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "dashboard": 0, "jira_todo": 1, "jira_filters": 2, "jira_boards": 3, "jenkins_browser": 4
    ]
    private static let tabLabels = ["Dashboard", "Tickets", "Filters", "Boards", "Jenkins"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Dashboard").tag(0)
                Text("Tickets").tag(1)
                Text("Filters").tag(2)
                Text("Boards").tag(3)
                Text("Jenkins").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: DashboardView()
                case 1: TodoDashboardView()
                case 2: SavedFiltersView()
                case 3: BoardsView()
                case 4: JenkinsBrowserView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { consumePendingTab(); updateSubTab() }
        .onChange(of: appState.pendingTabId) { consumePendingTab() }
        .onChange(of: selectedTab) { updateSubTab() }
    }

    private func consumePendingTab() {
        if let id = appState.pendingTabId, let tab = Self.tabMap[id] {
            selectedTab = tab
            appState.pendingTabId = nil
        }
    }

    private func updateSubTab() {
        appState.currentSubTab = Self.tabLabels[selectedTab]
    }
}

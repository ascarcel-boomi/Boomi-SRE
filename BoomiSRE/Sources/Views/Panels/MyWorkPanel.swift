import SwiftUI

/// Combined My Work panel — Jira TODO, Saved Filters, Boards, Jenkins.
struct MyWorkPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "jira_todo": 0, "jira_filters": 1, "jira_boards": 2, "jenkins_browser": 3
    ]
    private static let tabLabels = ["Tickets", "Filters", "Boards", "Jenkins"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Tickets").tag(0)
                Text("Filters").tag(1)
                Text("Boards").tag(2)
                Text("Jenkins").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: TodoDashboardView()
                case 1: SavedFiltersView()
                case 2: BoardsView()
                case 3: JenkinsBrowserView()
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

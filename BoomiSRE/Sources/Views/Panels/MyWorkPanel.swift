import SwiftUI

/// Combined My Work panel — Jira Tickets, Saved Filters, Boards.
struct MyWorkPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "jira_todo": 0, "jira_filters": 1, "jira_boards": 2
    ]
    private static let tabLabels = ["Tickets", "Filters", "Boards"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Tickets").tag(0)
                Text("Filters").tag(1)
                Text("Boards").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: TodoDashboardView()
                case 1: SavedFiltersView()
                case 2: BoardsView()
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
        // Store the tabMap key (not the display label) so popNavigation can restore it via pendingTabId
        let key = Self.tabMap.first(where: { $0.value == selectedTab })?.key
        appState.currentSubTab = key ?? Self.tabLabels[selectedTab]
    }
}

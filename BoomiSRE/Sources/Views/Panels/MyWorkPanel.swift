import SwiftUI

/// Combined My Work panel — Jira TODO, Saved Filters, Boards, GitHub PRs, Jenkins.
struct MyWorkPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Tickets").tag(0)
                Text("Filters").tag(1)
                Text("Boards").tag(2)
                Text("GitHub").tag(3)
                Text("Jenkins").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: TodoDashboardView()
                case 1: SavedFiltersView()
                case 2: BoardsView()
                case 3: GitHubBrowserView()
                case 4: JenkinsBrowserView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

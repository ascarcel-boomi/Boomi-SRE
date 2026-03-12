import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let ticketKey = appState.selectedTicketKey {
                TicketDetailView(ticketKey: ticketKey) {
                    appState.selectedTicketKey = nil
                }
            } else if appState.showSettings {
                SettingsView()
            } else if let report = appState.selectedReport {
                switch report.id {
                case "jira_todo":
                    TodoDashboardView()
                case "jira_filters":
                    SavedFiltersView()
                default:
                    ReportDetailView(report: report)
                }
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

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
                case "copilot_chat":
                    CopilotChatView()
                case "exec_assistant":
                    ExecAssistantView()
                case "jira_todo":
                    TodoDashboardView()
                case "jira_filters":
                    SavedFiltersView()
                case "jira_boards":
                    BoardsView()
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
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

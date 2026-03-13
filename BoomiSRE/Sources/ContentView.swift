import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: appState.sidebarCollapsed ? 50 : 220)
                .animation(.easeInOut(duration: 0.2), value: appState.sidebarCollapsed)

            Divider()

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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
            DashboardView()
        }
    }
}

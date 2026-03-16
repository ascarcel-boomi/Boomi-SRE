import SwiftUI

/// A thin breadcrumb trail at the top of the detail pane showing current location.
struct BreadcrumbView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            crumbs
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        Divider()
    }

    @ViewBuilder
    private var crumbs: some View {
        if let ticketKey = appState.selectedTicketKey {
            // Home > My Work > My TODO > CAMSRE-1234
            homeButton
            separator
            Text("My Work")
                .font(.callout)
                .foregroundStyle(.secondary)
            separator
            Button("My TODO") {
                appState.selectedTicketKey = nil
                appState.navigate(to: "jira_todo")
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(Color.accentColor)
            separator
            Text(ticketKey)
                .font(.callout)
                .foregroundStyle(.secondary)

        } else if appState.showSettings {
            // Home > Settings
            homeButton
            separator
            Text("Settings")
                .font(.callout)
                .foregroundStyle(.secondary)

        } else if appState.selectedSidebarItem != "home" {
            // Home > [Section]
            homeButton
            separator
            Text(sidebarLabel(appState.selectedSidebarItem))
                .font(.callout)
                .foregroundStyle(.secondary)

        } else {
            // Dashboard — already home
            Text("Home")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func sidebarLabel(_ item: String) -> String {
        switch item {
        case "alerts":     return "Alerts & On-Call"
        case "incidents":  return "Incidents"
        case "mywork":     return "My Work"
        case "infra":      return "Infrastructure"
        case "knowledge":  return "Knowledge & Tools"
        case "communicate": return "Communicate"
        default:           return item.capitalized
        }
    }

    private var homeButton: some View {
        Button("Home") {
            appState.showSettings = false
            appState.selectedTicketKey = nil
            appState.selectedReport = nil
            appState.selectedSidebarItem = "home"
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(Color.accentColor)
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

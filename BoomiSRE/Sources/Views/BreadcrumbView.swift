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
            // My Work > Tickets > CAMSRE-1234
            sectionButton("mywork")
            separator
            Button("Tickets") {
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
            Text("Settings")
                .font(.callout)
                .foregroundStyle(.secondary)

        } else if appState.selectedSidebarItem == "home" {
            Text("Home")
                .font(.callout)
                .foregroundStyle(.secondary)

        } else {
            // Section > Sub-tab
            sectionButton(appState.selectedSidebarItem)
            if let subTab = appState.currentSubTab {
                separator
                Text(subTab)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sidebarLabel(_ item: String) -> String {
        switch item {
        case "alerts":      return "Alerts & On-Call"
        case "incidents":   return "Incidents"
        case "mywork":      return "My Work"
        case "infra":       return "Infrastructure"
        case "knowledge":   return "Knowledge & Tools"
        case "communicate": return "Communicate"
        default:            return item.capitalized
        }
    }

    private func sectionButton(_ item: String) -> some View {
        Button(sidebarLabel(item)) {
            // Navigate to section (clears sub-tab)
            appState.showSettings = false
            appState.selectedTicketKey = nil
            appState.selectedReport = nil
            appState.selectedSidebarItem = item
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(appState.currentSubTab != nil ? Color.accentColor : .secondary)
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

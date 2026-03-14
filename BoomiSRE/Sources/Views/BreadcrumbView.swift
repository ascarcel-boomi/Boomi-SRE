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
            // Home > Work > My TODO > CAMSRE-1234
            homeButton
            separator
            Text(ReportSection.work.rawValue)
                .font(.callout)
                .foregroundStyle(.secondary)
            separator
            Button("My TODO") {
                appState.selectedTicketKey = nil
                appState.selectedReport = ReportCatalog.all.first { $0.id == "jira_todo" }
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

        } else if let report = appState.selectedReport {
            // Home > [Section] > [Page]
            homeButton
            separator
            Text(report.section.rawValue)
                .font(.callout)
                .foregroundStyle(.secondary)
            separator
            Text(report.title)
                .font(.callout)
                .foregroundStyle(.secondary)

        } else {
            // Dashboard — already home
            Text("Home")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var homeButton: some View {
        Button("Home") {
            appState.selectedReport = nil
            appState.showSettings = false
            appState.selectedTicketKey = nil
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

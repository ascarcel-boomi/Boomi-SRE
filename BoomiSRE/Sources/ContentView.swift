import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.showSettings {
                SettingsView()
            } else if let report = appState.selectedReport {
                ReportDetailView(report: report)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

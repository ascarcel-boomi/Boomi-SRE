import SwiftUI

/// Combined Alerts & On-Call panel — wraps On-Call, Grafana, and Notifications in tabs.
struct AlertsOnCallPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    // Held here so it survives tab switches — OnCallView reads it via @EnvironmentObject
    @StateObject private var onCallVM = OnCallViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("On-Call").tag(0)
                Text("Grafana").tag(1)
                Text("Notifications").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: OnCallView().environmentObject(onCallVM)
                case 1: GrafanaBrowserView()
                case 2: NotificationCenterView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { appState.currentScreenContext = "Viewing Alerts & On-Call" }
    }
}

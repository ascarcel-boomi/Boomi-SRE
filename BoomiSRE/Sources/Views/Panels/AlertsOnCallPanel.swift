import SwiftUI

/// Combined Alerts & On-Call panel — wraps On-Call, Grafana, and Notifications in tabs.
struct AlertsOnCallPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @EnvironmentObject private var onCallVM: OnCallViewModel

    private static let tabMap: [String: Int] = [
        "oncall": 0, "grafana_browser": 1, "notifications": 2
    ]
    private static let tabLabels = ["On-Call", "Grafana", "Notifications"]

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
        appState.currentSubTab = Self.tabLabels[selectedTab]
    }
}

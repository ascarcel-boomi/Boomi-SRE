import SwiftUI

/// Combined Alerts & On-Call panel — wraps On-Call, Grafana, SLOs, and Notifications in tabs.
struct AlertsOnCallPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @EnvironmentObject private var onCallVM: OnCallViewModel

    private static let tabMap: [String: Int] = [
        "oncall": 0, "grafana_browser": 1, "slo_dashboard": 2, "notifications": 3
    ]
    private static let tabLabels = ["On-Call", "Grafana", "SLOs", "Notifications"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("On-Call").tag(0)
                Text("Grafana").tag(1)
                Text("SLOs").tag(2)
                Text("Notifications").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: OnCallView().environmentObject(onCallVM)
                case 1: GrafanaBrowserView()
                case 2: SLODashboardView()
                case 3: NotificationCenterView()
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

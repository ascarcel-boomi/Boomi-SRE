import SwiftUI

/// Home panel: Dashboard (default) + AI Copilot as second tab.
struct HomePanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var selectedTab = "dashboard"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("Dashboard", id: "dashboard")
                tabButton("AI Copilot", id: "copilot")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            Divider()

            Group {
                switch selectedTab {
                case "copilot":
                    CopilotChatView()
                default:
                    DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            consumePendingTab()
            if appState.pendingTabId == nil {
                appState.currentSubTab = tabLabel(for: selectedTab)
            }
        }
        .onChange(of: appState.pendingTabId) { consumePendingTab() }
        .onChange(of: selectedTab) {
            appState.currentSubTab = tabLabel(for: selectedTab)
        }
    }

    private func tabLabel(for id: String) -> String {
        id == "copilot" ? "AI Copilot" : "Dashboard"
    }

    private func consumePendingTab() {
        guard let pending = appState.pendingTabId else { return }
        selectedTab = (pending == "copilot_chat" || pending == "copilot") ? "copilot" : "dashboard"
        appState.pendingTabId = nil
        appState.currentSubTab = tabLabel(for: selectedTab)
    }

    private func tabButton(_ label: String, id: String) -> some View {
        Button {
            selectedTab = id
            appState.currentSubTab = label
        } label: {
            Text(label)
                .font(.subheadline.weight(selectedTab == id ? .semibold : .regular))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(selectedTab == id ? Color.accentColor.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

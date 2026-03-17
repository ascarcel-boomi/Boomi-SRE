import SwiftUI

/// Combined Communicate panel — Gmail, Calendar, Chat.
struct CommunicatePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "google_gmail": 0, "google_calendar": 1, "google_chat": 2
    ]
    private static let tabLabels = ["Gmail", "Calendar", "Chat"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Gmail").tag(0)
                Text("Calendar").tag(1)
                Text("Chat").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: GmailView()
                case 1: CalendarView()
                case 2: ChatView()
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

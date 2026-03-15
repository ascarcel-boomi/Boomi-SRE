import SwiftUI

/// Combined Communicate panel — Gmail, Calendar, Chat.
struct CommunicatePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

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
        .onAppear { appState.currentScreenContext = "Viewing Communicate — Gmail, Calendar, Chat" }
    }
}

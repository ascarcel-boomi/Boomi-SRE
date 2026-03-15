import SwiftUI

/// Combined Knowledge & Tools panel — KB, Confluence, AI Copilot, Exec Assistant.
struct KnowledgeToolsPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Knowledge Base").tag(0)
                Text("Confluence").tag(1)
                Text("AI Copilot").tag(2)
                Text("Exec Assistant").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: KnowledgeBaseView()
                case 1: ConfluenceBrowserView()
                case 2: CopilotChatView()
                case 3: ExecAssistantView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { appState.currentScreenContext = "Viewing Knowledge & Tools" }
    }
}

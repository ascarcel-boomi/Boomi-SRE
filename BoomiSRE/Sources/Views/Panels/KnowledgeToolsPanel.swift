import SwiftUI

/// Combined Knowledge & Tools panel — KB, Confluence, AI Copilot, Exec Assistant, Skills.
struct KnowledgeToolsPanel: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var kbViewModel = KnowledgeBaseViewModel()
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "knowledge_base": 0, "confluence_browser": 1, "copilot_chat": 2, "exec_assistant": 3, "skills": 4
    ]
    private static let tabLabels = ["Knowledge Base", "Confluence", "AI Copilot", "Exec Assistant", "Skills"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Knowledge Base").tag(0)
                Text("Confluence").tag(1)
                Text("AI Copilot").tag(2)
                Text("Exec Assistant").tag(3)
                Text("Skills").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: KnowledgeBaseView(vm: kbViewModel)
                case 1: ConfluenceBrowserView()
                case 2: CopilotChatView()
                case 3: ExecAssistantView()
                case 4: SkillsManagerView()
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

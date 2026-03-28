import SwiftUI

/// Combined Knowledge & Tools panel — KB, Confluence, AI Copilot, Exec Assistant, Skills.
struct KnowledgeToolsPanel: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var kbViewModel = KnowledgeBaseViewModel()
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "knowledge_base": 0, "confluence_browser": 1, "exec_assistant": 2, "skills": 3
    ]
    private static let tabLabels = ["Knowledge Base", "Confluence", "Exec Assistant", "Skills"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Knowledge Base").tag(0)
                Text("Confluence").tag(1)
                Text("Exec Assistant").tag(2)
                Text("Skills").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: KnowledgeBaseView(vm: kbViewModel)
                case 1: ConfluenceBrowserView()
                case 2: ExecAssistantView()
                case 3: SkillsManagerView()
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

import SwiftUI

/// Combined Knowledge & Tools panel — KB, Confluence, Exec Assistant.
struct KnowledgeToolsPanel: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var kbViewModel = KnowledgeBaseViewModel()
    @State private var selectedTab = 0
    @State private var pendingKBFilterConsumed = false

    private static let tabMap: [String: Int] = [
        "knowledge_base": 0, "confluence_browser": 1, "exec_assistant": 2
    ]
    private static let tabLabels = ["Knowledge Base", "Confluence", "Exec Assistant"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Knowledge Base").tag(0)
                Text("Confluence").tag(1)
                Text("Exec Assistant").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: KnowledgeBaseView(vm: kbViewModel)
                case 1: ConfluenceBrowserView()
                case 2: ExecAssistantView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { consumePendingTab(); consumePendingKBFilter(); updateSubTab() }
        .onChange(of: appState.pendingTabId) { consumePendingTab() }
        .onChange(of: appState.pendingKBFilter) { consumePendingKBFilter() }
        .onChange(of: selectedTab) { updateSubTab() }
    }

    private func consumePendingTab() {
        if let id = appState.pendingTabId, let tab = Self.tabMap[id] {
            selectedTab = tab
            appState.pendingTabId = nil
        }
    }

    private func consumePendingKBFilter() {
        if let filter = appState.pendingKBFilter {
            selectedTab = 0 // Go to Knowledge Base tab
            if filter == "SOPs" {
                kbViewModel.categoryFilter = .sop
            }
            appState.pendingKBFilter = nil
        }
    }

    private func updateSubTab() {
        appState.currentSubTab = Self.tabLabels[selectedTab]
    }
}

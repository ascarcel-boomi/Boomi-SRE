import SwiftUI

/// Combined Infrastructure panel — Cloud Providers, Source Control, Automation/CI-CD.
struct InfrastructurePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "aws_health": 0, "aws_cost_explorer": 1, "github_browser": 2, "bitbucket_browser": 3, "jenkins_browser": 4
    ]
    private static let tabLabels = ["AWS Health", "AWS Costs", "GitHub", "Bitbucket", "Jenkins"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("AWS Health").tag(0)
                Text("AWS Costs").tag(1)
                Text("GitHub").tag(2)
                Text("Bitbucket").tag(3)
                Text("Jenkins").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: AWSHealthView()
                case 1: CostExplorerView()
                case 2: GitHubBrowserView()
                case 3: BitbucketBrowserView()
                case 4: JenkinsBrowserView()
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

import SwiftUI

/// Combined Infrastructure panel — Cloud Providers, Source Control, Automation/CI-CD.
struct InfrastructurePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    private static let tabMap: [String: Int] = [
        "aws_health": 0, "aws_cost_explorer": 1, "github_browser": 2, "bitbucket_browser": 3, "jenkins_browser": 4
    ]
    private static let tabLabels = ["AWS Health", "AWS Costs", "GitHub", "Bitbucket", "Jenkins"]

    // Tab groups for categorized display
    private struct TabGroup {
        let label: String
        let tabs: [(title: String, tag: Int)]
    }

    private let tabGroups: [TabGroup] = [
        TabGroup(label: "Cloud Providers", tabs: [("AWS Health", 0), ("AWS Costs", 1)]),
        TabGroup(label: "Source Control",  tabs: [("GitHub", 2), ("Bitbucket", 3)]),
        TabGroup(label: "Automation",      tabs: [("Jenkins", 4)])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Categorized tab bar
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(tabGroups.enumerated()), id: \.offset) { groupIdx, group in
                    if groupIdx > 0 {
                        Divider()
                            .frame(height: 28)
                            .padding(.horizontal, 6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        HStack(spacing: 4) {
                            ForEach(group.tabs, id: \.tag) { tab in
                                Button {
                                    selectedTab = tab.tag
                                } label: {
                                    Text(tab.title)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(selectedTab == tab.tag
                                                      ? Color.accentColor.opacity(0.15)
                                                      : Color.clear)
                                        )
                                        .foregroundStyle(selectedTab == tab.tag ? Color.accentColor : .primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedTab == tab.tag
                                                        ? Color.accentColor.opacity(0.5)
                                                        : Color.clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

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
        // Store the tabMap key (not the display label) so popNavigation can restore it via pendingTabId
        let key = Self.tabMap.first(where: { $0.value == selectedTab })?.key
        appState.currentSubTab = key ?? Self.tabLabels[selectedTab]
    }
}

import SwiftUI

/// Combined Infrastructure panel — AWS Health, AWS Costs, Bitbucket.
struct InfrastructurePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("AWS Health").tag(0)
                Text("AWS Costs").tag(1)
                Text("Bitbucket").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: AWSHealthView()
                case 1: CostExplorerView()
                case 2: BitbucketBrowserView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { appState.currentScreenContext = "Viewing Infrastructure & DevOps" }
    }
}

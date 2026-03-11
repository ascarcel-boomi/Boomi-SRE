import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Boomi SRE Reports")
                .font(.largeTitle.bold())

            Text("Select a report from the sidebar to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "dollarsign.circle", color: .green,
                           text: "AWS Cost Reports — multi-account cost analysis and trends")
                FeatureRow(icon: "chart.bar.xaxis", color: .blue,
                           text: "Jira / SRE Analytics — coming soon via Jira API")
            }
            .padding(.top, 8)

            // Auth status cards — all 5 services
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                authCard(service: "AWS SSO", icon: "cloud",
                         status: appState.awsAuthStatus)
                authCard(service: "Jira", icon: "ticket",
                         status: appState.jiraAuthStatus)
                authCard(service: "Confluence", icon: "book.closed",
                         status: appState.confluenceAuthStatus)
                authCard(service: "Bitbucket", icon: "externaldrive.connected.to.line.below",
                         status: appState.bitbucketAuthStatus)
                authCard(service: "GitHub", icon: "chevron.left.forwardslash.chevron.right",
                         status: appState.githubAuthStatus)
            }
            .padding(.top, 12)
            .frame(maxWidth: 700)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func authCard(service: String, icon: String, status: AuthStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(status.color)
                Text(service)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(status.color)
                    .frame(width: 10, height: 10)
            }
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(status.color.opacity(0.3)))
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

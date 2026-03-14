import SwiftUI

/// Settings panel for JSM Operations — team discovery and on-call favorites.
struct JSMSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var isDiscovering = false
    @State private var discoveredTeams: [OpsTeam] = []
    @State private var discoveryError: String?
    @State private var saved = false

    private let service = JSMOpsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("JSM Operations").font(.title2.bold())

            // KB Repo settings
            SettingsSection("Knowledge Base Repository") {
                Text("Configure the GitHub repository used for SOPs, runbooks, and guides.")
                    .font(.callout).foregroundStyle(.secondary)
                FieldRow(label: "Owner", text: $appState.kbRepoOwner, placeholder: "ascarcel-boomi")
                FieldRow(label: "Repository", text: $appState.kbRepoName, placeholder: "mashery-sre-kb")
                HStack {
                    Button("Save") { saveKBRepo() }
                        .buttonStyle(.borderedProminent)
                    if saved {
                        Text("Saved").font(.caption).foregroundStyle(.green)
                    }
                }
            }

            Divider()

            // On-Call team favorites
            SettingsSection("On-Call Teams") {
                Text("Discover your JSM Operations teams, then select favorites to display on the On-Call dashboard. Requires Jira credentials with JSM Operations access.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task { await discoverTeams() }
                    } label: {
                        if isDiscovering {
                            HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Discovering…") }
                        } else {
                            Label("Discover Teams", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDiscovering || !appState.isJiraConfigured)

                    if !appState.isJiraConfigured {
                        Text("Configure Jira credentials first")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let err = discoveryError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                let teams = discoveredTeams.isEmpty ? appState.discoveredJSMTeams : discoveredTeams
                if !teams.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(teams.count) teams found — select favorites:")
                            .font(.callout.bold())

                        ForEach(teams) { team in
                            HStack(spacing: 10) {
                                Toggle(isOn: Binding(
                                    get: { appState.favoriteJSMTeams.contains(team.id) },
                                    set: { on in
                                        if on {
                                            if !appState.favoriteJSMTeams.contains(team.id) {
                                                appState.favoriteJSMTeams.append(team.id)
                                            }
                                        } else {
                                            appState.favoriteJSMTeams.removeAll { $0 == team.id }
                                        }
                                        appState.saveConfig()
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(team.name).font(.callout)
                                        if let desc = team.description, !desc.isEmpty {
                                            Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                }

                if !appState.favoriteJSMTeams.isEmpty {
                    Text("\(appState.favoriteJSMTeams.count) team(s) selected as favorite")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            // Pre-populate from saved teams if available
            discoveredTeams = appState.discoveredJSMTeams
        }
    }

    private func saveKBRepo() {
        appState.saveConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func discoverTeams() async {
        isDiscovering = true
        discoveryError = nil
        do {
            let teams = try await service.listTeams(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            discoveredTeams = teams
            appState.discoveredJSMTeams = teams
            appState.saveConfig()
        } catch {
            discoveryError = error.localizedDescription
        }
        isDiscovering = false
    }
}

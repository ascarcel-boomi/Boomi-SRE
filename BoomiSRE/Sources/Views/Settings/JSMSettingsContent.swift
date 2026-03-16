import SwiftUI

/// Settings panel for JSM Operations — team/schedule discovery and on-call favorites.
/// On-call and schedules use your existing Jira credentials — no separate API key needed.
struct JSMSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var isDiscovering = false
    @State private var discoveredTeams: [OpsTeam] = []
    @State private var discoveryError: String?
    @State private var saved = false
    @State private var testResult: String?
    @State private var testIsError = false
    @State private var isTesting = false

    private let service = JSMOpsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("JSM Operations").font(.title2.bold())

            // ── Auth Info ──────────────────────────────────────────────────
            SettingsSection("Authentication") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("JSM Operations uses your existing Jira credentials — no separate API key needed.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                if !appState.isJiraConfigured {
                    Label("Jira not configured — add credentials in Settings → Jira first",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Using: \(appState.jiraEmail)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting { HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Testing…") } }
                        else { Label("Test Connection", systemImage: "checkmark.shield") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || !appState.isJiraConfigured)

                    if let result = testResult {
                        Label(result, systemImage: testIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(testIsError ? .red : .green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            // ── KB Repo settings ──────────────────────────────────────────
            SettingsSection("Knowledge Base Repository") {
                Text("Configure the GitHub repository used for SOPs, runbooks, and guides.")
                    .font(.callout).foregroundStyle(.secondary)
                FieldRow(label: "Owner", text: $appState.kbRepoOwner, placeholder: "ascarcel-boomi")
                FieldRow(label: "Repository", text: $appState.kbRepoName, placeholder: "mashery-sre-kb")
                HStack {
                    Button("Save") { saveKBRepo() }.buttonStyle(.borderedProminent)
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }

            Divider()

            // ── On-Call team/schedule favorites ──────────────────────────
            SettingsSection("On-Call Teams & Schedules") {
                Text("Discover your JSM Operations teams and schedules, then select favorites to display on the On-Call dashboard.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task { await discoverTeams() }
                    } label: {
                        if isDiscovering { HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Discovering…") } }
                        else { Label("Discover Teams & Schedules", systemImage: "magnifyingglass") }
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
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }

                let teams = discoveredTeams.isEmpty ? appState.discoveredJSMTeams : discoveredTeams
                if !teams.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(teams.count) teams/schedules found — select favorites:").font(.callout.bold())
                        ForEach(teams) { team in
                            Toggle(isOn: Binding(
                                get: { appState.favoriteJSMTeams.contains(team.id) },
                                set: { on in
                                    if on { if !appState.favoriteJSMTeams.contains(team.id) { appState.favoriteJSMTeams.append(team.id) } }
                                    else { appState.favoriteJSMTeams.removeAll { $0 == team.id } }
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
                            .toggleStyle(.checkbox).padding(.vertical, 2)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                }

                if !appState.favoriteJSMTeams.isEmpty {
                    Text("\(appState.favoriteJSMTeams.count) item(s) selected as favorite")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            discoveredTeams = appState.discoveredJSMTeams
            // Auto-discover teams if favorites are saved but team names haven't been fetched
            if appState.discoveredJSMTeams.isEmpty && !appState.favoriteJSMTeams.isEmpty && appState.isJiraConfigured {
                Task { await discoverTeams() }
            }
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true; testResult = nil
        do {
            let schedules = try await service.listSchedules(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            testResult = schedules.isEmpty
                ? "Connected — no schedules visible (check your JSM access)"
                : "Connected — found \(schedules.count) schedule(s)"
            testIsError = false
            appState.jsmOpsAuthStatus = .authenticated(detail: "\(schedules.count) schedules")
        } catch {
            testResult = error.localizedDescription
            testIsError = true
            appState.jsmOpsAuthStatus = .error(error.localizedDescription)
        }
        isTesting = false
    }

    private func saveKBRepo() {
        appState.saveConfig(); saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func discoverTeams() async {
        isDiscovering = true; discoveryError = nil
        do {
            // Try teams first, fall back to schedules
            var teams = try await service.listTeams(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            if teams.isEmpty {
                let schedules = try await service.listSchedules(
                    baseURL: appState.jiraBaseURL,
                    email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken
                )
                teams = schedules.map { OpsTeam(id: $0.id, name: $0.name, description: nil) }
            }
            discoveredTeams = teams
            appState.discoveredJSMTeams = teams
            appState.saveConfig()
        } catch { discoveryError = error.localizedDescription }
        isDiscovering = false
    }
}

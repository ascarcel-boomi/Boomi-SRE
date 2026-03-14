import SwiftUI

/// Settings panel for JSM Operations — JSM Ops API key, team discovery, and on-call favorites.
struct JSMSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyField = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testIsError = false
    @State private var isDiscovering = false
    @State private var discoveredTeams: [OpsTeam] = []
    @State private var discoveryError: String?
    @State private var saved = false

    private let service = JSMOpsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("JSM Operations").font(.title2.bold())

            // ── JSM Operations API Key ──────────────────────────────────────────
            SettingsSection("JSM Operations API Key") {
                Text("The JSM Operations (On-Call & Alerts) API uses a **separate API key** from your Jira token. It is created in JSM Ops Settings, not at id.atlassian.com.")
                    .font(.callout).foregroundStyle(.secondary)

                // Step-by-step guide
                VStack(alignment: .leading, spacing: 10) {
                    guideStep(1, "Open JSM Ops Integrations in your browser",
                              linkURL: URL(string: "https://boomii.atlassian.net/jira/ops/integrations"),
                              linkLabel: "Open boomii.atlassian.net/jira/ops/integrations")
                    guideStep(2, "Click \"Add integration\"\nSearch for \"API\" and select it", linkURL: nil, linkLabel: nil)
                    guideStep(3, "Name it \"Boomi SRE App\"\nOptionally assign to your team for team-scoped access\nClick \"Continue\"", linkURL: nil, linkLabel: nil)
                    guideStep(4, "Expand \"Steps to configure the integration\"\nCopy the API key\nClick \"Turn on integration\"", linkURL: nil, linkLabel: nil)
                    guideStep(5, "Paste the API key below", linkURL: nil, linkLabel: nil)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))

                Text("If you don't see the Integrations page, navigate from your team dashboard: Teams → [Your Team] → Integrations → Add integration.")
                    .font(.caption).foregroundStyle(.secondary)

                // Key field
                HStack(spacing: 8) {
                    SecureField("Paste your JSM Ops API key…", text: $apiKeyField)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            apiKeyField = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                if apiKeyField.isEmpty, !appState.jsmOpsAPIKey.isEmpty {
                    Text("Current key: ••••\(appState.jsmOpsAPIKey.suffix(4))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        if isTesting { HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Testing…") } }
                        else { Label("Test & Save", systemImage: "checkmark.shield") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyField.isEmpty || isTesting)

                    if let result = testResult {
                        Label(result, systemImage: testIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(testIsError ? .red : .green)
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

            // ── On-Call team favorites ────────────────────────────────────
            SettingsSection("On-Call Teams") {
                Text("Discover your JSM Operations teams, then select favorites to display on the On-Call dashboard.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task { await discoverTeams() }
                    } label: {
                        if isDiscovering { HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Discovering…") } }
                        else { Label("Discover Teams", systemImage: "magnifyingglass") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDiscovering || appState.jsmOpsAPIKey.isEmpty)

                    if appState.jsmOpsAPIKey.isEmpty {
                        Text("Save a JSM Ops API key above first")
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
                        Text("\(teams.count) teams found — select favorites:").font(.callout.bold())
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
                    Text("\(appState.favoriteJSMTeams.count) team(s) selected as favorite")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            discoveredTeams = appState.discoveredJSMTeams
        }
    }

    // MARK: - Helpers

    private func guideStep(_ n: Int, _ text: String, linkURL: URL?, linkLabel: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 22, height: 22)
                Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.callout)
                if let url = linkURL, let label = linkLabel {
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 4) { Image(systemName: "arrow.up.right.square"); Text(label) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
    }

    private func testAndSave() async {
        isTesting = true; testResult = nil
        let key = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.jsmOpsAPIKey = key
        do {
            let schedules = try await service.listSchedules(apiKey: key)
            testResult = "Connected — found \(schedules.count) schedule(s)"
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
            let schedules = try await service.listSchedules(apiKey: appState.jsmOpsAPIKey)
            let teams = schedules.map { OpsTeam(id: $0.id, name: $0.name, description: nil) }
            discoveredTeams = teams
            appState.discoveredJSMTeams = teams
            appState.saveConfig()
        } catch { discoveryError = error.localizedDescription }
        isDiscovering = false
    }
}

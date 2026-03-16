import SwiftUI

struct ProductSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var discoveredTeams: [OpsTeam] = []
    @State private var isDiscoveringTeams = false
    @State private var discoveryError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Product Contexts").font(.title2.bold())
            Text("Configure which data each product context filters. When you select a product at the top of the app, only matching data is shown.")
                .font(.callout).foregroundStyle(.secondary)

            // JSM Team discovery (shared across all products)
            SettingsSection("JSM Team Discovery") {
                Text("Discover your JSM Ops teams to configure on-call filtering per product.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        Task { await discoverTeams() }
                    } label: {
                        if isDiscoveringTeams {
                            HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Discovering...") }
                        } else {
                            Label("Discover Teams", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDiscoveringTeams)

                    if !discoveredTeams.isEmpty {
                        Text("\(discoveredTeams.count) teams found").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let err = discoveryError {
                    Label(err, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
                }
                if !discoveredTeams.isEmpty {
                    Text("Discovered teams — assign to products below:")
                        .font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(discoveredTeams) { team in
                            Text("• \(team.name)").font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 8)
                }
            }

            Divider()

            List {
                ForEach($appState.products.filter { $0.id.wrappedValue != "all" }, id: \.id) { $product in
                    DisclosureGroup(product.name) {
                        VStack(alignment: .leading, spacing: 12) {
                            // JSM Teams — checkboxes if discovered, text field otherwise
                            SettingsSection("JSM Ops Teams") {
                                if !discoveredTeams.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(discoveredTeams) { team in
                                            Toggle(team.name, isOn: Binding(
                                                get: { product.jsmTeamIds.contains(team.id) },
                                                set: { on in
                                                    if on {
                                                        if !product.jsmTeamIds.contains(team.id) {
                                                            product.jsmTeamIds.append(team.id)
                                                        }
                                                    } else {
                                                        product.jsmTeamIds.removeAll { $0 == team.id }
                                                    }
                                                    appState.saveConfig()
                                                }
                                            ))
                                            .toggleStyle(.checkbox)
                                        }
                                    }
                                } else {
                                    TextField("Team IDs (comma-separated)", text: Binding(
                                        get: { product.jsmTeamIds.joined(separator: ", ") },
                                        set: {
                                            product.jsmTeamIds = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                            appState.saveConfig()
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .help("Click 'Discover Teams' above to see team names")
                                }
                            }

                            SettingsSection("Jira Projects") {
                                TextField("Project keys (e.g., CAMSRE, SRE)", text: Binding(
                                    get: { product.jiraProjectKeys.joined(separator: ", ") },
                                    set: {
                                        product.jiraProjectKeys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            SettingsSection("Jenkins Job Patterns") {
                                TextField("Patterns (e.g., *mashery*, *cam*)", text: Binding(
                                    get: { product.jenkinsJobPatterns.joined(separator: ", ") },
                                    set: {
                                        product.jenkinsJobPatterns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            SettingsSection("GitHub Repo Patterns") {
                                TextField("Patterns (e.g., apim-sre-*)", text: Binding(
                                    get: { product.githubRepoPatterns.joined(separator: ", ") },
                                    set: {
                                        product.githubRepoPatterns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            SettingsSection("Incident Product Elements") {
                                TextField("Elements (e.g., Cloud API Management (Mashery))", text: Binding(
                                    get: { product.incidentProductElements.joined(separator: ", ") },
                                    set: {
                                        product.incidentProductElements = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            SettingsSection("Product Description") {
                                TextEditor(text: Binding(
                                    get: { product.productDescription },
                                    set: { product.productDescription = $0; appState.saveConfig() }
                                ))
                                .font(.callout)
                                .frame(minHeight: 60)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            }

                            SettingsSection("Architecture Notes") {
                                TextEditor(text: Binding(
                                    get: { product.architectureNotes },
                                    set: { product.architectureNotes = $0; appState.saveConfig() }
                                ))
                                .font(.callout)
                                .frame(minHeight: 80)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            }

                            SettingsSection("Key Runbooks") {
                                TextField("Runbook paths (comma-separated)", text: Binding(
                                    get: { product.keyRunbooks.joined(separator: ", ") },
                                    set: {
                                        product.keyRunbooks = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            SettingsSection("Common Alert Patterns (one per line)") {
                                TextEditor(text: Binding(
                                    get: { product.commonAlertPatterns.joined(separator: "\n") },
                                    set: {
                                        product.commonAlertPatterns = $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .font(.callout)
                                .frame(minHeight: 80)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 300)

            HStack {
                Button("Reset to Defaults") {
                    appState.products = ProductContext.defaults
                    appState.saveConfig()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private func discoverTeams() async {
        isDiscoveringTeams = true
        discoveryError = nil
        // Use already-discovered teams from JSM settings
        discoveredTeams = appState.discoveredJSMTeams
        if discoveredTeams.isEmpty {
            discoveryError = "No teams found. Configure JSM Ops in Settings \u{2192} JSM Ops first."
        }
        isDiscoveringTeams = false
    }
}

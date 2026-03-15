import SwiftUI

struct ProductSettingsContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Product Contexts").font(.title2.bold())
            Text("Configure which data each product context filters. When you select a product at the top of the app, only matching data is shown.")
                .font(.callout).foregroundStyle(.secondary)

            List {
                ForEach($appState.products.filter { $0.id.wrappedValue != "all" }, id: \.id) { $product in
                    DisclosureGroup(product.name) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSection("JSM Ops Teams") {
                                TextField("Team IDs (comma-separated)", text: Binding(
                                    get: { product.jsmTeamIds.joined(separator: ", ") },
                                    set: {
                                        product.jsmTeamIds = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        appState.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
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
}

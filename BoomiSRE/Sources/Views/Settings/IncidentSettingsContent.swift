import SwiftUI

struct IncidentSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var isDiscovering = false
    @State private var discoveryResult: String?
    @State private var discoveryIsError = false
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var searchText = ""

    private let jiraService = JiraService()

    var filteredElements: [String] {
        if searchText.isEmpty { return appState.availableProductElements }
        return appState.availableProductElements.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    var generatedJQL: String {
        if appState.useCustomIncidentJQL, !appState.customIncidentJQL.isEmpty {
            return appState.customIncidentJQL
        }
        var clauses = ["project = \"Boomi Incident Management\""]
        if !appState.favoriteProductElements.isEmpty {
            let elements = appState.favoriteProductElements.map { "\"\($0)\"" }.joined(separator: ", ")
            clauses.append("\"product element[select list (multiple choices)]\" IN (\(elements))")
        }
        return clauses.joined(separator: "\n  AND ") + "\nORDER BY created DESC, priority DESC"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Incident Command").font(.title2.bold())

            // Product Elements section
            SettingsSection("Product Elements") {
                // Product context banner
                if !appState.products.filter({ $0.id != "all" }).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill").foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Product elements are now managed per product in **Products & Resources**.")
                                .font(.caption)
                            Text("The selections below are used as a fallback when no product is selected.")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Manage Products") {
                            appState.selectedSettingsTab = "products"
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                        .fill(Color.accentColor.opacity(0.06)))
                }

                Text("Discover and select product elements. These are used as defaults when no product filter is active.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task { await discoverProductElements() }
                    } label: {
                        if isDiscovering {
                            HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Discovering…") }
                        } else {
                            Label("Discover Product Elements", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDiscovering || !appState.isJiraConfigured)

                    if !appState.availableProductElements.isEmpty {
                        Button("Select All") {
                            appState.favoriteProductElements = appState.availableProductElements
                            appState.saveConfig()
                        }
                        .buttonStyle(.bordered)

                        Button("Deselect All") {
                            appState.favoriteProductElements = []
                            appState.saveConfig()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let result = discoveryResult {
                    Label(result, systemImage: discoveryIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(discoveryIsError ? .red : .green)
                }

                if appState.availableProductElements.isEmpty {
                    Text(appState.isJiraConfigured
                         ? "Click 'Discover' to load product elements from Jira."
                         : "Configure Jira first to discover product elements.")
                        .font(.callout).foregroundStyle(.secondary)
                        .italic()
                } else {
                    TextField("Search product elements…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)

                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredElements, id: \.self) { element in
                            Toggle(element, isOn: Binding(
                                get: { appState.favoriteProductElements.contains(element) },
                                set: { on in
                                    if on {
                                        appState.favoriteProductElements.append(element)
                                    } else {
                                        appState.favoriteProductElements.removeAll { $0 == element }
                                    }
                                    appState.saveConfig()
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Query Preview section
            SettingsSection("Query Preview") {
                Text("JQL that will be used to fetch incidents:")
                    .font(.callout).foregroundStyle(.secondary)

                Text(appState.favoriteProductElements.isEmpty && !appState.useCustomIncidentJQL
                     ? "No product elements selected — all incidents in 'Boomi Incident Management' will be shown."
                     : generatedJQL)
                    .font(.callout.monospaced())
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button {
                        Task { await testQuery() }
                    } label: {
                        if isTesting {
                            HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Testing…") }
                        } else {
                            Label("Test Query", systemImage: "play.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || !appState.isJiraConfigured)

                    if let result = testResult {
                        Text(result).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            // Advanced section
            SettingsSection("Advanced") {
                Toggle("Use custom JQL instead of product element filters", isOn: $appState.useCustomIncidentJQL)
                    .onChange(of: appState.useCustomIncidentJQL) { appState.saveConfig() }

                if appState.useCustomIncidentJQL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom JQL Override").font(.subheadline)
                        TextEditor(text: $appState.customIncidentJQL)
                            .font(.callout.monospaced())
                            .frame(minHeight: 80)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            .onChange(of: appState.customIncidentJQL) { appState.saveConfig() }
                    }
                }

                if !appState.incidentProductElementFieldId.isEmpty {
                    Text("Field ID: \(appState.incidentProductElementFieldId)")
                        .font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func discoverProductElements() async {
        guard appState.isJiraConfigured else { return }
        isDiscovering = true
        discoveryResult = nil

        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)

        do {
            // Step 1: Find the product element field ID
            let fields = try await jiraService.getCustomFields(baseURL: baseURL, email: email, apiToken: token)
            guard let match = fields.first(where: { $0.name.lowercased().contains("product element") }) else {
                discoveryResult = "Could not find 'product element' field. Check that it exists in your Jira instance."
                discoveryIsError = true
                isDiscovering = false
                return
            }
            await MainActor.run { appState.incidentProductElementFieldId = match.id }

            // Step 2: Discover available values by sampling incidents
            let elements = try await jiraService.discoverProductElements(
                baseURL: baseURL, email: email, apiToken: token,
                productElementFieldId: match.id
            )
            await MainActor.run {
                appState.availableProductElements = elements
                appState.saveConfig()
                if elements.isEmpty {
                    discoveryResult = "No product elements found. Check that the 'Boomi Incident Management' project exists and has incidents."
                    discoveryIsError = true
                } else {
                    discoveryResult = "Found \(elements.count) product elements."
                    discoveryIsError = false
                }
            }
        } catch {
            await MainActor.run {
                discoveryResult = "Error: \(error.localizedDescription)"
                discoveryIsError = true
            }
        }
        await MainActor.run { isDiscovering = false }
    }

    private func testQuery() async {
        guard appState.isJiraConfigured else { return }
        isTesting = true
        testResult = nil

        let jql: String
        if appState.useCustomIncidentJQL, !appState.customIncidentJQL.isEmpty {
            jql = appState.customIncidentJQL
        } else {
            var clauses = ["project = \"Boomi Incident Management\""]
            if !appState.favoriteProductElements.isEmpty {
                let elements = appState.favoriteProductElements.map { "\"\($0)\"" }.joined(separator: ", ")
                clauses.append("\"product element[select list (multiple choices)]\" IN (\(elements))")
            }
            jql = clauses.joined(separator: " AND ") + " ORDER BY created DESC"
        }

        do {
            let result = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: jql,
                fields: ["summary"],
                maxResults: 1
            )
            let total = result.total ?? result.issues.count
            await MainActor.run {
                testResult = "Found \(total) incident(s) matching your filters."
            }
        } catch {
            await MainActor.run {
                testResult = "Error: \(error.localizedDescription)"
            }
        }
        await MainActor.run { isTesting = false }
    }
}

# Boomi SRE App — Phase 45: Product Context System

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. This is the first phase of a major evolution (see `docs/VISION_V2.md` for the full vision).

**Read these files first:**
- `docs/VISION_V2.md` — the full vision document (read Phase A section)
- `BoomiSRE/Sources/Models/AppState.swift` — current state: `favoriteJSMTeams`, `favoriteJiraProjects`, `favoriteGitHubRepos`, `favoriteJenkinsJobs`, `favoriteGrafanaDashboards`, `favoriteConfluenceSpaces`, `favoriteProductElements`
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — `OpsTeam` model
- `BoomiSRE/Sources/Views/DashboardView.swift` — current home page
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching (loads alerts, tickets, PRs, builds, etc.)
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar with 8 sections
- `BoomiSRE/Sources/Views/Settings/IncidentSettingsContent.swift` — existing product element filtering (working pattern to follow)

---

## Goal

Add a **Product Context Switcher** to the app. When an SRE selects a product (e.g., "CAM SRE"), the entire app filters to show only data relevant to that product: only CAM alerts, CAM on-call schedules, CAM Jira tickets, CAM GitHub repos, CAM Jenkins jobs, and CAM runbooks.

This is the foundation for horizontal scaling — any SRE can cover any product by switching context with a single click.

---

## Implementation

### Phase 45A: Define the Product Model

Create `BoomiSRE/Sources/Models/ProductContext.swift`:

```swift
import Foundation

struct ProductContext: Identifiable, Codable, Hashable {
    var id: String                    // unique slug: "cam-sre", "mft-sre", etc.
    var name: String                  // display name: "CAM SRE (Mashery)"
    var shortName: String             // compact: "CAM"
    var icon: String                  // SF Symbol: "shield.checkmark"
    var color: String                 // accent color name: "orange", "blue", etc.

    // Service filters — when this product is selected, filter data by these values
    var jsmTeamIds: [String]          // JSM Ops team IDs for on-call and alerts
    var jiraProjectKeys: [String]     // Jira project keys (e.g., ["CAMSRE"])
    var incidentProductElements: [String]  // Incident "product element" values
    var githubRepoPatterns: [String]  // repo name patterns (e.g., ["apim-sre-*", "mashery-*"])
    var bitbucketRepoPatterns: [String]
    var jenkinsJobPatterns: [String]  // job name patterns (e.g., ["*mashery*", "*cam*"])
    var grafanaDashboardTags: [String] // Grafana dashboard tags to filter by
    var grafanaFolders: [String]      // Grafana folder titles
    var confluenceSpaceKeys: [String] // Confluence space keys
    var kbTags: [String]             // Knowledge Base article tags for this product

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ProductContext, rhs: ProductContext) -> Bool { lhs.id == rhs.id }
}

extension ProductContext {
    /// Predefined product contexts for Boomi SRE.
    /// Users can customize these in Settings, but these are the starting defaults.
    static let defaults: [ProductContext] = [
        ProductContext(
            id: "all",
            name: "All Products",
            shortName: "All",
            icon: "square.grid.2x2",
            color: "gray",
            jsmTeamIds: [],           // empty = don't filter (show all)
            jiraProjectKeys: [],
            incidentProductElements: [],
            githubRepoPatterns: [],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: [],
            grafanaDashboardTags: [],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: []
        ),
        ProductContext(
            id: "cam-sre",
            name: "CAM SRE (Mashery)",
            shortName: "CAM",
            icon: "shield.checkmark",
            color: "orange",
            jsmTeamIds: ["og-90b86004-f391-4213-9742-3c0f47d8731b"],  // "CAM SRE" team
            jiraProjectKeys: ["CAMSRE"],
            incidentProductElements: ["Cloud API Management (Mashery)"],
            githubRepoPatterns: ["apim-sre-*", "mashery-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mashery*", "*cam*", "*apim*"],
            grafanaDashboardTags: ["mashery", "cam", "apim"],
            grafanaFolders: [],
            confluenceSpaceKeys: ["camsre", "CAMSRE"],
            kbTags: ["cam", "mashery", "apim"]
        ),
        ProductContext(
            id: "mft-sre",
            name: "MFT SRE (Thru)",
            shortName: "MFT",
            icon: "doc.on.doc",
            color: "blue",
            jsmTeamIds: ["314953fc-b4e1-4be0-bc6a-3267a30e98e1"],  // "MFT SRE" team
            jiraProjectKeys: ["MFTSRE", "MFT"],
            incidentProductElements: ["Managed File Transfer"],
            githubRepoPatterns: ["mft-*", "thru-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mft*", "*thru*"],
            grafanaDashboardTags: ["mft", "thru"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["mft", "thru"]
        ),
        ProductContext(
            id: "di-sre",
            name: "DI SRE (Rivery)",
            shortName: "DI",
            icon: "arrow.triangle.branch",
            color: "green",
            jsmTeamIds: ["c8007b3c-41c7-4135-ae9c-8a73f9e48576"],  // "Data Integration - DevOps"
            jiraProjectKeys: ["DISRE", "DI"],
            incidentProductElements: ["Data Integration"],
            githubRepoPatterns: ["di-*", "rivery-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*rivery*", "*data-integration*"],
            grafanaDashboardTags: ["rivery", "di"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["di", "rivery"]
        ),
        ProductContext(
            id: "mcs-sre",
            name: "MCS SRE",
            shortName: "MCS",
            icon: "cloud",
            color: "purple",
            jsmTeamIds: ["og-4b28ccc3-f6b6-436c-b18b-ce8e204f4465"],  // "Managed Cloud Service - SRE"
            jiraProjectKeys: ["MCS"],
            incidentProductElements: ["Managed Cloud Services"],
            githubRepoPatterns: ["mcs-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mcs*"],
            grafanaDashboardTags: ["mcs"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["mcs"]
        ),
        ProductContext(
            id: "boomi-sre",
            name: "Boomi SRE (Platform)",
            shortName: "Platform",
            icon: "server.rack",
            color: "red",
            jsmTeamIds: ["og-d8192695-a28f-4cf5-96c9-8a806f5bc90a"],  // "SRE_Operations_On-Call"
            jiraProjectKeys: ["SRE"],
            incidentProductElements: ["Boomi Platform", "Boomi Runtime"],
            githubRepoPatterns: ["boomi-*", "platform-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*boomi*", "*platform*"],
            grafanaDashboardTags: ["boomi", "platform", "runtime"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["boomi", "platform", "runtime"]
        ),
    ]
}
```

### Phase 45B: Add Product Context to AppState

Add to `AppState`:

```swift
// Product Context
@Published var products: [ProductContext] = ProductContext.defaults
@Published var selectedProductId: String = "all"   // "all" = no filter

var selectedProduct: ProductContext? {
    products.first { $0.id == selectedProductId }
}

/// Returns true if the selected product is "All Products" (no filtering)
var isAllProducts: Bool { selectedProductId == "all" }
```

Persist `products` and `selectedProductId` in `~/.boomi_sre_config.json`.

### Phase 45C: Add Product Context Switcher to the App Header

Add a **product dropdown** to the top of the app — visible on every screen.

In `ContentView.swift` or the top-level layout, add a toolbar item or a dropdown in the header area:

```swift
// Product context picker — always visible at the top
Menu {
    ForEach(appState.products) { product in
        Button {
            appState.selectedProductId = product.id
            appState.saveConfig()
        } label: {
            Label(product.name, systemImage: product.icon)
        }
    }
    Divider()
    Button("Manage Products...") {
        appState.showSettings = true
        appState.selectedSettingsTab = "products"
    }
} label: {
    HStack(spacing: 6) {
        if let product = appState.selectedProduct {
            Image(systemName: product.icon)
            Text(product.shortName)
                .font(.callout.bold())
        }
        Image(systemName: "chevron.down")
            .font(.caption2)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
}
```

Place this in the toolbar area, between the sidebar toggle and the search/refresh buttons. It should be prominent but not overwhelming — the SRE should see their current product context at a glance.

### Phase 45D: Filter Dashboard Data by Product

In `DashboardViewModel`, add product filtering to every data loader.

**Create a generic pattern match helper:**
```swift
/// Check if a string matches any of the given patterns (case-insensitive, wildcard *)
private func matchesAny(_ value: String, patterns: [String]) -> Bool {
    if patterns.isEmpty { return true }  // empty patterns = no filter (show all)
    let lower = value.lowercased()
    return patterns.contains { pattern in
        let p = pattern.lowercased()
        if p.hasPrefix("*") && p.hasSuffix("*") {
            return lower.contains(String(p.dropFirst().dropLast()))
        } else if p.hasPrefix("*") {
            return lower.hasSuffix(String(p.dropFirst()))
        } else if p.hasSuffix("*") {
            return lower.hasPrefix(String(p.dropLast()))
        } else {
            return lower == p
        }
    }
}
```

**Filter each data source:**

```swift
// In loadJSMOpsAlerts:
let product = appState.selectedProduct
if let p = product, !p.jsmTeamIds.isEmpty {
    jsmOpsAlerts = allAlerts.filter { alert in
        alert.responders.contains { r in p.jsmTeamIds.contains(r.id) }
    }
}

// In loadJiraTickets:
if let p = product, !p.jiraProjectKeys.isEmpty {
    let projectFilter = p.jiraProjectKeys.map { "\"\($0)\"" }.joined(separator: ", ")
    jql = "assignee = currentUser() AND project IN (\(projectFilter)) AND statusCategory NOT IN (Done) ORDER BY priority ASC"
}

// In loadRecentPRs:
if let p = product, !p.githubRepoPatterns.isEmpty {
    // Filter repos by pattern before fetching PRs
    repos = repos.filter { matchesAny($0.name, patterns: p.githubRepoPatterns) }
}

// In loadJenkinsBuilds:
if let p = product, !p.jenkinsJobPatterns.isEmpty {
    targetJobs = jobs.filter { matchesAny($0.name, patterns: p.jenkinsJobPatterns) }
}

// In loadGrafanaAlerts:
if let p = product, !p.grafanaDashboardTags.isEmpty {
    // Filter alert rules by tags if available
    firingAlerts = rules.filter { rule in
        rule.state.lowercased() == "alerting" &&
        (p.grafanaDashboardTags.isEmpty || rule.labels.keys.contains(where: { p.grafanaDashboardTags.contains($0.lowercased()) }))
    }
}

// In loadIncidents:
if let p = product, !p.incidentProductElements.isEmpty {
    let elements = p.incidentProductElements.map { "\"\($0)\"" }.joined(separator: ", ")
    jql += " AND \"product element[select list (multiple choices)]\" IN (\(elements))"
}

// In loadOnCall:
if let p = product, !p.jsmTeamIds.isEmpty {
    // Only load schedules for this product's teams
    let teamSchedules = allSchedules.filter { s in
        p.jsmTeamIds.contains(s.teamId ?? "")
    }
    // Load on-call for these schedules only
}
```

The key rule: **if the product filter arrays are empty, don't filter (show all)**. This makes "All Products" work by having empty arrays.

### Phase 45E: Refresh When Product Changes

When the user switches products, the dashboard should refresh:

```swift
// In DashboardView:
.onChange(of: appState.selectedProductId) {
    Task { await vm.refreshAll(appState: appState, notificationVM: notificationVM) }
}
```

Also update the On-Call view, Incidents view, and any other view that loads data — they should re-fetch when the product context changes. The simplest approach: each view's `.onAppear` already fetches data using `appState` — since `appState.selectedProduct` changes, the next fetch will use the new filter. But for the dashboard specifically, trigger an immediate refresh.

### Phase 45F: Product Configuration in Settings

Add a "Products" tab to Settings where the user can customize each product's filters:

```swift
// Settings → Products tab
struct ProductSettingsContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Product Contexts").font(.headline)
            Text("Configure which data each product context filters. When you select a product at the top of the app, only matching data is shown.")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach($appState.products.filter { $0.id.wrappedValue != "all" }) { $product in
                    DisclosureGroup(product.name) {
                        // JSM Team IDs
                        Section("JSM Ops Teams") {
                            TextField("Team IDs (comma-separated)", text: Binding(
                                get: { product.jsmTeamIds.joined(separator: ", ") },
                                set: { product.jsmTeamIds = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                        }
                        // Jira Project Keys
                        Section("Jira Projects") {
                            TextField("Project keys (e.g., CAMSRE, SRE)", text: Binding(
                                get: { product.jiraProjectKeys.joined(separator: ", ") },
                                set: { product.jiraProjectKeys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                        }
                        // Jenkins Job Patterns
                        Section("Jenkins Job Patterns") {
                            TextField("Patterns (e.g., *mashery*, *cam*)", text: Binding(
                                get: { product.jenkinsJobPatterns.joined(separator: ", ") },
                                set: { product.jenkinsJobPatterns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                        }
                        // GitHub Repo Patterns
                        Section("GitHub Repo Patterns") {
                            TextField("Patterns (e.g., apim-sre-*)", text: Binding(
                                get: { product.githubRepoPatterns.joined(separator: ", ") },
                                set: { product.githubRepoPatterns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                        }
                        // Incident Product Elements
                        Section("Incident Product Elements") {
                            TextField("Elements (e.g., Cloud API Management (Mashery))", text: Binding(
                                get: { product.incidentProductElements.joined(separator: ", ") },
                                set: { product.incidentProductElements = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                        }
                    }
                }
            }
            .listStyle(.plain)

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
```

Register this tab in `SettingsView`.

### Phase 45G: Show Product Badge in the Health Score Bar

Update the health score bar on the dashboard to show the current product context:

```swift
// In healthScoreBar:
HStack(spacing: 12) {
    if let product = appState.selectedProduct, product.id != "all" {
        HStack(spacing: 4) {
            Image(systemName: product.icon)
            Text(product.shortName).font(.caption.bold())
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
    // ... existing health score content
}
```

This gives the SRE a constant visual reminder of which product they're viewing.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Add Product Context System — filter entire app by product line"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

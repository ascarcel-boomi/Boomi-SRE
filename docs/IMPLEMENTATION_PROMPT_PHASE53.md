# Boomi SRE App — Phase 53: Fix JSM Team Discovery & Consolidate Settings Tabs

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/SettingsView.swift` — settings structure with section headers and tabs (lines 81-114)
- `BoomiSRE/Sources/Views/Settings/ProductSettingsContent.swift` — Products settings, `discoverTeams()` at line 199 (broken — reads cached data instead of calling API)
- `BoomiSRE/Sources/Views/Settings/JSMSettingsContent.swift` — JSM Ops settings with team discovery
- `BoomiSRE/Sources/Views/Settings/IncidentSettingsContent.swift` — Incident settings (JQL, product elements, severity mapping)
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — `listTeams()` API method
- `BoomiSRE/Sources/Models/AppState.swift` — `discoveredJSMTeams`, `favoriteJSMTeams`

---

## Bug: Products → JSM Team Discovery Doesn't Actually Discover

**Root cause:** In `ProductSettingsContent.swift` line 199-208, the `discoverTeams()` function does NOT call the JSM API. It only reads `appState.discoveredJSMTeams`, which is empty until the user manually visits Settings → JSM Ops and clicks discover there. The function should call the API directly.

**Fix:** Replace the lazy read with an actual API call:

```swift
private func discoverTeams() async {
    isDiscoveringTeams = true
    discoveryError = nil
    guard appState.isJiraConfigured else {
        discoveryError = "Configure Jira credentials first (Settings → Jira)"
        isDiscoveringTeams = false
        return
    }
    let service = JSMOpsService()
    do {
        let teams = try await service.listTeams(
            baseURL: appState.jiraBaseURL,
            email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken
        )
        discoveredTeams = teams
        appState.discoveredJSMTeams = teams  // cache for other views
    } catch {
        discoveryError = error.localizedDescription
    }
    isDiscoveringTeams = false
}
```

---

## Reorganize: Move JSM Ops and Incidents Under Jira Integration

The user correctly identified that JSM Ops and Incidents are both Jira-based features, not separate "Features". They should be sub-sections under the Jira integration tab.

### Change 1: Move tabs in SettingsView

**Current structure:**
```
INTEGRATIONS
  Jira
  AWS SSO
  Grafana
  GitHub
  Bitbucket
  Jenkins
  Confluence
  Google

FEATURES
  Products
  Incidents      ← should be under Jira
  JSM Ops        ← should be under Jira
```

**New structure:**
```
INTEGRATIONS
  Jira           ← now includes sub-tabs for Credentials, Incidents, JSM Ops
  AWS SSO
  Grafana
  GitHub
  Bitbucket
  Jenkins
  Confluence
  Google

FEATURES
  Products       ← the only real "Feature" config
```

### Change 2: Make Jira a tabbed settings page

When the user clicks "Jira" in settings, show a page with **sub-tabs**:
- **Credentials** — the existing Jira API token setup (email, base URL, token, test connection)
- **Incidents** — the existing incident settings (JQL, product elements, severity mapping)
- **On-Call (JSM Ops)** — the existing JSM Ops settings (team discovery, favorite teams/schedules)

```swift
// In the Jira settings content view:
struct JiraSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var jiraSubTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("", selection: $jiraSubTab) {
                Text("Credentials").tag(0)
                Text("Incidents").tag(1)
                Text("On-Call").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            // Sub-tab content
            ScrollView {
                switch jiraSubTab {
                case 0:
                    jiraCredentialsContent   // existing Jira API setup
                case 1:
                    IncidentSettingsContent() // existing incident settings
                case 2:
                    JSMSettingsContent()      // existing JSM Ops settings
                default:
                    EmptyView()
                }
            }
        }
    }
}
```

### Change 3: Remove "Incidents" and "JSM Ops" as standalone tabs

In `SettingsView.swift`:
- **Remove** `settingsTab("incidents", ...)` from the FEATURES section
- **Remove** `settingsTab("jsm", ...)` from the FEATURES section
- **Remove** their `case "incidents":` and `case "jsm":` from the content switch
- The FEATURES section now only contains `settingsTab("products", ...)`

### Change 4: Update navigation from other parts of the app

Search the codebase for any code that navigates to `selectedSettingsTab = "jsm"` or `selectedSettingsTab = "incidents"` and change them to `selectedSettingsTab = "jira"`:

```swift
// Old:
appState.selectedSettingsTab = "jsm"
// New:
appState.selectedSettingsTab = "jira"
// (The Jira tab will show, and the user can click the On-Call sub-tab)
```

For a better UX, you could also add `appState.jiraSettingsSubTab` to auto-navigate to the right sub-tab, but that's optional — just getting to the Jira page is sufficient.

### Change 5: Clean up the FEATURES section

The FEATURES section header should only show if there are features to show. With just "Products" under it, it still makes sense. But if Products is the only item, consider moving it to its own section header or keeping it under FEATURES with a brief explanation:

```
FEATURES
  Products       — Configure product contexts for cross-team filtering
```

### Change 6: Also fix the JSM Ops team list display

The user reported: "Settings → JSM Ops → On-Call Teams & Schedules shows '7 item(s) selected as favorite' but none of the teams are listed."

This means `favoriteJSMTeams` has 7 IDs saved, but `discoveredJSMTeams` is empty (the team names haven't been fetched). The fix:

In `JSMSettingsContent`, on `.onAppear`, auto-discover teams if `discoveredJSMTeams` is empty but `favoriteJSMTeams` is not:

```swift
.onAppear {
    if appState.discoveredJSMTeams.isEmpty && !appState.favoriteJSMTeams.isEmpty && appState.isJiraConfigured {
        Task { await autoDiscoverTeams() }
    }
}
```

This ensures the team list is populated whenever the settings page opens, without requiring a manual button click.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Fix JSM team discovery, consolidate Incidents and JSM Ops under Jira settings tab"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

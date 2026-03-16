# Boomi SRE App — Phase 51: Settings Redesign, Products UX, About Window & Boomi Theme Colors

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/SettingsView.swift` — current settings with 16 flat tabs (profile, preferences, aws, jira, confluence, bitbucket, github, jenkins, grafana, google, jsm, incidents, products, productivity, advanced, about)
- `BoomiSRE/Sources/Views/Settings/` — individual settings content views (if split into separate files)
- `BoomiSRE/Sources/Views/AboutView.swift` — custom About popup window
- `BoomiSRE/Sources/Models/ProductContext.swift` — product model with filter patterns
- `BoomiSRE/Sources/Models/AppState.swift` — all settings state

---

## Four Changes

### 1. Settings Reorganization
### 2. Products Settings — Dropdowns Instead of Free-Text
### 3. About Popup — Add Check for Updates
### 4. Boomi Brand Colors Theme

---

## Implementation

### Phase 51A: Reorganize Settings into Grouped Sections

The current settings has 16 flat tabs in a left sidebar. This is overwhelming and disjointed. Reorganize into **grouped sections** that mirror the main sidebar categories.

**New Settings structure:**

```
GENERAL
  ├─ Profile
  ├─ Preferences
  └─ Appearance (NEW — theme colors)

INTEGRATIONS
  ├─ Alerts & On-Call
  │   ├─ Jira (shared credentials for tickets + incidents + on-call)
  │   └─ JSM Ops (on-call specific settings)
  ├─ Infrastructure
  │   └─ AWS SSO
  ├─ Observability
  │   └─ Grafana
  ├─ Source Control
  │   ├─ GitHub
  │   └─ Bitbucket
  ├─ Automation
  │   └─ Jenkins
  ├─ Knowledge
  │   └─ Confluence
  └─ Communication
      └─ Google (Gmail, Calendar, Chat)

FEATURES
  ├─ Products (product context configuration)
  ├─ Incidents (incident JQL, severity mapping)
  └─ Notifications (polling preferences)

ABOUT
  ├─ Productivity (analytics)
  ├─ Advanced (factory reset)
  └─ About (version, updates, authors)
```

**Implementation:**
- The left sidebar in Settings should show section headers (GENERAL, INTEGRATIONS, FEATURES, ABOUT) with items underneath — similar to macOS System Settings.
- Section headers are non-clickable labels in `.caption.bold()` uppercase grey text.
- The integration items are grouped under their sidebar category names so the user sees the same mental model in both places.
- Clicking "Jira" in Settings shows the Jira credential tab (same as today), but it's now under the "Alerts & On-Call" group header.

### Phase 51B: Products Settings — Replace Free-Text with Pickers

The current Products settings has plain text fields where users type JSM team IDs, Jira project keys, Jenkins job patterns, etc. This is error-prone.

**Replace with smart pickers for each field:**

1. **JSM Team IDs** → Replace text field with a **multi-select checkbox list** of discovered teams:
   - Show a "Discover Teams" button that fetches teams from the JSM Ops API
   - Display all teams as checkboxes with their names (not raw IDs)
   - Checked teams are added to the product's `jsmTeamIds` array
   - The raw ID is stored, but the user sees "CAM SRE" not "og-90b86004-..."

2. **Jira Project Keys** → Replace with a **multi-select** from discovered projects:
   - Fetch available projects: `GET /rest/api/3/project/search` with Basic auth
   - Show project key + name as checkboxes: `☑ CAMSRE — CAM SRE Team`
   - Add a `JiraService.listProjects()` method if it doesn't exist

3. **Incident Product Elements** → Already has a discovery mechanism (from Phase 14). Reuse the same picker: checkboxes with discovered product element values.

4. **GitHub Repo Patterns** → Replace with a **multi-select** from discovered repos:
   - Fetch repos from configured orgs (already implemented)
   - Show repo names as checkboxes grouped by org
   - Selected repos become the patterns (exact match instead of wildcards)
   - Keep a "Custom pattern" text field for wildcards as a fallback

5. **Jenkins Job Patterns** → Replace with a **multi-select** from discovered jobs:
   - Fetch jobs from Jenkins (already implemented via `JenkinsService.listJobs()`)
   - Show job names as checkboxes
   - Selected jobs become the patterns

6. **Grafana Dashboard Tags/Folders** → Replace with a **multi-select** from discovered dashboards:
   - Fetch dashboards (already implemented via `GrafanaService.searchDashboards()`)
   - Extract unique tags and folder names
   - Show as checkboxes

7. **Confluence Space Keys** → Replace with a **multi-select** from discovered spaces:
   - Fetch spaces (already implemented via `ConfluenceService.fetchSpaces()`)
   - Show space key + name as checkboxes

8. **KB Tags** → Keep as a text field (tags are free-form), but add a "Suggested" list based on the product name.

**Each picker should:**
- Show a "Discover" button that fetches the available options from the API
- Cache the discovered options so they don't re-fetch every time the settings open
- Show a loading spinner while fetching
- Show an error if the service isn't configured ("Configure Jira credentials first")
- Allow manual entry as a fallback (a text field at the bottom: "Add custom value...")

### Phase 51C: About Popup — Add Check for Updates

Update the custom About popup window (`AboutView.swift` / `showAboutPanel()`) to include version checking:

1. **Make the version text clickable.** When the user clicks on "Version 26.03.15-120000", it should:
   - Open Settings → About tab
   - Automatically trigger `updateVM.checkForUpdate()`

2. **OR add a small "Check for Updates" link** directly in the About popup below the version:
   ```
   Version 26.03.15-120000
   [Check for Updates]  ← clickable link
   ```
   Clicking it navigates to Settings → About (which auto-checks on appear per Phase 35).

3. **If an update is already known** (from the last auto-check), show it in the About popup:
   ```
   Version 26.03.15-120000
   ✨ Version 26.03.16-080000 is available — Check for Updates
   ```

To access the `UpdateViewModel` from the About popup, either:
- Pass it as a parameter to `showAboutPanel()`
- Or use a global/singleton reference
- Or use the `@EnvironmentObject` pattern if the About popup is a SwiftUI window

### Phase 51D: Boomi Brand Colors Theme

Add a Boomi color theme that users can toggle alongside the native macOS theme.

**Boomi brand colors (extracted from boomi.com CSS):**

```swift
// BoomiSRE/Sources/Models/BoomiTheme.swift

import SwiftUI

enum AppTheme: String, Codable, CaseIterable {
    case system = "System"      // Use macOS accent color
    case boomi  = "Boomi"       // Use Boomi brand colors

    var displayName: String { rawValue }
}

struct BoomiColors {
    // Primary
    static let deepNavy     = Color(hex: "072B55")   // Dark background, headers
    static let boomiPurple  = Color(hex: "4B4FE2")   // Primary accent (replaces system accent)
    static let boomiMagenta = Color(hex: "A03291")    // Secondary accent
    static let boomiGreen   = Color(hex: "0EC38B")    // Success, healthy, positive
    static let boomiCoral   = Color(hex: "FF7C66")    // Warning, attention

    // Supporting
    static let darkIndigo   = Color(hex: "181CAF")    // Deep accent
    static let boomiMaroon  = Color(hex: "7B0A2E")    // Legacy accent

    // Gradients (used on boomi.com)
    static let gradientGreenPurple = LinearGradient(
        colors: [boomiGreen, boomiPurple], startPoint: .leading, endPoint: .trailing)
    static let gradientPurpleMagenta = LinearGradient(
        colors: [boomiPurple, boomiMagenta], startPoint: .leading, endPoint: .trailing)
    static let gradientMagentaCoral = LinearGradient(
        colors: [boomiMagenta, boomiCoral], startPoint: .leading, endPoint: .trailing)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

**Add theme to AppState:**
```swift
@Published var appTheme: String = "system"   // "system" or "boomi"
```

**Add Appearance settings** (under General):
```swift
struct AppearanceSettingsContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.headline)

            Picker("Color Theme", selection: $appState.appTheme) {
                Text("System (macOS accent color)").tag("system")
                Text("Boomi Brand Colors").tag("boomi")
            }
            .pickerStyle(.radioGroup)
            .onChange(of: appState.appTheme) { appState.saveConfig() }

            if appState.appTheme == "boomi" {
                // Preview of Boomi colors
                HStack(spacing: 8) {
                    colorSwatch(BoomiColors.boomiPurple, "Purple")
                    colorSwatch(BoomiColors.boomiGreen, "Green")
                    colorSwatch(BoomiColors.boomiMagenta, "Magenta")
                    colorSwatch(BoomiColors.boomiCoral, "Coral")
                    colorSwatch(BoomiColors.deepNavy, "Navy")
                }

                Text("Boomi brand colors will be used for accents, status indicators, and highlights throughout the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func colorSwatch(_ color: Color, _ name: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 40, height: 40)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
```

**Apply the theme throughout the app:**

Create a helper to get the current accent color:
```swift
extension AppState {
    var themeAccent: Color {
        appTheme == "boomi" ? BoomiColors.boomiPurple : .accentColor
    }
    var themeSuccess: Color {
        appTheme == "boomi" ? BoomiColors.boomiGreen : .green
    }
    var themeWarning: Color {
        appTheme == "boomi" ? BoomiColors.boomiCoral : .orange
    }
    var themeDanger: Color {
        appTheme == "boomi" ? BoomiColors.boomiMagenta : .red
    }
}
```

Replace key `.accentColor` usages throughout the app with `appState.themeAccent`. The main places to update:
- Sidebar icons (currently `.foregroundStyle(.accentColor)`)
- Health score bar color
- Widget card accents
- Feed item priority colors
- Button tints on action buttons

Don't replace EVERY color — just the primary accent and status colors. Keep system colors for standard macOS controls (toggles, pickers, etc.) so the app still feels native.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Redesign Settings, smart product pickers, About updates check, Boomi theme colors"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

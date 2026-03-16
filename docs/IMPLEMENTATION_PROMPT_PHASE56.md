# Boomi SRE App — Phase 56: Eliminate Preferences Tab — Redistribute Into Logical Homes

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/SettingsView.swift` — settings structure, `PreferencesSettingsContent` (line ~349), settings tab list (line ~81)
- `BoomiSRE/Sources/Views/Settings/ProductSettingsContent.swift` — Products settings (where favorites should live)
- `BoomiSRE/Sources/Views/Settings/JSMSettingsContent.swift` — JSM Ops / On-Call settings (now a sub-tab of Jira)
- `BoomiSRE/Sources/Models/AppState.swift` — all the favorites arrays, AI settings, notification prefs, exec assistant prefs
- `BoomiSRE/Sources/Models/ReportItem.swift` — `ReportSection.commandCenter` (verify it's fully absorbed)

---

## Goal

The Preferences tab is a grab bag of unrelated settings. Split it up and put each group where it logically belongs, then remove the Preferences tab entirely.

**Current Preferences tab contains:**
1. Favorite AWS Profiles
2. Favorite Jira Projects
3. Favorite Confluence Spaces
4. Favorite GitHub Repos
5. Favorite Jenkins Jobs
6. Favorite Grafana Dashboards
7. AI Settings (Claude model, max tokens, auto-context, analysis depth)
8. Notification Preferences (poll toggles per service, refresh interval, system notifications)
9. Executive Assistant Preferences (enabled briefing types, auto-generate on launch)

**Where each should go:**

| Current Location | New Location | Reason |
|-----------------|--------------|--------|
| Favorite AWS Profiles | Products → per-product config | Each product has its own AWS accounts |
| Favorite Jira Projects | Products → per-product config | Each product has its own Jira projects |
| Favorite Confluence Spaces | Products → per-product config | Each product has its own spaces |
| Favorite GitHub Repos | Products → per-product config | Each product has its own repos |
| Favorite Jenkins Jobs | Products → per-product config | Each product has its own jobs |
| Favorite Grafana Dashboards | Products → per-product config | Each product has its own dashboards |
| AI Settings | Profile settings tab | AI behavior is personal to the user |
| Notification Preferences | Jira → On-Call sub-tab (or its own "Notifications" section under Jira) | Notifications are driven by Jira/JSM data |
| Executive Assistant Preferences | Keep in Knowledge & Tools area, or add as a sub-tab under Jira since briefings use Jira data | Briefings are driven by Jira tickets + calendar |

---

## Implementation

### Phase 56A: Move Favorites Into Products Settings

The Products settings already has per-product configuration with text fields for Jira project keys, GitHub repo patterns, Jenkins job patterns, etc. The Preferences favorites are the SAME data presented differently (checkboxes vs text fields).

**Merge them:**

1. In `ProductSettingsContent.swift`, for each product, replace the free-text fields (already partially replaced with pickers in Phase 51B) with the same checkbox lists that are currently in Preferences:
   - **Jira Projects**: show the fetched project list with checkboxes, saving to `product.jiraProjectKeys`
   - **GitHub Repos**: show the fetched repo list with checkboxes, saving to `product.githubRepoPatterns`
   - **Jenkins Jobs**: show the fetched job list with checkboxes, saving to `product.jenkinsJobPatterns`
   - **Grafana Dashboards**: show the fetched dashboard list with checkboxes, saving to `product.grafanaDashboardTags`
   - **Confluence Spaces**: show the fetched space list with checkboxes, saving to `product.confluenceSpaceKeys`
   - **AWS Profiles**: show available profiles with checkboxes (for the "All Products" product, this represents the global favorites)

2. **For the "All Products" context**: The global favorites (`appState.favoriteAWSProfiles`, `appState.favoriteJiraProjects`, etc.) should be editable in the "All Products" product config. When viewing All Products, the favorites apply globally. When viewing a specific product, only that product's filtered list applies.

3. **The pickers should reuse the same fetch logic** that's currently in `PreferencesSettingsContent` — the `fetchJiraProjects()`, `fetchGitHubRepos()`, `fetchJenkinsJobs()`, `fetchGrafanaDashboards()`, `fetchConfluenceSpaces()` methods. Move these into a shared service or ViewModel that both the Products settings and any other view can use.

### Phase 56B: Move AI Settings Into Profile

The AI settings (Claude model, max tokens, auto-context, analysis depth) are personal to the user — they affect how AI responds to THIS user. They belong in the Profile tab.

1. **In Profile settings** (`ProfileView.swift` or wherever the Profile settings content is), add an "AI Preferences" section:
   ```
   AI Preferences
   ─────────────
   Model: [claude-sonnet-4-6 ▾]
   Max Tokens: [4096]
   Auto-context: [✓] Automatically gather Jira/calendar/email context
   Analysis Depth: [Standard ▾]  (Brief / Standard / Thorough)
   ```

2. Move the corresponding code from `PreferencesSettingsContent` into the Profile content view.

### Phase 56C: Move Notification Preferences Into Jira Settings

Notifications are driven by service polling (Jira assignments, Jenkins failures, Grafana alerts, GitHub PR reviews). These toggles control which services get polled and how often.

1. **Add a "Notifications" sub-tab to the Jira settings** (alongside Credentials, Incidents, On-Call):
   ```
   Jira → [Credentials] [Incidents] [On-Call] [Notifications]
   ```

   Or better — since notifications span multiple services (not just Jira), create a **standalone Notifications section** under FEATURES:
   ```
   FEATURES
     Products
     Notifications  ← NEW: polling preferences, refresh interval, system notifications toggle
   ```

2. Move the notification preference controls:
   - Poll Jira assignments toggle
   - Poll Jenkins failures toggle
   - Poll Grafana alerts toggle
   - Poll GitHub PR reviews toggle
   - Poll Confluence page updates toggle
   - Poll AWS costs toggle
   - System notifications toggle
   - Refresh interval slider

### Phase 56D: Move Executive Assistant Preferences

Executive Assistant settings (which briefing types are enabled, auto-generate on launch) should go into the **Knowledge & Tools** area since that's where Executive Assistant lives in the sidebar.

Options:
1. Add as a section in the Knowledge & Tools combined view (if there's a settings area there)
2. Or keep it as a small section in Notifications settings (since briefings generate notifications)
3. Or add it to Profile (since it's personal preference about which briefings YOU want)

**Simplest approach:** Add it to Profile alongside the AI Settings — both are personal AI behavior preferences:

```
Profile
  ├── Personal Info (name, role, experience level)
  ├── AI Preferences (model, tokens, depth)
  └── Executive Assistant (enabled briefings, auto-generate)
```

### Phase 56E: Remove the Preferences Tab

1. **Remove** `settingsTab("preferences", ...)` from the Settings tab list
2. **Remove** `case "preferences": PreferencesSettingsContent()` from the content switch
3. **Remove or archive** the `PreferencesSettingsContent` struct — all its content has been moved elsewhere
4. **Update any navigation** that points to `selectedSettingsTab = "preferences"` — redirect to the appropriate new location

### Phase 56F: Verify Command Center Is Fully Absorbed

The old `ReportSection.commandCenter` contained: Notifications, Incidents, On-Call, AI Copilot, Executive Assistant.

Verify each is accessible in the new sidebar structure:
- **Notifications** → "Alerts & On-Call" tab (Notifications sub-tab) ✓
- **Incidents** → "Incidents" sidebar item ✓
- **On-Call** → "Alerts & On-Call" tab (On-Call sub-tab) ✓
- **AI Copilot** → Persistent AI bar (bottom of every screen) + "Knowledge & Tools" tab ✓
- **Executive Assistant** → "Knowledge & Tools" tab (Exec Assistant sub-tab) ✓

If any of these are NOT accessible from the new sidebar, add them.

Also verify that the `ReportSection.commandCenter` enum case can be removed or deprecated — it shouldn't be referenced in the active sidebar anymore. If other code still references it (old routing, notifications, etc.), update those references.

### Phase 56G: Update Settings Tab List

After all moves, the final Settings structure should be:

```
GENERAL
  Profile (personal info + AI prefs + Exec Assistant prefs)
  Appearance (theme colors)

INTEGRATIONS
  Jira (Credentials / Incidents / On-Call sub-tabs)
  AWS SSO
  Grafana
  GitHub
  Bitbucket
  Jenkins
  Confluence
  Google

FEATURES
  Products (product contexts with per-product integration pickers)
  Notifications (polling preferences, refresh interval)

ABOUT
  Productivity
  Advanced
  About
```

Clean, logical, nothing redundant.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift test` to verify tests still pass.
3. Commit with message: "Eliminate Preferences tab — favorites moved to Products, AI/Notifications moved to Profile"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

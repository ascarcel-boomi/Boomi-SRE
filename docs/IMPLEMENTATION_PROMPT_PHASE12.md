# Boomi SRE App — Phase 12: Quick Wins — Factory Reset, Settings, Incidents, Toolbar, Feature Requests, Credential UX

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object, config persistence (`~/.boomi_sre_config.json`), keychain-backed tokens
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — file-based secrets store (`~/.boomi_sre_secrets.json`, NOT macOS Keychain)
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation (Settings button currently at bottom of List)
- `BoomiSRE/Sources/Views/ContentView.swift` — detail pane routing
- `BoomiSRE/Sources/Views/SettingsView.swift` — settings panel with service tabs
- `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift` — incident list + detail
- `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift` — local incident CRUD (`~/.boomi_sre_incidents.json`)
- `BoomiSRE/Sources/Models/IncidentModels.swift` — Incident, IncidentSeverity, IncidentStatus, TimelineEntry
- `BoomiSRE/Sources/Views/OnboardingWizardView.swift` — first-run wizard
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point, CommandMenu

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path from `AWSAuthService.resolvedAWSPath`.
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 12A: Factory Reset

**Goal:** Add a safe "Factory Reset" that returns the app to first-launch state for testing/development without touching any external system configs.

**Implementation:**

1. Add a `factoryReset()` method to `AppState`:
   ```swift
   func factoryReset() {
       let home = FileManager.default.homeDirectoryForCurrentUser
       let filesToDelete = [
           ".boomi_sre_config.json",
           ".boomi_sre_secrets.json",
           ".boomi_sre_notifications.json",
           ".boomi_sre_incidents.json",
           ".boomi_sre_chat_history.json",
           ".boomi_sre_briefings.json",
       ]
       for file in filesToDelete {
           let url = home.appendingPathComponent(file)
           try? FileManager.default.removeItem(at: url)
       }
       // Reset in-memory state
       hasCompletedOnboarding = false
       // ... reset all @Published properties to defaults
   }
   ```

2. Reset ALL in-memory AppState properties to their init defaults:
   - Navigation: `selectedReport = nil`, `showSettings = false`, `selectedTicketKey = nil`
   - Config: `awsSSOProfile = "cam-prod-ro-json"`, `jiraEmail = ""`, `jiraBaseURL = "https://boomii.atlassian.net"`, `jiraProjectKeys = ["CAMSRE", "SRE"]`
   - Favorites: clear all arrays
   - AI settings: reset to defaults
   - Poll settings: reset to defaults
   - Auth statuses: all set to `.unknown`
   - Dashboard widgets: reset to defaults
   - `hasCompletedOnboarding = false`

3. **Do NOT delete:**
   - `~/.aws/config`, `~/.aws/credentials` — system-level AWS configs
   - `~/.kiro/` — MCP credentials
   - `~/.amazonq/` — Amazon Q credentials
   - `~/.gitconfig` — Git config
   - Anything not prefixed with `.boomi_sre_`

4. **UI in Settings:**
   - Add a new "Advanced" section at the bottom of the Settings tab bar (below Google, above nothing).
   - Show a "Factory Reset" button styled with `.tint(.red)`.
   - On click, show a confirmation alert:
     - Title: "Factory Reset"
     - Message: "This will reset all app settings, clear notifications, incidents, chat history, and saved credentials. Your AWS config (~/.aws/), MCP credentials (~/.kiro/), and Git config are NOT affected.\n\nThe app will restart with the Onboarding Wizard."
     - Buttons: "Cancel" (default) and "Reset" (destructive)
   - After confirmation: call `factoryReset()`, then trigger the onboarding sheet (the `hasCompletedOnboarding = false` should cause BoomiSREApp to show the onboarding wizard sheet automatically).

5. **Also add to the menu bar:** Help → "Factory Reset..." with the same confirmation flow.

---

### Phase 12B: Settings Pinned to Sidebar Bottom

**Goal:** Move Settings out of the scrollable sidebar list and pin it as a fixed footer at the bottom of the sidebar. This is the standard macOS pattern (Finder, Mail, etc.).

**Current state:** Settings is a `Button` inside the `List` in `SidebarView.swift`, at the bottom of the list items. It scrolls with the rest of the content.

**Implementation:**

1. Remove the Settings `Button` from inside the `List`.

2. Restructure `SidebarView`'s body from:
   ```swift
   List(selection:) {
       // Home, AI, Jira, AWS, Google, Services, Settings
   }
   ```
   to:
   ```swift
   VStack(spacing: 0) {
       List(selection:) {
           // Home, AI, Jira, AWS, Google, Services (NO Settings)
       }
       .listStyle(.sidebar)

       Divider()

       // Fixed footer
       Button {
           appState.selectedReport = nil
           appState.showSettings = true
       } label: {
           Label {
               Text("Settings").font(.body)
           } icon: {
               Image(systemName: "gear").foregroundStyle(.accentColor)
           }
       }
       .buttonStyle(.plain)
       .padding(.horizontal, 12)
       .padding(.vertical, 10)
       .frame(maxWidth: .infinity, alignment: .leading)
       .background(appState.showSettings ? Color.accentColor.opacity(0.1) : .clear)
       .cornerRadius(6)
       .padding(.horizontal, 6)
       .padding(.bottom, 6)
   }
   ```

3. In collapsed sidebar mode (if implemented from Phase 9B): show just the gear icon centered in the footer strip, with `.help("Settings")` tooltip.

4. The `.navigationTitle("Boomi SRE")` should stay on the List portion (or the parent VStack — test which looks correct).

---

### Phase 12C: Customizable Toolbar

**Goal:** Let users customize the toolbar at the top of the window with useful buttons.

**Implementation:**

1. In `BoomiSREApp.swift` or `ContentView.swift`, add a `.toolbar` modifier to the main window with these default items:

   ```swift
   .toolbar(id: "mainToolbar") {
       ToolbarItem(id: "sidebar", placement: .navigation) {
           Button { appState.sidebarCollapsed.toggle() } label: {
               Image(systemName: "sidebar.left")
           }
           .help("Toggle Sidebar")
       }

       ToolbarItem(id: "back", placement: .navigation) {
           Button { navigateBack() } label: {
               Image(systemName: "chevron.left")
           }
           .help("Back")
           .disabled(navigationHistory.isEmpty)
       }

       ToolbarItem(id: "refresh", placement: .primaryAction) {
           Button { appState.refreshTrigger = UUID() } label: {
               Image(systemName: "arrow.clockwise")
           }
           .help("Refresh (⌘R)")
       }

       ToolbarItem(id: "search", placement: .primaryAction) {
           Button { showGlobalSearch = true } label: {
               Image(systemName: "magnifyingglass")
           }
           .help("Search (⌘F)")
       }

       ToolbarItem(id: "copilot", placement: .primaryAction) {
           Button {
               appState.selectedReport = ReportCatalog.all.first { $0.id == "copilot_chat" }
           } label: {
               Image(systemName: "sparkles")
           }
           .help("AI Copilot (⌘/)")
       }

       ToolbarItem(id: "notifications", placement: .primaryAction) {
           Button {
               appState.selectedReport = ReportCatalog.all.first { $0.id == "notifications" }
           } label: {
               ZStack(alignment: .topTrailing) {
                   Image(systemName: "bell")
                   if notificationVM.unreadCount > 0 {
                       Text("\(notificationVM.unreadCount)")
                           .font(.system(size: 9).bold())
                           .foregroundStyle(.white)
                           .padding(3)
                           .background(Color.red)
                           .clipShape(Circle())
                           .offset(x: 6, y: -6)
                   }
               }
           }
           .help("Notifications")
       }
   }
   .toolbarRole(.editor)
   ```

2. Make the toolbar **customizable** using SwiftUI's `.toolbar(id:)` API (macOS 13+). This automatically gives the user "Customize Toolbar..." when right-clicking the toolbar area.

3. Add a `@State private var showGlobalSearch = false` and a minimal global search sheet:
   - A search field that searches across: Jira tickets (by key or summary), GitHub repos (by name), Confluence pages (by title), Jenkins jobs (by name)
   - Results grouped by service with icons
   - Clicking a result navigates to the appropriate view
   - Keyboard shortcut: ⌘F

4. For the "Back" button, add a simple navigation history stack:
   - `@State private var navigationHistory: [ReportItem?] = []` in ContentView
   - Before every navigation (when `selectedReport` changes), push the previous value onto the stack
   - "Back" pops the stack and sets `selectedReport` to the popped value
   - Limit stack depth to 20

---

### Phase 12D: In-App Feature Requests

**Goal:** Let users submit feature requests or bug reports as GitHub Issues directly from the app.

**Implementation:**

1. **Create `BoomiSRE/Sources/Views/Panels/FeatureRequestView.swift`:**
   - A sheet/modal with:
     - **Type picker:** Segmented control — "Feature Request" | "Bug Report" | "Improvement"
     - **Title:** Text field (required)
     - **Description:** Multi-line text editor (TextEditor, ~6 lines tall)
     - **Submit** button (disabled if title is empty)
     - **Cancel** button
   - On submit:
     - If GitHub token is configured (`appState.githubToken` is not empty):
       - Create a GitHub Issue via `POST /repos/ascarcel-boomi/Boomi-SRE/issues` using `GitHubService`
       - Set title to the user's title
       - Set body to: the user's description + a separator + auto-collected context:
         ```
         ---
         **Submitted from Boomi SRE App**
         - App Version: {bundle version or "dev"}
         - macOS: {ProcessInfo.processInfo.operatingSystemVersionString}
         - Connected Services: {list of services with .authenticated status}
         ```
       - Set labels based on type: `["feature-request"]`, `["bug"]`, or `["enhancement"]`, plus `["submitted-from-app"]`
       - On success: show confirmation with a clickable link to the created issue URL
       - On failure: show error message
     - If GitHub token is NOT configured:
       - Open `https://github.com/ascarcel-boomi/Boomi-SRE/issues/new` in the system browser with the title pre-filled as a query param
       - Show a note: "GitHub token not configured — opening in browser instead."

2. **Add a `createIssue()` method to `GitHubService`:**
   ```swift
   func createIssue(owner: String, repo: String, title: String, body: String, labels: [String], token: String) async throws -> (number: Int, htmlURL: String)
   ```
   - `POST /repos/{owner}/{repo}/issues`
   - Body JSON: `{"title": "...", "body": "...", "labels": [...]}`
   - Return the issue number and HTML URL from the response

3. **Access points (3 places):**
   - **Help menu** in `BoomiSREApp.swift` CommandMenu: "Submit Feedback..." item
   - **Settings view:** Add a "Feedback" section at the bottom of the Advanced tab (from Phase 12A) with a "Submit Feature Request" button
   - **Toolbar:** If the user adds it via toolbar customization (add an optional toolbar item with `questionmark.circle` icon)

---

### Phase 12E: Recent Incidents — Not Just Active

**Goal:** The Incidents section currently only shows active/open incidents in the main view and has an empty state saying "No Active Incidents". Add the ability to see recent resolved incidents.

**Current state:** `IncidentViewModel` stores all incidents (active + resolved) in `~/.boomi_sre_incidents.json`. The view has `activeIncidents` (filtered) and `incidents` (all). But `IncidentCommandView` only shows `activeIncidents` in the list, and when all are resolved, it shows the empty state — the user can never browse past incidents.

**Implementation:**

1. **Add a filter segmented control** to the `topBar` in `IncidentCommandView`:
   ```swift
   Picker("Filter", selection: $incidentFilter) {
       Text("Active").tag(IncidentFilter.active)
       Text("Recent").tag(IncidentFilter.recent)
       Text("All").tag(IncidentFilter.all)
   }
   .pickerStyle(.segmented)
   .frame(width: 240)
   ```

2. **Define the filter enum** (local to the view or in IncidentModels):
   ```swift
   enum IncidentFilter: String, CaseIterable {
       case active   // status != resolved
       case recent   // resolved within last 30 days
       case all      // everything
   }
   ```

3. **Computed property for filtered incidents:**
   - `active`: `vm.incidents.filter { $0.isActive }` (current behavior)
   - `recent`: `vm.incidents.filter { $0.status == .resolved && $0.resolvedAt != nil && $0.resolvedAt! > Calendar.current.date(byAdding: .day, value: -30, to: Date())! }`
   - `all`: `vm.incidents` (no filter)

4. **Update the incident list** to use the filtered list instead of `vm.activeIncidents`.

5. **Update the empty state** to be filter-aware:
   - If `active` filter and no active incidents: "No Active Incidents — All systems operational" (current behavior, with green shield)
   - If `recent` filter and empty: "No recently resolved incidents in the last 30 days"
   - If `all` filter and empty: "No incidents recorded yet. Declare an incident when an issue is detected."

6. **Add an incident timeline chart** below the filter control (only visible when filter is `recent` or `all`):
   - Swift Charts bar chart showing incident count per week for the last 12 weeks
   - Bars colored by severity (stacked: P1 red, P2 orange, P3 yellow, P4 blue)
   - X-axis: week labels (e.g., "Mar 3", "Mar 10")
   - Y-axis: count
   - Helps visualize incident trends over time

7. **Add sort options** in the incident list header:
   - Sort by: Created (newest first — default), Severity (P1 first), Duration (longest first)
   - Small `Menu` with sort options next to the filter control

---

### Phase 12F: Credential Explanation UX in Settings

**Goal:** Users are confused about why they need API tokens vs. web logins. Add clear explanations to each Settings service tab.

**Implementation:**

1. **For each service tab in SettingsView**, add an info box at the top explaining the two connection methods. Use a consistent style:
   ```swift
   private func connectionExplanation(
       serviceName: String,
       apiDescription: String,
       webDescription: String?
   ) -> some View {
       VStack(alignment: .leading, spacing: 8) {
           Label("How Boomi SRE connects to \(serviceName)", systemImage: "info.circle")
               .font(.subheadline.bold())

           HStack(alignment: .top, spacing: 8) {
               Image(systemName: "cable.connector")
                   .foregroundStyle(.blue)
                   .frame(width: 20)
               VStack(alignment: .leading, spacing: 2) {
                   Text("API Connection").font(.caption.bold())
                   Text(apiDescription).font(.caption).foregroundStyle(.secondary)
               }
           }

           if let webDesc = webDescription {
               HStack(alignment: .top, spacing: 8) {
                   Image(systemName: "globe")
                       .foregroundStyle(.green)
                       .frame(width: 20)
                   VStack(alignment: .leading, spacing: 2) {
                       Text("Web View").font(.caption.bold())
                       Text(webDesc).font(.caption).foregroundStyle(.secondary)
                   }
               }
           }
       }
       .padding(12)
       .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.05)))
       .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.15)))
   }
   ```

2. **Per-service explanations:**

   - **Jira:** API: "Your personal API token is used to fetch tickets, filters, boards, and post comments. Generate one at id.atlassian.com." Web: none (Jira is fully API-driven).

   - **Confluence:** API: "Your API token fetches spaces, pages, and search results." Web: "Some pages with complex macros or embedded content are rendered in an embedded browser view. If you see a login page, sign in once — the session persists."

   - **GitHub:** API: "Your personal access token (classic or fine-grained) is used to list repos, PRs, files, workflow runs, and create issues. Generate one at github.com/settings/tokens." Web: none.

   - **Jenkins:** API: "Your Jenkins API token is used to list jobs, fetch build history, and read console output. Find it in Jenkins → Your Name → Configure → API Token." Web: none.

   - **Grafana:** API: "Your Service Account token is used to fetch dashboards, panels, queries, and alert rules via the Grafana API." Web: "Dashboard views are rendered in an embedded browser using your Grafana web session. If you see a login screen, sign in once — the session persists."
     - Add optional fields: "Grafana Web Username" and "Grafana Web Password" stored in `~/.boomi_sre_secrets.json` via KeychainHelper (keys: `grafana-web-username`, `grafana-web-password`). These are used to auto-fill the Grafana login form in the WebView.

   - **Google:** API: "Google Workspace integration uses OAuth credentials for Gmail and Calendar." Web: "Google Chat and some Gmail features use an embedded browser. Sign in to your Google account once within the app — the session persists across launches."

   - **AWS:** API: "AWS SSO or portal credentials are used to run AWS CLI commands for Cost Explorer, EC2, RDS, and other infrastructure queries." Web: none.

   - **Bitbucket:** API: "Your Bitbucket app password is used to list repositories and pull requests." Web: none.

3. **Add a small badge** next to each sidebar item label indicating the connection type. This is optional and should be subtle — only show if the user enables "Show connection type badges" in Preferences. Use a tiny `Text("API")` or `Text("Web")` badge in `.caption2` font, colored blue or green respectively.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing functionality must continue to work.
- **Dark mode:** All new views must support both light and dark macOS appearances.
- **Commit after each phase** (12A, 12B, 12C, 12D, 12E, 12F) with a descriptive commit message.

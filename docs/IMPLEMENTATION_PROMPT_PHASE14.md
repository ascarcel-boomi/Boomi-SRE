# Boomi SRE App — Phase 14: Jira-Based Incidents (Replaces Local Incidents)

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift` — current incident UI (will be heavily rewritten)
- `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift` — current local-only incident CRUD (will be replaced with Jira fetching)
- `BoomiSRE/Sources/Models/IncidentModels.swift` — Incident, IncidentSeverity, IncidentStatus, TimelineEntry
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira REST API client (search, ticket detail)
- `BoomiSRE/Sources/Models/JiraModels.swift` — JiraIssue, JiraStatus, JiraPriority, etc.
- `BoomiSRE/Sources/Models/AppState.swift` — jiraProjectKeys, jiraBaseURL, jiraEmail, jiraAPIToken

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- **Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.**
- All Jira Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Background

**The current incident system is local-only** — incidents are created manually in the app, stored in `~/.boomi_sre_incidents.json`, and optionally linked to Jira. **This is being completely replaced.** All incidents now come from Jira.

**How Boomi tracks incidents in Jira:**
- **Project:** `Boomi Incident Management` (project key: look it up via the Jira API, but the project name is "Boomi Incident Management")
- **Custom field:** `product element[select list (multiple choices)]` — a multi-select field on each incident ticket that identifies which Boomi product is affected (e.g., "Cloud API Management (Mashery)", "Boomi Integration", "Boomi Master Data Hub", etc.)
- **Example JQL:**
  ```
  project = "Boomi Incident Management"
  AND "product element[select list (multiple choices)]" = "Cloud API Management (Mashery)"
  ORDER BY created ASC, priority DESC
  ```
- Users should be able to pick their favorite **product elements** and the Incidents section will only show incidents matching those elements.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 14A: Discover Product Elements from Jira

**Goal:** Fetch the list of all available product element values from Jira so the user can pick their favorites.

**Implementation:**

1. **Find the custom field ID for "product element":**
   - Jira custom fields have internal IDs like `customfield_12345`. The display name is `product element[select list (multiple choices)]`.
   - Add a method to `JiraService`:
     ```swift
     func getCustomFields(baseURL: String, email: String, apiToken: String) async throws -> [(id: String, name: String)]
     ```
   - Call: `GET /rest/api/3/field` — returns all fields. Filter for fields where `name` contains "product element" (case-insensitive). Return the `id` (e.g., `customfield_10XXX`) and `name`.

2. **Fetch the allowed values for the product element field:**
   - Once we have the field ID, get its allowed values.
   - Method 1: Use `GET /rest/api/3/field/{fieldId}/context` and then `GET /rest/api/3/field/{fieldId}/context/{contextId}/option` to list all options.
   - Method 2 (simpler): Search for a few recent incidents and extract unique product element values from the results. Use JQL: `project = "Boomi Incident Management" ORDER BY created DESC` with `maxResults=100` and include the custom field in the `fields` parameter. Collect all unique product element values across the results.
   - **Use Method 2** — it's simpler and guaranteed to return values that actually exist on real tickets. Method 1 requires admin-level knowledge of field contexts.
   - Add a method to `JiraService`:
     ```swift
     func discoverProductElements(
         baseURL: String, email: String, apiToken: String,
         productElementFieldId: String
     ) async throws -> [String]
     ```
   - Parse the custom field value from each issue. Since it's a multi-select, each issue may have multiple values. The JSON structure will be an array of objects with a `value` key: `[{"value": "Cloud API Management (Mashery)"}, {"value": "Boomi Integration"}]`.
   - Return a sorted, deduplicated list of all unique values.

3. **Cache the results** in AppState:
   ```swift
   @Published var incidentProductElementFieldId: String = ""  // e.g., "customfield_10456"
   @Published var availableProductElements: [String] = []     // all discovered values
   @Published var favoriteProductElements: [String] = []      // user's selected favorites
   ```
   Persist all three in `~/.boomi_sre_config.json`.

---

### Phase 14B: Product Element Picker in Settings

**Goal:** Let users select which product elements they care about.

**Implementation:**

1. **Add an "Incidents" tab to SettingsView** (after Preferences, before AWS):
   - **"Product Elements" section:**
     - Header: "Select the product elements you want to track. Only incidents matching these elements will appear in the Incident Command Center."
     - A "Discover Product Elements" button that:
       1. First calls `getCustomFields()` to find the product element field ID (cache it)
       2. Then calls `discoverProductElements()` to get all values
       3. Updates `availableProductElements` in AppState
       4. Shows a loading spinner while discovering
       5. Shows success: "Found {N} product elements" or error message
     - A searchable list of all `availableProductElements`, each with a toggle/checkbox.
     - Toggled-on elements are added to `favoriteProductElements`.
     - A "Select All" / "Deselect All" pair of buttons.
     - If `availableProductElements` is empty and hasn't been discovered yet: show "Click 'Discover' to load product elements from Jira."
     - If discovered but empty: show "No product elements found. Check that the 'Boomi Incident Management' project exists and has incidents."

   - **"Query Preview" section:**
     - Show the generated JQL query that will be used, based on selected product elements:
       ```
       project = "Boomi Incident Management"
       AND "product element[select list (multiple choices)]" IN ("Cloud API Management (Mashery)", "Boomi Integration")
       ORDER BY created DESC, priority DESC
       ```
     - If no product elements selected, show: "No product elements selected — all incidents will be shown."
     - A "Test Query" button that runs the JQL and shows: "Found {N} incidents matching your filters."

   - **"Advanced" section:**
     - A text field: "Custom JQL Override" — if the user wants to write their own JQL entirely. When non-empty, this overrides the auto-generated query.
     - A toggle: "Use custom JQL instead of product element filters" (default: off).

---

### Phase 14C: Rewrite IncidentViewModel — Jira-Only

**Goal:** Replace the local incident storage with Jira-based fetching.

**Implementation:**

1. **Remove all local incident CRUD:**
   - Remove `incidents: [Incident]` local storage array
   - Remove `loadIncidents()` and `saveIncidents()` (no more `~/.boomi_sre_incidents.json`)
   - Remove `createIncident()`, `deleteIncident()`, `updateStatus()`, `addTimelineEntry()`
   - Remove `isCreatingNew`, `newTitle`, `newSeverity`, `newAffectedServices`, `entryInput`
   - Keep `linkJiraTicket()` → **remove it** (all incidents already have Jira keys)
   - Keep `createJiraTicket()` → **repurpose it** as "Create Incident in Jira" (see Phase 14D)
   - Keep all AI analysis methods (`analyzeIncident()`, `draftStatusUpdate()`, `draftPostmortem()`, `suggestRemediation()`) — these work on the selected incident regardless of source.

2. **New published state:**
   ```swift
   @Published var incidents: [Incident] = []          // Fetched from Jira
   @Published var selectedIncident: Incident?
   @Published var isLoading = false
   @Published var error: String?
   @Published var lastFetched: Date?

   // Filters
   @Published var incidentFilter: IncidentFilter = .active
   @Published var searchText: String = ""

   // AI (keep existing)
   @Published var aiOutput: String?
   @Published var isAnalyzing = false
   @Published var aiOutputLabel = ""
   @Published var aiError: String?
   ```

3. **Add `fetchIncidents()` method:**
   ```swift
   func fetchIncidents(appState: AppState) async {
       guard appState.isJiraConfigured else {
           error = "Jira not configured. Set up Jira in Settings."
           return
       }

       isLoading = true
       error = nil

       let jql = buildIncidentJQL(appState: appState)

       do {
           let issues = try await jiraService.searchIssues(
               baseURL: appState.jiraBaseURL,
               email: appState.jiraEmail,
               apiToken: appState.jiraAPIToken,
               jql: jql,
               fields: "summary,status,priority,issuetype,created,updated,resolutiondate,assignee,reporter,labels,\(appState.incidentProductElementFieldId),comment",
               maxResults: 100
           )
           incidents = issues.map { mapJiraToIncident($0, appState: appState) }
           lastFetched = Date()
       } catch {
           self.error = error.localizedDescription
       }
       isLoading = false
   }
   ```

4. **Build the JQL:**
   ```swift
   private func buildIncidentJQL(appState: AppState) -> String {
       // If custom JQL override is set, use it
       if appState.useCustomIncidentJQL, !appState.customIncidentJQL.isEmpty {
           return appState.customIncidentJQL
       }

       var clauses = ["project = \"Boomi Incident Management\""]

       // Product element filter
       if !appState.favoriteProductElements.isEmpty {
           let elements = appState.favoriteProductElements
               .map { "\"\($0)\"" }
               .joined(separator: ", ")
           clauses.append("\"product element[select list (multiple choices)]\" IN (\(elements))")
       }

       // Time filter based on incident filter
       switch incidentFilter {
       case .active:
           clauses.append("statusCategory NOT IN (Done)")
       case .recent:
           clauses.append("created >= -30d")
       case .all:
           clauses.append("created >= -90d")
       }

       return clauses.joined(separator: " AND ") + " ORDER BY created DESC, priority DESC"
   }
   ```

5. **Map Jira issue to Incident:**
   ```swift
   private func mapJiraToIncident(_ issue: JiraIssue, appState: AppState) -> Incident {
       let severity: IncidentSeverity = {
           switch issue.priority?.name?.lowercased() ?? "" {
           case "highest", "blocker", "p1": return .p1
           case "high", "critical", "p2": return .p2
           case "medium", "p3": return .p3
           default: return .p4
           }
       }()

       let status: IncidentStatus = {
           let category = issue.status?.statusCategory?.key ?? ""
           switch category {
           case "done": return .resolved
           case "indeterminate": return .identified
           default: return .investigating
           }
       }()

       let created = parseJiraDate(issue.created) ?? Date()
       let resolved = issue.resolutionDate.flatMap(parseJiraDate)

       // Build timeline from status + comments
       var timeline: [TimelineEntry] = [
           TimelineEntry(timestamp: created, content: "Incident created: \(issue.key) — \(issue.summary ?? "")", source: "jira")
       ]

       // Extract product elements for display
       let productElements: [String] = extractProductElements(from: issue, fieldId: appState.incidentProductElementFieldId)

       return Incident(
           id: deterministicUUID(from: issue.key),
           title: issue.summary ?? issue.key,
           severity: severity,
           status: status,
           createdAt: created,
           resolvedAt: resolved,
           jiraTicketKey: issue.key,
           timeline: timeline,
           affectedServices: productElements,
           aiAnalysis: nil
       )
   }
   ```

6. **Filtered incidents computed properties:**
   ```swift
   var filteredIncidents: [Incident] {
       var result = incidents

       // Apply search
       if !searchText.isEmpty {
           result = result.filter {
               $0.title.localizedCaseInsensitiveContains(searchText) ||
               ($0.jiraTicketKey ?? "").localizedCaseInsensitiveContains(searchText)
           }
       }

       return result
   }

   var activeIncidents: [Incident] { incidents.filter(\.isActive) }
   var activeHighPriorityCount: Int { incidents.filter { $0.isActive && $0.isHighPriority }.count }
   ```

---

### Phase 14D: Rewrite IncidentCommandView — Jira-Powered UI

**Goal:** Rebuild the incident UI around Jira data instead of local CRUD.

**Implementation:**

1. **Remove the "Declare Incident" button** and local incident creation form. Replace with:
   - "Create Incident in Jira" button that opens a sheet to create a new Jira ticket in the "Boomi Incident Management" project (reuse the existing `createJiraIssue()` method, but target the incident project and let the user pick severity/product element)
   - Or simpler: "Create in Jira" button that opens `{jiraBaseURL}/secure/CreateIssue.jspa?pid={projectId}` in the system browser

2. **Top bar redesign:**
   ```
   [Incident Command]  [2 active] [P1 badge]   |  [Active|Recent|All]  [Search...]  [Refresh ↻]  [Last updated: 2m ago]
   ```
   - Title with active count and severity badges
   - Filter segmented control: Active / Recent (last 30d) / All (last 90d)
   - Search field (filters by title or ticket key)
   - Refresh button that re-fetches from Jira
   - "Last updated" timestamp showing `lastFetched` relative time
   - "Create in Jira" button (opens browser or in-app creation)

3. **Product element pills** below the top bar:
   - Show the user's selected `favoriteProductElements` as colored pill/chip badges
   - Each pill is removable (click X to temporarily hide incidents for that element)
   - A "+" button to add more elements (opens a picker from `availableProductElements`)
   - This provides quick visual context: "Showing incidents for: Cloud API Management (Mashery), Boomi Integration"

4. **Incident list (left pane of HSplitView):**
   - Each row shows:
     - Severity badge (P1 red, P2 orange, P3 yellow, P4 blue) — large, prominent
     - Ticket key (e.g., "INC-1234") in monospaced font
     - Title (bold, 2 lines max)
     - Status badge with color
     - Product elements as small pills
     - Created date (relative: "2h ago", "3d ago")
     - Assignee name (small, secondary)
   - Sort by: created (default), severity, last updated
   - Clickable — sets `selectedIncident`

5. **Incident detail (right pane):**
   - **Header:** Severity badge + Ticket key + Title
   - **Metadata bar:** Status | Priority | Assignee | Reporter | Created | Updated | Product Elements
   - **"Open in Jira" button** — opens `{jiraBaseURL}/browse/{ticketKey}`
   - **"View Full Ticket" button** — navigates to TicketDetailView (sets `appState.selectedTicketKey`)
   - **AI action buttons** (keep all existing ones):
     - "Analyze Root Cause"
     - "Draft Status Update"
     - "Draft Post-Incident Review"
     - "Suggest Remediation"
   - **AI output panel** (keep existing)
   - **Timeline section:** Shows Jira comments in chronological order. Each entry shows: author avatar/name, timestamp, content. Fetch comments lazily when an incident is selected (don't load all comments in the initial search).

6. **Loading state:**
   - On first appear: full-screen loading with "Loading incidents from Jira..."
   - On refresh: subtle loading indicator in the top bar (don't replace the list)
   - On error: banner at the top with error message and retry button, but keep stale data visible

7. **Empty states:**
   - Jira not configured: "Configure Jira in Settings to view incidents."
   - No product elements selected: "Select product elements in Settings → Incidents to see relevant incidents."
   - No incidents found: green shield icon + "No active incidents for your product elements. All clear." (for Active filter)

---

### Phase 14E: Incident Comments (Lazy Loading)

**Goal:** When the user selects an incident, fetch and display its Jira comments as the incident timeline.

**Implementation:**

1. **Add a method to fetch comments for a single issue:**
   Add to `JiraService` (or reuse if it exists):
   ```swift
   func getIssueComments(
       baseURL: String, email: String, apiToken: String,
       issueKey: String
   ) async throws -> [JiraComment]
   ```
   - Call: `GET /rest/api/3/issue/{issueKey}/comment?orderBy=created&maxResults=100`
   - Parse into `JiraComment` model:
     ```swift
     struct JiraComment: Identifiable, Sendable {
         let id: String
         let authorName: String
         let authorAvatarURL: String?
         let created: String
         let bodyText: String  // extracted plain text from ADF body
     }
     ```
   - The comment body in Jira v3 is in Atlassian Document Format (ADF). Extract plain text from it:
     - ADF is a JSON structure with nested `content` arrays containing `text` nodes
     - Walk the tree and concatenate all `text` node values
     - Handle `type: "paragraph"`, `type: "text"`, `type: "hardBreak"` (→ newline), `type: "codeBlock"`, `type: "bulletList"`, `type: "listItem"`

2. **In IncidentViewModel, add comment state:**
   ```swift
   @Published var selectedIncidentComments: [JiraComment] = []
   @Published var isLoadingComments = false

   func loadComments(for incident: Incident, appState: AppState) async {
       guard let key = incident.jiraTicketKey, appState.isJiraConfigured else { return }
       isLoadingComments = true
       do {
           selectedIncidentComments = try await jiraService.getIssueComments(
               baseURL: appState.jiraBaseURL,
               email: appState.jiraEmail,
               apiToken: appState.jiraAPIToken,
               issueKey: key
           )
       } catch {
           // Silently fail — comments are supplementary
           selectedIncidentComments = []
       }
       isLoadingComments = false
   }
   ```

3. **Trigger comment loading** when `selectedIncident` changes (in `IncidentCommandView`'s `.onChange(of: vm.selectedIncident)`).

4. **Display comments** in the detail pane's timeline section:
   - Each comment shows: author name, relative timestamp, body text
   - Style like a chat/conversation thread (author on left, content in a bubble or card)
   - If loading: show a spinner with "Loading comments..."
   - If no comments: "No comments on this incident yet."

5. **Add a "Post Comment" field** at the bottom of the timeline:
   - Text field + "Post" button
   - Posts a comment to the Jira issue via `POST /rest/api/3/issue/{key}/comment`
   - Body format: ADF (wrap the text in a basic paragraph ADF structure, same as the existing `createJiraIssue()` method uses for descriptions)
   - After posting, refresh the comments list
   - This lets SREs add timeline entries directly from the app without switching to Jira

---

### Phase 14F: Cleanup — Remove Local Incident System

**Goal:** Remove all remnants of the local incident system.

**Implementation:**

1. **Delete `~/.boomi_sre_incidents.json`** handling — remove `historyURL`, `loadIncidents()`, `saveIncidents()` from IncidentViewModel.

2. **Remove local incident creation UI** — no more "Declare Incident" form with title/severity/affected services fields. Replace with "Create in Jira" button.

3. **Update `AppState`:**
   - Remove any references to local incident count that was based on local storage
   - `activeIncidentCount` should now be set from the Jira-fetched incidents

4. **Update Notification system** (if Phase 10 was implemented):
   - Incident-related notifications should now reference Jira ticket keys, not local incident UUIDs

5. **Update `DashboardView` / `WelcomeView`:**
   - The "Active Incidents" widget (if it exists) should pull from the Jira-powered IncidentViewModel

6. **Keep the Incident model struct** (`IncidentModels.swift`) — it's still useful as the in-memory representation. Just remove the `Codable` conformance for local persistence since it's no longer saved to disk. Actually, keep `Codable` — it doesn't hurt, and the AI analysis methods serialize incidents for Claude prompts.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break other features.** AI analysis, notifications, sidebar badges, and the rest of the app must continue to work.
- **Jira field discovery may fail.** If the product element field can't be found, show a clear error: "Could not find 'product element' field. Check that it exists in your Jira instance." Let the user manually enter the field ID as a fallback.
- **JQL with custom fields:** When using custom field names with spaces and brackets in JQL, they must be quoted: `"product element[select list (multiple choices)]"`. The brackets are part of the field name in Jira Cloud.
- **Performance:** The initial search (100 results) should be fast. Comments are lazy-loaded per incident. Don't fetch comments in the search query — do it separately when the user selects an incident.
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Commit after each phase** (14A, 14B, 14C, 14D, 14E, 14F) with a descriptive commit message.

# Boomi SRE App — Phase 16: Assignee Display, PCR Generation, Knowledge Base, JSM On-Call

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Models/JiraModels.swift` — JiraIssue, JiraFields, JiraUser (assignee is missing from JiraFields)
- `BoomiSRE/Sources/Services/JiraService.swift` — search queries, field lists
- `BoomiSRE/Sources/Views/Shared/JiraIssueTableView.swift` — reusable issue table (no Assignee column)
- `BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift` — TODO list (no Assignee shown)
- `BoomiSRE/Sources/ViewModels/TodoDashboardViewModel.swift` — search fields don't include assignee
- `BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift` — full detail DOES include assignee
- `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift` — shows assignee in detail view
- `BoomiSRE/Sources/Models/AppState.swift` — central state
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar
- `BoomiSRE/Sources/Views/ContentView.swift` — routing
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point, CommandMenu
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI integration

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- **Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.**
- All Jira Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

**External resources:**
- Knowledge Base repo: `ascarcel-boomi/mashery-sre-kb` on GitHub — contains SOPs in `sops/`, runbooks in `runbooks/`, and guides at the root level (all Markdown)
- Official Boomi documentation: `https://help.boomi.com/` (public website, searchable)
- JSM Operations (On-Call/Alerts): `https://boomii.atlassian.net/jira/ops/overview` — Jira Cloud JSM Operations (formerly OpsGenie integrated)

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 16A: Show Assignee on All Jira Ticket Views

**Problem:** Assignee is only visible when drilling into a full ticket detail view. It should be visible everywhere tickets are listed.

**Current state:**
- `JiraFields` struct does NOT have an `assignee` field
- `TodoDashboardViewModel` search fields: `["summary", "status", "priority", "issuetype", "duedate", "labels", "created", "updated", sprintField]` — no assignee
- `JiraIssueTableView` columns: Key, Summary, Status, Priority, Type, Due — no Assignee
- `TicketDetailViewModel.getIssue()` DOES request assignee and displays it

**Changes:**

1. **Add `assignee` to `JiraFields`:**
   ```swift
   struct JiraFields: Codable {
       // ... existing fields ...
       let assignee: JiraUser?

       enum CodingKeys: String, CodingKey {
           // ... existing keys ...
           case assignee
       }
   }
   ```

2. **Add `assignee` to ALL Jira search field lists** — find every place where search fields are specified (TodoDashboardViewModel, SavedFiltersViewModel, BoardsViewModel, any other ViewModel that calls `searchIssues`) and add `"assignee"` to the fields array.

3. **Add Assignee column to `JiraIssueTableView`:**
   - New column between Status and Priority (or at the end)
   - Show `issue.fields?.assignee?.displayName ?? "Unassigned"`
   - "Unassigned" should be styled in `.secondary` color
   - Keep the column narrow — just the name, no avatar needed

4. **Add Assignee to `TodoDashboardView` list rows:**
   - Show assignee name below the summary line, in `.caption` font, `.secondary` color
   - Format: "Assigned to: {name}" or just the name with a person icon

5. **Add Assignee everywhere tickets appear:**
   - Saved Filters results
   - Board columns (if tickets are shown in board view)
   - Search results (if there's a global search)
   - Notification detail (for jiraAssigned notifications)
   - Dashboard widgets (if the MyTickets widget lists tickets)

---

### Phase 16B: Production Change Request (PCR) Generator

**Goal:** Let users generate a PCR document from a Jira ticket + an SOP, using AI to fill in the template.

**Context:** The knowledge base at `ascarcel-boomi/mashery-sre-kb` has a `sops/creating-a-pcr.md` file that documents the PCR process. PCRs are formal requests for production changes that require approval before execution.

**Implementation:**

1. **Add a "Generate PCR" button to TicketDetailView:**
   - In the Actions tab (or as a prominent button in the toolbar area)
   - Button: "Generate PCR" with a `doc.badge.plus` icon
   - Clicking opens a PCR generation sheet

2. **PCR Generation Sheet (`PCRGeneratorView.swift`):**
   - **Ticket info** (auto-populated, read-only): Key, Summary, Priority, Status, Assignee
   - **SOP picker:** A dropdown/picker that lists all SOPs from the knowledge base (fetched from GitHub in Phase 16C). The user selects which SOP this change follows. If no SOP applies, they can select "Custom / No SOP".
   - **Change details** (user fills in or AI generates):
     - Change Description (multi-line text)
     - Justification / Business Reason
     - Impact Assessment (what services/customers are affected)
     - Rollback Plan
     - Testing Plan
     - Scheduled Date/Time
     - Estimated Duration
     - Risk Level picker: Low / Medium / High / Critical
   - **"Generate with AI" button:** Sends the ticket detail + selected SOP content to Claude and asks it to generate all the PCR fields. The AI should:
     - Read the ticket description and comments to understand the change
     - Read the SOP steps to understand the procedure
     - Generate appropriate content for each field
     - Be conservative on risk assessment
   - **"Copy to Clipboard" button** — copies the full PCR as formatted Markdown
   - **"Create Jira Ticket" button** — creates a new Jira ticket of type "Change Request" or "Task" in a configurable project, with the PCR content as the description
   - **"Post as Comment" button** — posts the PCR as a comment on the source ticket

3. **PCR template** (what Claude generates):
   ```markdown
   # Production Change Request

   **Ticket:** {key} — {summary}
   **SOP:** {sop title}
   **Requested by:** {assignee or current user}
   **Date:** {scheduled date}

   ## Change Description
   {AI-generated description of the change}

   ## Justification
   {AI-generated business reason}

   ## Procedure
   {Steps from the SOP, customized for this specific change}

   ## Impact Assessment
   - **Affected Services:** {list}
   - **Affected Customers:** {scope}
   - **Expected Downtime:** {duration}

   ## Risk Assessment
   - **Risk Level:** {Low/Medium/High/Critical}
   - **Risk Factors:** {list}

   ## Rollback Plan
   {AI-generated rollback steps}

   ## Testing Plan
   {AI-generated testing steps}

   ## Approvals
   - [ ] SRE Lead
   - [ ] Service Owner
   - [ ] Change Manager
   ```

4. **AI prompt for PCR generation:**
   Send to Claude:
   - The full ticket detail (key, summary, description, comments)
   - The SOP content (full markdown)
   - The PCR template
   - System prompt: "You are an SRE generating a Production Change Request. Be thorough and conservative. The rollback plan must be specific and actionable. The risk assessment must consider blast radius and customer impact."

---

### Phase 16C: Knowledge Base Browser

**Goal:** Provide full searchable access to the team's knowledge base (SOPs, runbooks, guides) from GitHub, plus official Boomi documentation.

**Implementation:**

1. **Create `BoomiSRE/Sources/Services/KnowledgeBaseService.swift`:**
   ```swift
   actor KnowledgeBaseService {
       struct KBArticle: Identifiable, Sendable {
           let id: String          // file path in repo
           let title: String       // extracted from first # heading or filename
           let category: KBCategory
           let path: String        // e.g., "sops/creating-a-pcr.md"
           let content: String     // full markdown content
           let lastModified: String?
       }

       enum KBCategory: String, CaseIterable, Sendable {
           case sop = "SOPs"
           case runbook = "Runbooks"
           case guide = "Guides"
           case reference = "Reference"
       }

       /// Fetch all articles from the GitHub repo.
       func fetchArticles(token: String) async throws -> [KBArticle]

       /// Fetch a single article's content.
       func fetchArticle(path: String, token: String) async throws -> String

       /// Search articles by keyword (local search across fetched content).
       func search(query: String, articles: [KBArticle]) -> [KBArticle]
   }
   ```

2. **Fetching from GitHub:**
   - Use `GitHubService` to get the repo contents:
     - `GET /repos/ascarcel-boomi/mashery-sre-kb/git/trees/main?recursive=1` — list all files
     - Filter for `.md` files
     - Categorize by path: `sops/*` → .sop, `runbooks/*` → .runbook, root `*.md` → .guide or .reference
   - Fetch content for each file: `GET /repos/ascarcel-boomi/mashery-sre-kb/contents/{path}` — returns base64-encoded content
   - Cache the articles in memory (refresh on demand, not every time the view appears)

3. **Create `BoomiSRE/Sources/ViewModels/KnowledgeBaseViewModel.swift`:**
   - Fetches and caches all KB articles
   - Provides search functionality (simple case-insensitive substring match across title + content)
   - Tracks selected article for display

4. **Create `BoomiSRE/Sources/Views/Panels/KnowledgeBaseView.swift`:**
   - **HSplitView layout:**
     - **Left pane (article list):**
       - Search field at top
       - Sections by category: SOPs, Runbooks, Guides, Reference
       - Each article row: title + category badge
       - Section counts: "SOPs (7)", "Runbooks (2)"
     - **Right pane (article content):**
       - Article title (large, bold)
       - Category badge + file path + last modified
       - "Open on GitHub" button (opens the file in browser)
       - Rendered Markdown content (use `Text(AttributedString(markdown:))` for basic rendering, or a `WKWebView` for full HTML rendering with a Markdown-to-HTML converter)
       - "Copy" button to copy raw markdown
       - If the article is an SOP: a prominent "Generate PCR from this SOP" button that opens the PCR generator (Phase 16B) with this SOP pre-selected

5. **Official Boomi Documentation search:**
   - Below the KB articles section, add a "Boomi Documentation" section
   - A search field that searches `https://help.boomi.com/`
   - Implementation: use a WKWebView that loads `https://help.boomi.com/search?q={query}` when the user searches
   - Or simpler: a "Search Boomi Docs" button that opens the search URL in the system browser
   - Or best: embed the help.boomi.com site in a WKWebView panel (like the Google Chat implementation), allowing the user to browse documentation without leaving the app

6. **Register in sidebar and routing:**
   - Add to `ReportCatalog`:
     ```swift
     ReportItem(id: "knowledge_base", title: "Knowledge Base",
                description: "SOPs, runbooks, guides, and Boomi documentation",
                section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "book.closed")
     ```
   - Place it in the AI section (after Executive Assistant, before Incidents) — or create a new "Knowledge" section
   - Add routing in `ContentView.swift`

7. **Add to Help menu:**
   - In `BoomiSREApp.swift` CommandMenu, add:
     - "Knowledge Base" (Cmd+K) — navigates to KnowledgeBaseView
     - "Search Boomi Docs" — opens help.boomi.com in browser
     - "SOPs" — navigates to KnowledgeBaseView with SOPs filter pre-selected

8. **AppState config:**
   - `@Published var kbRepoOwner: String = "ascarcel-boomi"` (persisted)
   - `@Published var kbRepoName: String = "mashery-sre-kb"` (persisted)
   - These should be configurable in Settings in case the KB repo changes

---

### Phase 16D: SOP Creator

**Goal:** Let users draft new SOPs using AI assistance and save them to the knowledge base.

**Implementation:**

1. **Add a "New SOP" button** to the Knowledge Base view (top bar, next to search).

2. **SOP Creator Sheet (`SOPCreatorView.swift`):**
   - **Title field:** Text field for the SOP name
   - **Description:** Brief description of what this SOP covers
   - **Product/Service:** Picker or text field for the affected product
   - **"Generate with AI" button:**
     - Sends the title + description to Claude
     - System prompt: "Generate a Standard Operating Procedure for an SRE team. Use this structure: Purpose, Prerequisites, Procedure (numbered steps with specific commands/actions), Verification Steps, Rollback Procedure, References. Be specific and actionable. Include actual commands where applicable."
     - Returns full SOP markdown
   - **Editor:** Full markdown text editor (TextEditor) showing the generated or manually written SOP
   - **Preview toggle:** Switch between Edit and Preview (rendered markdown)
   - **Actions:**
     - "Copy to Clipboard" — copies the markdown
     - "Save to Knowledge Base" — creates a new file in the KB repo via GitHub API:
       - `PUT /repos/{owner}/{repo}/contents/sops/{filename}.md` with base64-encoded content
       - Commit message: "Add SOP: {title}"
       - Requires GitHub token with write access to the repo
     - "Open PR" — instead of committing directly, create a branch and PR:
       - Create branch: `POST /repos/{owner}/{repo}/git/refs` (branch from main)
       - Create file on branch: `PUT /repos/{owner}/{repo}/contents/sops/{filename}.md?ref={branch}`
       - Create PR: `POST /repos/{owner}/{repo}/pulls`
       - This is safer for teams that require PR review

3. **Note:** The user mentioned "follow up with Jason on this work" — add a subtle note in the UI: "New SOPs should be reviewed by the team before use. Consider using 'Open PR' to get team review."

---

### Phase 16E: JSM On-Call & Alerts

**Goal:** Show who is currently on-call and display JSM alerts, filtered by the user's favorite teams.

**Background:**
- Boomi uses Jira Service Management (JSM) Operations (formerly OpsGenie) at `boomii.atlassian.net`
- The JSM Ops overview is at: `https://boomii.atlassian.net/jira/ops/overview`
- JSM Cloud Operations APIs are available at: `https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/`
- To get the cloudId: `GET https://boomii.atlassian.net/_edge/tenant_info` → returns `{"cloudId": "..."}`
- Auth: Same Atlassian API token used for Jira (Basic auth with email:token)

**Implementation:**

1. **Create `BoomiSRE/Sources/Services/JSMOpsService.swift`:**
   ```swift
   actor JSMOpsService {
       private var cloudId: String?

       /// Discover the Atlassian Cloud ID for the instance.
       func getCloudId(baseURL: String) async throws -> String {
           // GET {baseURL}/_edge/tenant_info
           // Parse {"cloudId": "..."}
           // Cache it
       }

       /// List all JSM Ops teams the user has access to.
       func listTeams(baseURL: String, email: String, apiToken: String) async throws -> [OpsTeam] {
           let cloudId = try await getCloudId(baseURL: baseURL)
           // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/teams
           // Auth: Basic email:token
       }

       /// Get the current on-call schedule for a team.
       func getOnCall(baseURL: String, email: String, apiToken: String, teamId: String) async throws -> [OnCallParticipant] {
           let cloudId = try await getCloudId(baseURL: baseURL)
           // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/schedules/{scheduleId}/on-calls
           // Or: GET .../v1/teams/{teamId}/on-call
           // Returns who is currently on call (primary, secondary, etc.)
       }

       /// List alerts for a team (open/acked/closed).
       func listAlerts(baseURL: String, email: String, apiToken: String, query: String? = nil) async throws -> [OpsAlert] {
           let cloudId = try await getCloudId(baseURL: baseURL)
           // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/alerts
           // Optional query param for filtering
       }

       /// Get schedules for a team.
       func listSchedules(baseURL: String, email: String, apiToken: String, teamId: String) async throws -> [OpsSchedule] {
           let cloudId = try await getCloudId(baseURL: baseURL)
           // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/schedules?teamId={teamId}
       }
   }
   ```

2. **Models (`BoomiSRE/Sources/Models/JSMOpsModels.swift`):**
   ```swift
   struct OpsTeam: Identifiable, Codable, Sendable {
       let id: String
       let name: String
       let description: String?
   }

   struct OnCallParticipant: Identifiable, Codable, Sendable {
       var id: String { name }
       let name: String
       let type: String  // "user" or "escalation"
   }

   struct OpsAlert: Identifiable, Codable, Sendable {
       let id: String
       let message: String
       let status: String      // "open", "acked", "closed"
       let priority: String    // "P1"-"P5"
       let createdAt: String
       let updatedAt: String
       let source: String?
       let tags: [String]?
       let teamId: String?
   }

   struct OpsSchedule: Identifiable, Codable, Sendable {
       let id: String
       let name: String
       let teamId: String
       let enabled: Bool
   }
   ```

3. **Create `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift`:**
   - Fetches teams, on-call participants, alerts, schedules
   - Filters by user's favorite teams
   - Published state for all data + loading/error

4. **Create `BoomiSRE/Sources/Views/Panels/OnCallView.swift`:**
   - **Top section: "Who's On Call"**
     - For each favorite team, show a card:
       - Team name
       - Current on-call: Primary (name, avatar), Secondary (name), IC (name)
       - Schedule name
       - "View Schedule" button → opens JSM in browser or shows schedule detail
     - If no favorite teams: "Select your teams in Settings → JSM" with a link
     - If only one team: show it prominently without the team selector

   - **Middle section: "Active Alerts"**
     - Filter chips: "Open" | "Acknowledged" | "Closed (24h)"
     - Alert list per team (or merged across favorite teams):
       - Priority badge (P1 red, P2 orange, etc.)
       - Alert message (title)
       - Status badge (Open/Acked/Closed)
       - Created time (relative)
       - Source (e.g., "Grafana", "CloudWatch")
       - Tags
     - Click to expand: full alert detail, "Acknowledge" button, "Close" button, "Open in JSM" link
     - Empty state: green "No active alerts for your teams"

   - **Bottom section: "On-Call Schedules"**
     - Calendar-style view showing upcoming rotations for favorite teams
     - Or a simple list: "Next rotation: {name} starts {date}"

5. **Register in sidebar:**
   - Add to `ReportCatalog`:
     ```swift
     ReportItem(id: "oncall", title: "On-Call",
                description: "On-call schedules, alerts, and team rosters from JSM",
                section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "phone.badge.waveform")
     ```
   - Place it in the AI section (near Incidents — on-call is closely related)
   - Add routing in `ContentView.swift`

6. **Settings — JSM tab:**
   - Add a "JSM Operations" section to Settings (new tab, or under Jira tab):
     - "Discover Teams" button — fetches all teams the user has access to
     - List of discovered teams with favorite toggles (checkboxes)
     - Save favorites to `appState.favoriteJSMTeams: [String]` (team IDs, persisted)
   - The same Jira email + API token should work for JSM Ops API (it uses the same Atlassian auth)

7. **AppState additions:**
   ```swift
   @Published var favoriteJSMTeams: [String] = []      // team IDs
   @Published var availableJSMTeams: [OpsTeam] = []     // discovered teams (not persisted — rediscovered on demand)
   @Published var jsmCloudId: String = ""               // cached cloud ID (persisted)
   ```

**Important API notes:**
- The JSM Ops API base URL is `https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/` — NOT the Jira base URL. The auth is still Basic (email:token) but the host is `api.atlassian.com`.
- If the JSM Ops APIs return 403/404, it may mean the user's Jira plan doesn't include JSM Operations, or their token doesn't have the right scopes. Handle this gracefully with a clear error message.
- The on-call endpoint structure may vary. Try these in order:
  1. `GET /v1/teams/{teamId}/on-calls` (team-level on-call)
  2. `GET /v1/schedules?teamIdentifierType=id&teamIdentifier={teamId}` then `GET /v1/schedules/{id}/on-calls`
  3. Fall back to showing the schedule configuration without real-time on-call data

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing Jira, AI, and service integrations must continue to work.
- **Performance:** Adding `assignee` to search fields is a minimal API impact. KB fetching should cache aggressively. JSM API calls should be on-demand (not background polled).
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Commit after each phase** (16A, 16B, 16C, 16D, 16E) with a descriptive commit message.

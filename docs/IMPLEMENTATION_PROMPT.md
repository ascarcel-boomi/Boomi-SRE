# Boomi SRE App — AI-Powered Feature Expansion

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, NavigationSplitView layout, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `Package.swift` — dependencies and targets
- `TODO.md` — existing roadmap
- `BoomiSRE/Sources/BoomiSREApp.swift` — app entry point and CommandMenu
- `BoomiSRE/Sources/ContentView.swift` — NavigationSplitView root
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Models/JiraModels.swift` — Jira domain models
- `BoomiSRE/Sources/Services/ClaudeService.swift` — existing AI integration
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API client
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift` — ticket detail (7 tabs)
- `BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift` — ticket AI analysis

**Existing services (all actor types):** JiraService, ClaudeService, AWSAuthService, AWSCostService, GoogleService, ConfluenceService, BitbucketService, GitHubService

**Key constraints:**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Never macOS Keychain (unsigned app).
- Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path `/usr/local/bin/aws` (PATH stripped in .app bundle).
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 1: AI Copilot Chat Interface

**Goal:** Add a persistent AI chat panel that has deep context about the user's SRE state. This is the app's killer feature — not a generic Claude chat, but an SRE copilot that knows your tickets, costs, meetings, and alerts.

#### 1A. Chat Data Model

Create `BoomiSRE/Sources/Models/ChatModels.swift`:

```
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole  // .user, .assistant, .system
    let content: String
    let timestamp: Date
    var contextSources: [ContextSource]  // what data was injected
}

enum ChatRole: String, Codable { case user, assistant, system }

struct ContextSource: Identifiable, Codable {
    let id: UUID
    let type: ContextType  // .jiraTickets, .awsCosts, .calendar, .email, .jenkins, .grafana, .confluence, .github
    let label: String      // e.g., "5 open tickets", "March AWS costs"
    let summary: String    // brief description of injected data
}

enum ContextType: String, Codable {
    case jiraTickets, awsCosts, calendar, email, jenkins, grafana, confluence, github, custom
}
```

#### 1B. Chat ViewModel

Create `BoomiSRE/Sources/ViewModels/ChatViewModel.swift`:

```swift
@MainActor final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var autoContext: Bool = true  // auto-inject relevant context
    @Published var selectedContextTypes: Set<ContextType> = [.jiraTickets]

    // Context gathering — pulls live data from services
    func gatherContext() async -> String { ... }

    // Send message with context
    func send() async { ... }

    // Quick actions (pre-built prompts)
    func askAboutTicket(_ key: String) async { ... }
    func analyzeIncident(_ description: String) async { ... }
    func explainCostSpike(_ service: String, _ amount: Double) async { ... }
    func draftRunbook(for topic: String) async { ... }
    func summarizeMyDay() async { ... }
    func planSprint() async { ... }
}
```

**Context gathering logic:**
- If `.jiraTickets` is selected: fetch open tickets via JiraService, format as structured text (key, summary, status, priority, due date, last comment)
- If `.awsCosts` is selected: fetch current month costs via AWSCostService, format top 10 services
- If `.calendar` is selected: fetch today's events via GoogleService
- If `.email` is selected: fetch recent unread emails via GoogleService
- Each context type adds a `ContextSource` to the message so the user can see what data was injected

**System prompt for the copilot:**
```
You are an SRE copilot embedded in a native macOS application for Boomi's APIM SRE team. You have real-time context about the user's tickets, AWS costs, calendar, and infrastructure.

Your capabilities:
- Analyze and prioritize Jira tickets with actionable next steps
- Explain AWS cost trends and recommend optimizations
- Draft incident postmortems, runbooks, and documentation
- Help plan sprints and estimate work
- Correlate information across systems (e.g., a cost spike + a recent deployment)
- Draft Jira comments, Confluence pages, and PR descriptions

Always be specific and actionable. Reference ticket keys, dollar amounts, and service names. Format output as markdown. When recommending actions, explain the "why" not just the "what".
```

**Claude API call:** Use the existing `ClaudeService` but extend it:
- Add a `chat(messages: [(role: String, content: String)], systemPrompt: String, maxTokens: Int) async throws -> String` method that accepts multi-turn conversation history
- Use `max_tokens: 4096` for chat (vs 1024 for ticket analysis)
- Include full conversation history in the messages array for multi-turn context

#### 1C. Chat View

Create `BoomiSRE/Sources/Views/Panels/CopilotChatView.swift`:

**Layout:**
- Top: Context bar showing active context sources as chips/tags (toggleable)
- Middle: Scrolling message list (user messages right-aligned blue, assistant left-aligned gray, markdown rendered)
- Bottom: Text input field with send button and quick-action dropdown menu

**Quick actions menu** (gear icon or dropdown next to input):
- "Summarize my day" — pulls calendar + email + tickets
- "Prioritize my tickets" — pulls Jira tickets, returns prioritized plan
- "Explain cost trends" — pulls AWS costs, analyzes changes
- "Draft incident postmortem" — opens structured template with context
- "Draft runbook for..." — free-form topic input
- "Plan next sprint" — pulls backlog, suggests sprint scope
- "What should I work on next?" — pulls tickets + calendar, recommends focus

**Context chips** at the top:
- Each chip shows icon + label (e.g., "🎫 5 tickets", "💰 AWS $4,230", "📅 3 meetings")
- Clicking a chip toggles that context type on/off
- Chips show loading spinner while gathering context
- Hovering shows the summary of injected data

#### 1D. Sidebar Integration

Add "AI Copilot" as the **first item** in the sidebar, above the existing sections. Use a brain/sparkle icon. This is the flagship feature and should be prominent.

Also add a global keyboard shortcut: **Cmd+/** to focus the copilot input field from anywhere in the app.

---

### Phase 2: Executive Assistant Panels

**Goal:** Port the 7 executive assistant tasks from `~/github/boomi-exec-assistant/` into native SwiftUI panels. These should work both on-demand (click to generate) and optionally on a schedule (background refresh). The app replaces email as the delivery surface.

**Reference the exec-assistant source code at `~/github/boomi-exec-assistant/ea/` for prompt templates and logic.**

#### 2A. Executive Assistant Models

Create `BoomiSRE/Sources/Models/BriefingModels.swift`:

```swift
struct Briefing: Identifiable, Codable {
    let id: UUID
    let type: BriefingType
    let title: String
    let content: String          // markdown
    let generatedAt: Date
    var contextSummary: String   // what data was used
    var isRead: Bool
}

enum BriefingType: String, Codable, CaseIterable {
    case morningBrief
    case emailTriage
    case preMeetingBrief
    case actionTracker
    case eodDigest
    case dailyTicketBrief
    case claudeUsageReport
}
```

#### 2B. Executive Assistant ViewModel

Create `BoomiSRE/Sources/ViewModels/ExecAssistantViewModel.swift`:

```swift
@MainActor final class ExecAssistantViewModel: ObservableObject {
    @Published var briefings: [Briefing] = []     // history of generated briefings
    @Published var isGenerating: [BriefingType: Bool] = [:]
    @Published var lastGenerated: [BriefingType: Date] = [:]

    // Generate specific briefing on-demand
    func generateMorningBrief() async { ... }
    func generateEmailTriage() async { ... }
    func generatePreMeetingBrief() async { ... }
    func generateActionTracker() async { ... }
    func generateEODDigest() async { ... }
    func generateDailyTicketBrief() async { ... }
    func generateClaudeUsageReport() async { ... }

    // Generate all applicable briefings
    func generateAll() async { ... }
}
```

**Prompt templates:** Port the prompt-building logic from `~/github/boomi-exec-assistant/ea/claude.py`. Each task's prompt builder should:
1. Gather the same data inputs (emails, calendar, tickets, etc.)
2. Build the same system + user prompt structure
3. Call ClaudeService.chat() with the prompt
4. Parse the response into a Briefing object

**Key adaptations from Python → Swift:**
- Gmail History API → use existing GoogleService (extend if needed to support history-based incremental fetch)
- Calendar events → use existing GoogleService
- Jira tickets → use existing JiraService with the same JQL queries from `ea/jira.py`
- Action items → store in AppState or a local JSON file (same pattern as `ea/state.py`)
- Claude usage report → parse `~/.claude/projects/**/*.jsonl` files using Foundation FileManager + JSONSerialization

#### 2C. Executive Assistant Dashboard View

Create `BoomiSRE/Sources/Views/Panels/ExecAssistantView.swift`:

**Layout — Dashboard style:**
- Top row: "Generate All" button + last-generated timestamp
- Grid of 7 briefing cards (2 columns), each showing:
  - Briefing type icon + title
  - Last generated time (or "Not yet generated")
  - Status indicator (ready / generating / error)
  - "Generate" button
  - Preview of last briefing content (first 2-3 lines, truncated)
- Clicking a card opens the full briefing in a detail view

**Briefing Detail View** (sheet or navigation push):
- Full markdown-rendered content
- "Regenerate" button
- "Copy to Clipboard" button
- "Send to Gmail" button (uses GoogleService to send to self)
- "Post to Confluence" button (future)
- Timestamp and context summary

**Briefing types and their data sources:**

| Briefing | Icon | Data Sources |
|----------|------|-------------|
| Morning Brief | ☀️ sun | Calendar today + overnight emails |
| Email Triage | 📧 envelope | Recent unread emails → P1/P2/P3 |
| Pre-Meeting Brief | 🤝 handshake | Next meeting + related emails |
| Action Tracker | ✅ checkmark | Today's emails + completed meetings |
| EOD Digest | 🌙 moon | Today's meetings + emails + actions + tomorrow preview |
| Daily Ticket Brief | 🎫 ticket | Open Jira tickets → prioritized plan |
| Claude Usage | 📊 chart | ~/.claude/ JSONL logs → cost report |

#### 2D. Sidebar Integration

Add "Executive Assistant" as a sidebar section below "AI Copilot". Show a badge count of unread briefings.

Add keyboard shortcut: **Cmd+E** to open the Executive Assistant panel.

---

### Phase 3: Enhanced AI on Existing Panels

**Goal:** Add AI capabilities to every existing panel so the user can ask questions and take actions in context.

#### 3A. AI-Powered Cost Explorer

Extend the existing `CostExplorerView` and `CostExplorerViewModel`:

**New features:**
- **"Analyze Costs" button** — sends current cost data to Claude, gets back:
  - Cost trend analysis (up/down/stable vs. last month)
  - Top cost drivers and why they might be high
  - Specific optimization recommendations (right-sizing, reserved instances, unused resources)
  - Anomaly detection (any service with >20% month-over-month increase)
- **"Compare Periods" button** — compare current month vs. previous month, current quarter vs. previous quarter
- **Natural language cost queries** — text field where user can ask "Why did EC2 costs spike last week?" and get AI analysis with the actual cost data as context

#### 3B. AI-Powered Boards View

Extend the existing `BoardsView` and `BoardsViewModel`:

**New features:**
- **"Sprint Health Check" button** — AI analyzes the current sprint:
  - Velocity vs. commitment
  - Tickets at risk (in progress too long, no updates, blocked)
  - Scope creep detection (tickets added mid-sprint)
  - Recommended actions to hit sprint goals
- **"Generate Sprint Report" button** — AI generates a sprint summary suitable for stakeholders
- **Board-level AI summary** — one-line AI summary at top of board: "Sprint is on track, 3 tickets at risk, 2 blocked"

#### 3C. AI-Powered Ticket Detail

Extend the existing `TicketDetailView` (already has AI analysis tab):

**New features on the AI tab:**
- **"Draft Comment" button** — AI drafts a status update comment based on ticket context
- **"Draft PR Description" button** — AI generates a PR description from the ticket
- **"Find Related Tickets" button** — AI identifies related/duplicate tickets using JQL search + semantic analysis
- **"Estimate Effort" button** — AI estimates story points based on description, subtasks, and historical data
- **"Generate Subtasks" button** — AI suggests a breakdown of work into subtasks
- **Conversational follow-up** — after the initial analysis, show a text input where the user can ask follow-up questions about the ticket ("What's the risk if we delay this?" / "Who should review this?" / "Draft an escalation message")

#### 3D. AI-Powered Saved Filters

Extend the existing `SavedFiltersView`:

**New features:**
- **"Explain Results" button** — AI analyzes filter results and provides insights:
  - Pattern detection (are most tickets from one team? one component?)
  - Trend analysis (increasing/decreasing over time?)
  - Recommendations based on the pattern

---

### Phase 4: Service Browsers

**Goal:** Add browsable panels for GitHub, Jenkins, Grafana, and Confluence. Each browser should have an AI layer.

#### 4A. GitHub Browser

Create `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` and `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift`:

**Features:**
- List repositories (from org `Mashery-Boomi` + personal repos)
- Browse open PRs per repo with status (checks passing/failing, review status)
- PR detail view: diff summary, review comments, CI status
- **AI features:**
  - "Summarize PR" — AI reads the PR diff and generates a summary
  - "Review PR" — AI does a code review focusing on SRE concerns (reliability, security, performance, observability)
  - "Draft Review Comment" — AI drafts review feedback

**GitHub API calls** (extend existing GitHubService):
- `GET /orgs/{org}/repos` — list org repos
- `GET /repos/{owner}/{repo}/pulls` — list PRs
- `GET /repos/{owner}/{repo}/pulls/{number}` — PR detail
- `GET /repos/{owner}/{repo}/pulls/{number}/files` — PR diff
- `GET /repos/{owner}/{repo}/actions/runs` — CI/CD status

#### 4B. Jenkins Browser

Create `BoomiSRE/Sources/Services/JenkinsService.swift` (actor), `BoomiSRE/Sources/ViewModels/JenkinsBrowserViewModel.swift`, and `BoomiSRE/Sources/Views/Panels/JenkinsBrowserView.swift`:

**Features:**
- List Jenkins jobs/pipelines (from configured Jenkins URL)
- Show build history per job with status (success/failure/unstable/running)
- View console output for any build
- **AI features:**
  - "Explain Failure" — AI reads console output of a failed build and explains what went wrong + how to fix it
  - "Summarize Build" — AI summarizes what a build did (deployments, test results)
  - "Compare Builds" — AI compares two builds and highlights differences

**Jenkins API calls:**
- `GET /api/json?tree=jobs[name,color,url]` — list jobs
- `GET /job/{name}/api/json?tree=builds[number,result,timestamp,duration]` — build history
- `GET /job/{name}/{number}/consoleText` — console output
- `GET /job/{name}/{number}/api/json` — build detail

**Important:** Jenkins at `jenkins-master.mashspud.com` uses Basic auth. The USW2 instance at `jenkins-master.usw2.mashspud.com` requires `-sk` (skip SSL verify) — set `URLSessionConfiguration` to bypass SSL for that specific host.

#### 4C. Grafana Browser

Create `BoomiSRE/Sources/Services/GrafanaService.swift` (actor), `BoomiSRE/Sources/ViewModels/GrafanaBrowserViewModel.swift`, and `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift`:

**Features:**
- List dashboards (search API)
- Show dashboard panels with their queries
- Run Prometheus/Loki queries and display results
- **AI features:**
  - "Explain Dashboard" — AI summarizes what a dashboard is monitoring and current state
  - "Analyze Alerts" — AI reviews active alerts and correlates them
  - "Explain Metric" — user pastes a PromQL query, AI explains what it measures and current value

**Grafana API calls:**
- `GET /api/search?type=dash-db` — search dashboards
- `GET /api/dashboards/uid/{uid}` — get dashboard JSON
- `POST /api/ds/query` — run datasource queries
- `GET /api/v1/provisioning/alert-rules` — list alert rules

#### 4D. Confluence Browser

Create `BoomiSRE/Sources/ViewModels/ConfluenceBrowserViewModel.swift` and `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift`:

**Features:**
- List spaces (use existing ConfluenceService)
- Browse pages within a space (hierarchy)
- View page content (rendered HTML or converted to markdown)
- Search across Confluence
- **AI features:**
  - "Summarize Page" — AI reads a Confluence page and provides a TL;DR
  - "Draft Page" — AI generates a new Confluence page (runbook, postmortem, design doc) from a prompt
  - "Update Page" — AI suggests updates to an existing page based on recent changes

**Confluence API calls** (extend existing ConfluenceService):
- `GET /wiki/api/v2/spaces` — list spaces
- `GET /wiki/api/v2/spaces/{id}/pages` — pages in space
- `GET /wiki/api/v2/pages/{id}?body-format=storage` — page content
- `GET /wiki/rest/api/search?cql=...` — search

#### 4E. Sidebar Integration

Add a "Services" section in the sidebar with:
- GitHub (icon: branch)
- Jenkins (icon: hammer)
- Grafana (icon: chart)
- Confluence (icon: document)

Each shows a badge with relevant counts (open PRs, failed builds, active alerts, etc.).

---

### Phase 5: Incident Command Center

**Goal:** A dedicated panel for incident management that ties together alerts, logs, metrics, tickets, and AI analysis.

#### 5A. Incident Models

Create `BoomiSRE/Sources/Models/IncidentModels.swift`:

```swift
struct Incident: Identifiable, Codable {
    let id: UUID
    var title: String
    var severity: IncidentSeverity  // P1, P2, P3, P4
    var status: IncidentStatus      // investigating, identified, monitoring, resolved
    var createdAt: Date
    var resolvedAt: Date?
    var jiraTicketKey: String?
    var timeline: [TimelineEntry]
    var affectedServices: [String]
    var aiAnalysis: String?
}

struct TimelineEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let content: String
    let source: String  // "user", "ai", "grafana", "jenkins", etc.
}
```

#### 5B. Incident View

Create `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift`:

**Layout:**
- Top: Active incidents list (or "No active incidents" green banner)
- Create new incident button
- Incident detail view:
  - Header: title, severity, status, duration
  - Timeline: chronological entries from all sources
  - AI panel (right side):
    - "Analyze Incident" — AI correlates available data and suggests root cause
    - "Draft Status Update" — AI writes a stakeholder status update
    - "Draft Postmortem" — AI generates a postmortem document
    - "Suggest Remediation" — AI recommends fix based on similar past incidents
  - Actions:
    - Update status
    - Add timeline entry
    - Create/link Jira ticket
    - Resolve incident

#### 5C. Sidebar Integration

Add "Incidents" in the sidebar with a red badge for active P1/P2 incidents.

Keyboard shortcut: **Cmd+I** to open Incidents.

---

### Phase 6: Smart Notifications & Background Refresh

**Goal:** The app should proactively surface important information without the user having to check each panel.

#### 6A. Notification Center

Create `BoomiSRE/Sources/Models/NotificationModels.swift` and `BoomiSRE/Sources/Views/Panels/NotificationCenterView.swift`:

**Notification types:**
- Jira ticket assigned to you
- Jira ticket you're watching changed status
- Jenkins build failed for your team's jobs
- AWS cost anomaly detected (>20% increase)
- Grafana alert firing
- PR review requested
- New briefing generated

**Implementation:**
- Background timer (every 5 minutes) checks each service for changes
- Compares against last-known state (stored in AppState)
- New notifications shown as badge on sidebar item
- macOS native notifications (UNUserNotificationCenter) for high-priority items
- Notification center panel shows history

#### 6B. Background Refresh

Add a background refresh system to AppState:

```swift
// In AppState
@Published var refreshInterval: TimeInterval = 300  // 5 minutes
private var refreshTimer: Timer?

func startBackgroundRefresh() { ... }
func stopBackgroundRefresh() { ... }
```

Each panel's ViewModel gets a `refreshIfNeeded()` method that checks staleness and fetches new data.

---

### Phase 7: Preferences & Polish

**Goal:** Let users customize which features are active and configure favorites.

#### 7A. Enhanced Preferences

Extend `SettingsView` with a new "Preferences" tab:

**Sections:**
- **Favorites:**
  - Favorite AWS Accounts (from ~/.aws/config profiles)
  - Favorite Jira Projects (fetched from API)
  - Favorite Confluence Spaces
  - Favorite GitHub Repos
  - Favorite Jenkins Jobs
  - Favorite Grafana Dashboards
- **AI Settings:**
  - Claude model selection (sonnet vs opus for analysis)
  - Max tokens for chat (default 4096)
  - Auto-context toggle (auto-inject relevant data in copilot)
  - Analysis depth (brief / standard / thorough)
- **Notifications:**
  - Enable/disable per notification type
  - macOS notification toggle
  - Background refresh interval
- **Executive Assistant:**
  - Enable/disable per briefing type
  - Schedule times (morning brief, EOD digest)
  - Auto-generate on app launch toggle

#### 7B. Onboarding Wizard

Create a first-launch onboarding flow that:
1. Welcomes the user
2. Runs credential auto-discovery
3. Tests each service connection
4. Lets user pick favorites
5. Configures notification preferences
6. Generates first morning brief

---

## Implementation Notes

### Claude API Usage Pattern

For all AI features, follow this pattern:

```swift
// In ClaudeService, add a general chat method:
func chat(
    messages: [(role: String, content: String)],
    systemPrompt: String,
    maxTokens: Int = 4096
) async throws -> String {
    // Build Anthropic Messages API request
    // POST https://api.anthropic.com/v1/messages
    // model: "claude-sonnet-4-6"
    // Include full conversation history for multi-turn
}
```

### Error Handling

Every AI feature should gracefully degrade:
- If Claude API key is not configured → show "Configure API key in Settings" message
- If a service is disconnected → show which context is unavailable but still allow chat
- If API call fails → show error with retry button, never crash

### Performance

- AI calls can take 5-30 seconds. Always show a loading indicator with "Analyzing..." text.
- Cache AI responses. Don't re-analyze the same ticket unless data changed.
- Context gathering should be parallel (fetch tickets, costs, calendar simultaneously with TaskGroup).
- Limit context size: truncate to last 10 tickets, last 20 emails, last 5 meetings to stay within Claude's context window.

### State Persistence

- Chat history: persist to `~/.boomi_sre_chat_history.json` (last 50 messages per conversation)
- Briefing history: persist to `~/.boomi_sre_briefings.json` (last 7 days)
- Incident history: persist to `~/.boomi_sre_incidents.json`
- Notification history: persist to `~/.boomi_sre_notifications.json` (last 7 days)

### Sidebar Organization

Final sidebar structure:
```
🤖 AI Copilot              ← Phase 1
📋 Executive Assistant      ← Phase 2
  ├── Morning Brief
  ├── Email Triage
  ├── Pre-Meeting Brief
  ├── Action Tracker
  ├── EOD Digest
  ├── Daily Ticket Brief
  └── Claude Usage
🚨 Incidents               ← Phase 5
─── JIRA ───
📝 My TODO
🔍 Saved Filters
📊 Boards
─── AWS ───
💰 Cost Explorer
─── SERVICES ───
🐙 GitHub                  ← Phase 4A
🔧 Jenkins                 ← Phase 4B
📈 Grafana                 ← Phase 4C
📄 Confluence              ← Phase 4D
─── GOOGLE ───
📧 Gmail
📅 Calendar
💬 Chat
🔔 Notifications           ← Phase 6
⚙️ Settings
```

### Keyboard Shortcuts (CommandMenu)

Add these to BoomiSREApp.swift CommandMenu:
- Cmd+/ → Focus AI Copilot input
- Cmd+E → Executive Assistant
- Cmd+I → Incidents
- Cmd+1 → My TODO
- Cmd+2 → Saved Filters
- Cmd+3 → Boards
- Cmd+4 → Cost Explorer
- Cmd+G → GitHub Browser
- Cmd+J → Jenkins Browser
- Cmd+K → Grafana Browser
- Cmd+N → Notification Center
- Cmd+, → Settings

---

## Execution Instructions

1. **Read all referenced files first** before writing any code.
2. **Work one phase at a time.** Complete Phase 1 fully (compiles, runs) before starting Phase 2.
3. **Run `swift build`** after each phase to verify compilation.
4. **Follow existing patterns** — look at how current ViewModels, Services, and Views are structured and match that style exactly.
5. **Don't refactor existing code** unless necessary for integration. Add to it.
6. **Keep AI prompts specific and actionable** — the system prompts should produce output that an SRE can act on immediately, not generic summaries.
7. **Test incrementally** — after adding each new view, verify it appears in the sidebar and basic navigation works before adding complex logic.

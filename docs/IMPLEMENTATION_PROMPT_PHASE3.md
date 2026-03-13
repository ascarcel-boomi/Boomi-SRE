# Boomi SRE App — Phase 3: Enhanced AI on Existing Panels

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI integration (multi-turn chat method)
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API client
- `BoomiSRE/Sources/ViewModels/CostExplorerViewModel.swift` — AWS cost data
- `BoomiSRE/Sources/ViewModels/BoardsViewModel.swift` — Jira boards data
- `BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift` — ticket AI analysis
- `BoomiSRE/Sources/ViewModels/SavedFiltersViewModel.swift` — saved filters
- `BoomiSRE/Sources/Views/Panels/CostExplorerView.swift`
- `BoomiSRE/Sources/Views/Panels/BoardsView.swift`
- `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift`
- `BoomiSRE/Sources/Views/Panels/SavedFiltersView.swift`

**Key constraints:**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Never macOS Keychain (unsigned app).
- Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path `/usr/local/bin/aws` (PATH stripped in .app bundle).
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira/Confluence Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Implementation Plan

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

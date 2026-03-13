# Boomi SRE App — Phase 2: Executive Assistant Panels

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI integration (chat method added in Phase 1)
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API client
- `BoomiSRE/Sources/Services/GoogleService.swift` — Gmail/Calendar APIs
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `~/github/boomi-exec-assistant/ea/` — Python source for prompt templates and logic to port

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

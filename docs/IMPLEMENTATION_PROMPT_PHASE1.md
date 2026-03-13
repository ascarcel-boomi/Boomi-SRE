# Boomi SRE App — Phase 1: AI Copilot Chat Interface

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

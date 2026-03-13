# Boomi SRE App — Phase 5: Incident Command Center

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI integration
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API client
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `BoomiSRE/Sources/Models/ReportItem.swift` — ReportItem, ReportCatalog, ReportSection

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

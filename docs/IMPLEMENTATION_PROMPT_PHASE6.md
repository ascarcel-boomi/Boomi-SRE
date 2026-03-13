# Boomi SRE App — Phase 6: Smart Notifications & Background Refresh

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object (has refreshInterval, background timer)
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API client
- `BoomiSRE/Sources/Services/GitHubService.swift` — GitHub API client
- `BoomiSRE/Sources/Services/JenkinsService.swift` — Jenkins API client
- `BoomiSRE/Sources/Services/GrafanaService.swift` — Grafana API client
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point

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

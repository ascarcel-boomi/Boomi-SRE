# Boomi SRE App — Phase 10: Notification Center Overhaul

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Views/Panels/NotificationCenterView.swift` — notification list UI (primary file to modify)
- `BoomiSRE/Sources/ViewModels/NotificationViewModel.swift` — polling engine, notification generation, persistence
- `BoomiSRE/Sources/Models/NotificationModels.swift` — SRENotification model, NotificationType enum
- `BoomiSRE/Sources/Models/AppState.swift` — polling preferences, credentials, navigation state
- `BoomiSRE/Sources/Views/ContentView.swift` — detail pane routing
- `BoomiSRE/Sources/Services/JenkinsService.swift` — Jenkins API client (for understanding what data is available)
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API client
- `BoomiSRE/Sources/Services/GrafanaService.swift` — Grafana API client
- `BoomiSRE/Sources/Services/GitHubService.swift` — GitHub API client
- `BoomiSRE/Sources/Services/ConfluenceService.swift` — Confluence API client
- `BoomiSRE/Sources/Views/Panels/JenkinsBrowserView.swift` — Jenkins browser (to understand existing detail views)
- `BoomiSRE/Sources/ViewModels/JenkinsBrowserViewModel.swift` — Jenkins view model

**Key constraints (same as all prior phases):**
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

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 10A: Make Entire Notification Row Clickable

**Problem:** Users must click a tiny "Go to →" link to interact with a notification. The entire notification row should be clickable.

**Current state in `NotificationCenterView.swift`:**
- Each notification row displays: unread dot, icon, title, body (3-line max), timestamp, type badge, and a small "Go to →" `Button` that only appears if `deepLink` is set.
- Clicking the row does nothing except mark as read.
- The "Go to →" button calls `navigateTo(deepLink)` which sets `appState.selectedReport` to navigate to a different section (e.g., jenkins_browser).

**Changes:**

1. Make the entire notification row a tappable area. Clicking anywhere on the row should:
   - Mark the notification as read (already happens)
   - Expand the notification inline to show its detail (see Phase 10B)
2. Remove the separate "Go to →" button. Its navigation function is being replaced by inline detail display.
3. Use `.contentShape(Rectangle())` on the row to make the full area tappable.
4. Add a visual selection state — when a notification is tapped/selected, highlight its row with a subtle accent-color background tint.

---

### Phase 10B: Inline Notification Detail — No Context Switching

**Problem:** Clicking "Go to →" on a Jenkins failure navigates to the Jenkins Browser section, but does NOT load the specific failed job/build. The user lands at the top of the Jenkins job list and has to manually find the failure. This is useless. The same problem exists for all notification types — they navigate to the parent section but not to the specific item.

**New approach:** Instead of navigating away from Notifications, show the notification detail **inline** within the Notification Center itself. This eliminates context switching entirely.

**Implementation — Expandable Notification Detail:**

1. Add `@State private var expandedNotification: UUID?` to `NotificationCenterView`.

2. When a notification row is tapped, toggle `expandedNotification` to that notification's ID (or nil if already expanded — tap again to collapse).

3. Below the expanded notification row, show a detail pane that varies by notification type:

   **For `jenkinsBuildFailed`:**
   - Fetch the build's console output using `JenkinsService.getBuildConsoleOutput()` (the job name and build number are stored in the notification's `metadata` dictionary).
   - Store the job name in `metadata["jobName"]` and build number in `metadata["buildNumber"]` when the notification is created (update `pollJenkins()` in NotificationViewModel to include these).
   - Display:
     - Job name, build number, duration, timestamp
     - Build result badge (FAILURE in red)
     - Console output in a scrollable monospaced text view (last 100 lines, with a "Show Full Log" button to expand)
     - "Open in Jenkins" link button that opens the build URL in the system browser
     - "Analyze with AI" button that sends the console output to Claude for failure analysis (reuse the pattern from JenkinsBrowserViewModel's `analyzeFailure()` method)

   **For `jiraAssigned`:**
   - Fetch the ticket detail using `JiraService` (the ticket key is in `metadata["ticketKey"]`).
   - Store `metadata["ticketKey"]` when the notification is created (update `pollJira()` to include this).
   - Display:
     - Ticket key, summary, status, priority, assignee
     - Description (first 500 chars)
     - "Open in Jira" link button
     - "View Full Ticket" button that navigates to TicketDetailView (sets `appState.selectedTicketKey`)
     - "Analyze with AI" button for quick AI assessment

   **For `jiraStatusChange`:**
   - Same as jiraAssigned but with a status transition indicator: "Status: In Progress → Done" (store `metadata["oldStatus"]` and `metadata["newStatus"]` when created).
   - Display the same ticket detail as above.

   **For `grafanaAlertFiring`:**
   - Fetch the alert rule detail using `GrafanaService` (store `metadata["alertUID"]` when created).
   - Display:
     - Alert name, state (FIRING in red), summary/description
     - Labels/tags
     - "Open in Grafana" link button
     - "View Dashboard" button that navigates to Grafana Browser with the relevant dashboard selected (if the alert is associated with a dashboard)
     - "Analyze with AI" button to get AI assessment of the alert

   **For `githubPRReview`:**
   - Show PR detail inline (store `metadata["owner"]`, `metadata["repo"]`, `metadata["prNumber"]` when created).
   - Display:
     - PR title, number, author, branch, description (truncated)
     - File change summary (+additions/-deletions)
     - CI status badges
     - "Open on GitHub" link button
     - "View in GitHub Browser" button to navigate there
     - "Summarize PR" AI button

   **For `briefingGenerated`:**
   - Show the briefing content inline (store `metadata["briefingType"]` when created).
   - "View Full Briefing" button to navigate to Executive Assistant.

4. The detail pane should:
   - Appear below the notification row with a slide-down animation (`.transition(.move(edge: .top).combined(with: .opacity))`).
   - Have a loading state while fetching data from the service API.
   - Handle errors gracefully (service not configured, API error) with an inline error message.
   - Include a "Close" button or allow tapping the notification row again to collapse.
   - Be contained within a card-style view (rounded rect, subtle background, max height ~400pt with scroll).

5. **Update `NotificationViewModel.pollJenkins()`** to store richer metadata when creating notifications:
   ```swift
   metadata: [
       "jobName": job.name,
       "buildNumber": String(build.number),
       "buildURL": build.url,   // full Jenkins URL
       "duration": build.duration
   ]
   ```
   Apply the same pattern to all other poll methods — every notification should store enough metadata to fetch its detail later without re-querying the list endpoint.

---

### Phase 10C: Add New Notification Types

**Problem:** Currently only 6 notification types exist, and in practice users mostly see Jenkins build failures. The Notification Center should surface more actionable SRE events to become a true single-pane-of-glass alert feed.

**New notification types to add:**

#### 1. `jenkinsBuildsuccess` — Jenkins Build Recovered
- **Trigger:** A job that was previously in `lastKnownFailedBuilds` now has a successful build.
- **Why:** SREs need to know when a broken pipeline is fixed, not just when it breaks.
- **Icon:** `checkmark.circle.fill`, color: `.green`
- **High priority:** NO
- **Title:** "Jenkins: {jobName} recovered"
- **Body:** "Build #{number} succeeded after previous failure"
- **Metadata:** `jobName`, `buildNumber`, `buildURL`
- **Detail view:** Same as jenkinsBuildFailed — show console output and result

#### 2. `awsCostAnomaly` — AWS Cost Spike
- **Note:** This type already exists in `NotificationModels.swift` but is never generated.
- **Trigger:** Poll AWS Cost Explorer daily (not every 5 minutes — use a separate 24-hour timer or check once per app launch). Compare today's cost-to-date against the same day last month. If > 20% higher, fire a notification.
- **Icon:** `exclamationmark.triangle.fill`, color: `.orange`
- **High priority:** YES
- **Title:** "AWS: Cost anomaly detected"
- **Body:** "Current month spend is ${amount} — {percent}% above last month's pace"
- **Metadata:** `currentMonthCost`, `lastMonthCost`, `percentIncrease`, `profile`
- **Detail view:** Show current vs. last month cost comparison, top 3 services by cost delta, "Open Cost Explorer" button.
- **Polling:** Add a `lastCostCheckDate: Date?` to NotificationViewModel. Only poll AWS costs if `lastCostCheckDate` is nil or > 24 hours ago. Use the existing `AWSCostService` to fetch monthly costs.

#### 3. `confluencePageUpdated` — Confluence Page Updated in Favorite Spaces
- **Trigger:** A page in one of the user's `favoriteConfluenceSpaces` was updated since the last poll.
- **Icon:** `doc.text.fill`, color: `.blue`
- **High priority:** NO
- **Title:** "Confluence: {pageTitle} updated"
- **Body:** "Updated by {authorName} in {spaceName}"
- **Metadata:** `pageId`, `pageTitle`, `spaceKey`, `authorName`, `pageURL`
- **Detail view:** Show page title, author, last modified date, first 500 chars of content, "Open in Confluence" button.
- **Polling:** In `pollConfluence()` (new method), call `ConfluenceService.listPages()` for each favorite space (limit 10 pages per space, sorted by lastUpdated). Track `lastKnownPageVersions: [String: Int]` (pageId → version number). Fire notification when version increases.
- **Add to Settings:** Add a "Confluence page updates (favorite spaces)" toggle tied to a new `pollConfluenceEnabled` preference.

#### 4. `githubPRMerged` — PR Merged in Watched Repos
- **Trigger:** A PR that was previously open (tracked in `lastKnownReviewPRs` or a new `lastKnownOpenPRs` set) is now closed+merged.
- **Icon:** `arrow.triangle.merge`, color: `.purple`
- **High priority:** NO
- **Title:** "GitHub: PR #{number} merged in {repo}"
- **Body:** "{title} by @{author}"
- **Metadata:** `owner`, `repo`, `prNumber`, `prTitle`, `authorLogin`, `htmlURL`
- **Detail view:** PR title, author, merge commit, "Open on GitHub" button.
- **Polling:** Extend `pollGitHub()` to also check for recently merged PRs. Track open PR numbers per repo. When a previously-open PR disappears from the open list, check if it was merged (state=closed, merged=true).

#### 5. `githubWorkflowFailed` — GitHub Actions Workflow Failed
- **Trigger:** A workflow run in a watched repo completed with `conclusion: "failure"`.
- **Icon:** `xmark.circle.fill`, color: `.red`
- **High priority:** YES
- **Title:** "GitHub Actions: {workflowName} failed in {repo}"
- **Body:** "Run #{runNumber} failed on branch {branch}"
- **Metadata:** `owner`, `repo`, `runId`, `workflowName`, `branch`, `htmlURL`
- **Detail view:** Workflow name, branch, run number, conclusion, "Open on GitHub" link, "View Logs" button.
- **Polling:** In `pollGitHub()`, for each watched repo, call `GitHubService.getWorkflowRuns()`. Track `lastKnownWorkflowRuns: [String: Int]` (repo → latest run ID). Fire notification for new runs with `conclusion == "failure"`.

#### 6. `grafanaAlertResolved` — Grafana Alert Resolved
- **Trigger:** An alert that was previously in `lastKnownAlertingUIDs` is no longer alerting (state changed from "alerting" to "normal"/"ok").
- **Icon:** `checkmark.circle.fill`, color: `.green`
- **High priority:** NO
- **Title:** "Grafana: {alertTitle} resolved"
- **Body:** "Alert is no longer firing"
- **Metadata:** `alertUID`, `alertTitle`
- **Detail view:** Same as grafanaAlertFiring but with green "RESOLVED" badge.

**Summary of changes to `NotificationModels.swift`:**
Add these cases to the `NotificationType` enum:
- `jenkinsBuildRecovered`
- `confluencePageUpdated`
- `githubPRMerged`
- `githubWorkflowFailed`
- `grafanaAlertResolved`

(`awsCostAnomaly` already exists — just needs to be wired up.)

Each new case needs: `icon`, `color`, `isHighPriority`, and `displayName` properties.

**Summary of changes to `NotificationViewModel.swift`:**
- Add `pollConfluence()` method
- Extend `pollJenkins()` to detect recoveries
- Extend `pollGitHub()` to detect merged PRs and failed workflows
- Extend `pollGrafana()` to detect resolved alerts
- Add `pollAWSCosts()` with 24-hour cooldown
- Add tracking state: `lastKnownPageVersions`, `lastKnownOpenPRs`, `lastKnownWorkflowRuns`, `lastCostCheckDate`
- Add `confluenceService` and `awsCostService` actor instances
- Update `pollAllServices()` to include Confluence and AWS cost checks

**Summary of changes to `AppState`:**
- Add `@Published var pollConfluenceEnabled: Bool = true` (persisted)
- Add `@Published var pollAWSCostsEnabled: Bool = true` (persisted)

**Summary of changes to `SettingsView.swift`:**
- Add "Confluence page updates (favorite spaces)" toggle
- Add "AWS cost anomaly detection (daily)" toggle

---

### Phase 10D: Notification Grouping & Smart Filters

**Problem:** As more notification types are added, the flat chronological list becomes hard to scan. Group related notifications and add smarter filtering.

**Implementation:**

1. **Group by service:** Add a grouping mode that groups notifications by source service (Jira, Jenkins, Grafana, GitHub, Confluence, AWS). Show each group as a collapsible section with a count badge. Default to chronological (current behavior) with a toggle to switch to grouped.

2. **Add filter chips:** Replace the current segmented control (All / Unread / High Priority) with a horizontal scrollable row of filter chips:
   - "All" (default)
   - "Unread" (with count badge)
   - "High Priority" (with count badge)
   - One chip per service that has notifications: "Jira (3)", "Jenkins (5)", "Grafana (1)", etc.
   - Chips are toggleable — multiple can be active (AND logic: e.g., "Unread" + "Jenkins" = unread Jenkins notifications only).
   - Chip styling: rounded capsule, accent-colored when active, grey when inactive.

3. **Time grouping within the list:** Add section headers for time periods: "Today", "Yesterday", "This Week", "Older". This helps the user scan recent vs. stale notifications.

4. **Notification count summary** at the top of the view: "12 notifications — 5 unread, 3 high priority" as a compact summary line below the header.

---

### Phase 10E: Notification Detail View Model

**Problem:** The inline detail views (from Phase 10B) need to fetch data from service APIs. This logic shouldn't live in the view.

**Implementation:**

1. Create `BoomiSRE/Sources/ViewModels/NotificationDetailViewModel.swift`:
   - `@MainActor final class NotificationDetailViewModel: ObservableObject`
   - Published properties:
     - `isLoading: Bool`
     - `error: String?`
     - `jenkinsConsoleOutput: String?`
     - `jiraTicketDetail: JiraIssue?` (reuse existing model)
     - `grafanaAlertDetail: GrafanaAlertRule?` (reuse existing model)
     - `githubPRDetail: GitHubPR?`
     - `githubPRFiles: [GitHubPRFile]?`
     - `confluencePageContent: String?`
     - `awsCostData: (current: Double, previous: Double, topServices: [(String, Double)])?`
     - `aiAnalysis: String?`
     - `isAnalyzing: Bool`
   - Methods:
     - `loadDetail(for notification: SRENotification, appState: AppState)` — dispatches to the right service based on notification type
     - `analyzeWithAI(notification: SRENotification)` — sends context to Claude for analysis
   - Uses existing service actors: `JenkinsService`, `JiraService`, `GrafanaService`, `GitHubService`, `ConfluenceService`, `AWSCostService`, `ClaudeService`

2. In `NotificationCenterView`, create one `@StateObject` instance of `NotificationDetailViewModel`. When `expandedNotification` changes, call `vm.loadDetail(for:appState:)`.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing notification polling, system notifications, and badge counts must continue to work.
- **Metadata backward compatibility:** Older notifications loaded from `~/.boomi_sre_notifications.json` won't have the new metadata fields. Handle missing metadata gracefully — show a "Details unavailable" message or fall back to the old "Go to" navigation behavior.
- **Dark mode:** All new views must support both light and dark macOS appearances.
- **Performance:** Inline detail fetching should be async and non-blocking. Show loading spinners while fetching. Don't fetch detail data until the user actually expands a notification.
- **Commit after each phase** (10A, 10B, 10C, 10D, 10E) with a descriptive commit message.

# Bug-Fix Stabilization — Remaining Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the remaining 24 items from the bug-fix stabilization spec (2026-04-02). Items are grouped into 9 tasks across 3 tiers, ordered by user impact.

**Architecture:** Each task is self-contained. Tier 1 tasks have the highest user impact and should be done first. All VMs now use `@Observable` — wrap async property mutations in `withAnimation(.none)`.

**Tech Stack:** Swift 5.9, SwiftUI (@Observable), macOS 15

**Spec:** `docs/superpowers/specs/2026-04-02-bug-fix-stabilization-design.md`

**Hard Rule:** DO NOT touch integration auth/configuration code — tokens, API keys, credential discovery, auth flows, ZscalerTrustURLSession.

---

## Tier 1: High Impact

### Task 1: Dashboard Caching (spec item 2.1)

**Problem:** Dashboard reloads from scratch every visit — no caching in Feed, Auto, or Custom mode.

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift`
- Modify: `BoomiSRE/Sources/Views/DashboardView.swift`

- [ ] **Step 1: Add cache state to DashboardViewModel**

Add a `lastFetchTime: Date?` and a TTL constant. In the load method, skip fetching if data exists and TTL hasn't expired:

```swift
@ObservationIgnored private var lastFetchTime: Date?
@ObservationIgnored private let cacheTTL: TimeInterval = 300 // 5 minutes

func loadDashboard(appState: AppState, force: Bool = false) async {
    if !force, lastFetchTime != nil,
       let elapsed = lastFetchTime.map({ Date().timeIntervalSince($0) }),
       elapsed < cacheTTL, !items.isEmpty {
        return // Use cached data
    }
    withAnimation(.none) { isLoading = true }
    // ... existing fetch logic ...
    withAnimation(.none) { isLoading = false }
    lastFetchTime = Date()
}
```

- [ ] **Step 2: Wire force refresh to global refresh button**

In DashboardView, pass `force: true` when triggered by the global refresh (`refreshTrigger`):

```swift
.onChange(of: appState.refreshTrigger) { _, _ in
    Task { await vm.loadDashboard(appState: appState, force: true) }
}
```

- [ ] **Step 3: Build and verify**

```bash
swift build -c release
```

- [ ] **Step 4: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/DashboardViewModel.swift BoomiSRE/Sources/Views/DashboardView.swift
git commit -m "fix: add 5-minute cache to Dashboard — skip reload if data fresh

Spec item 2.1. Force refresh bypasses cache.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: My Work > Tickets Rework (spec items 6.1-6.4)

**Problem:** Tickets view has no filtering, no rich inline detail, no story point lens. Users have to open Jira for everything.

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift`
- Modify: `BoomiSRE/Sources/ViewModels/TodoDashboardViewModel.swift`

This is the largest remaining task. Break into sub-steps:

- [ ] **Step 1: Add status/priority/type filtering to TodoDashboardViewModel**

The VM already has `statusFilter`, `priorityFilter`, `typeFilter` properties. Verify they're wired to filter the displayed tickets. If not, add computed `filteredIssues` that applies all active filters:

```swift
var filteredIssues: [JiraIssue] {
    issues.filter { issue in
        (statusFilter == "All" || issue.fields.status?.name == statusFilter) &&
        (priorityFilter == "All" || issue.fields.priority?.name == priorityFilter) &&
        (typeFilter == "All" || issue.fields.issuetype?.name == typeFilter)
    }
}
```

- [ ] **Step 2: Add sprint and assignee filters**

Add `sprintFilter` and `assigneeFilter` properties. Populate sprint options from the `customfield_10020` sprint field. Populate assignee options from the fetched issues.

- [ ] **Step 3: Rich inline detail view**

When a ticket is selected in the HSplitView, the right pane should show:
- Formatted description (use `Text(LocalizedStringKey(desc))` — NOT MarkdownView/WKWebView)
- Comments list (viewable)
- Quick comment input (reuse pattern from NotificationDetailPane)
- Status transition buttons (reuse pattern from NotificationDetailPane)
- Editable fields: assignee, priority, story points

Read `NotificationDetailPane.swift` for the pattern — the Jira detail section there has quick comment and transitions already working.

- [ ] **Step 4: Story point lens**

Add a summary bar at the top showing:
- Total SP committed vs completed
- Planned vs unplanned breakdown
- Velocity context (SP per sprint average)

The `TodoDashboardViewModel` already fetches story points via `customfield_10008`. Add computed properties:

```swift
var totalSPCommitted: Double {
    issues.compactMap { $0.fields.storyPoints }.reduce(0, +)
}
var totalSPCompleted: Double {
    issues.filter { $0.fields.status?.statusCategory?.name == "Done" }
        .compactMap { $0.fields.storyPoints }.reduce(0, +)
}
```

- [ ] **Step 5: Build and verify**

```bash
swift build -c release && bash build_app.sh
```

- [ ] **Step 6: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/TodoDashboardViewModel.swift BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift
git commit -m "feat: rich tickets view — filtering, inline detail, SP lens

Spec items 6.1-6.4. Adds status/priority/type/sprint/assignee filters,
rich inline detail with comments + transitions, story point summary bar.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Tier 2: Medium Impact

### Task 3: Exec Assistant Fixes (spec items 11.1, 11.2)

**Problem:** Report modal scroll area takes half the modal (bottom is blank). Report cards aren't obviously clickable.

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/ExecAssistantView.swift`

- [ ] **Step 1: Fix scroll area to fill modal**

Find the ScrollView or content area in the report modal. Remove any `maxHeight` constraint or fixed frame that limits it to half. Use `.frame(maxHeight: .infinity)` and `.scrollIndicators(.hidden)`.

- [ ] **Step 2: Make report cards clickable**

Add a tap gesture and visual hover effect to report cards. Use `.contentShape(Rectangle())` for full-area hit testing and `.onHover` for cursor change:

```swift
ReportCard(report: report)
    .contentShape(Rectangle())
    .onTapGesture { selectedReport = report }
    .onHover { hovering in isHovering = hovering }
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isHovering ? Color.accentColor : .clear))
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release
git add BoomiSRE/Sources/Views/Panels/ExecAssistantView.swift
git commit -m "fix: exec assistant — full-height scroll, clickable report cards

Spec items 11.1, 11.2.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Integration Health Indicators (spec items 9.1-9.3)

**Problem:** No per-screen health banner. Health checks only verify "token exists" not actual API access.

**Files:**
- Create: `BoomiSRE/Sources/Views/Shared/IntegrationHealthBanner.swift`
- Modify: Browser views (GitHub, Bitbucket, Jenkins, Grafana, Confluence)
- Modify: `BoomiSRE/Sources/Views/Settings/IntegrationsOverviewContent.swift`

- [ ] **Step 1: Create IntegrationHealthBanner shared component**

A compact banner that shows red/yellow/green status with a message:

```swift
struct IntegrationHealthBanner: View {
    let service: String
    let status: AuthStatus
    let message: String?

    var body: some View {
        if status != .authenticated {
            HStack(spacing: 8) {
                Image(systemName: status == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status == .error ? .red : .orange)
                Text(message ?? "\(service) is not connected")
                    .font(.callout)
                Spacer()
                Button("Settings") { /* navigate to integrations */ }
                    .font(.caption).buttonStyle(.bordered)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
        }
    }
}
```

- [ ] **Step 2: Add banner to each browser view**

At the top of GitHubBrowserView, BitbucketBrowserView, JenkinsBrowserView, GrafanaBrowserView, ConfluenceBrowserView — add the banner reading from `appState.githubAuthStatus`, etc.

- [ ] **Step 3: Enhance health checks to verify API access**

In `AppState.checkAllServices()` or each service's check method, make a lightweight API call (not just token existence). For example, GitHub: try `listOrgRepos` with limit 1. Mark status as `.error` if the API call fails even though token exists.

**IMPORTANT:** Do NOT change auth code. Only add a verification call that tests the existing credentials.

- [ ] **Step 4: Build and commit**

```bash
swift build -c release
git add BoomiSRE/Sources/
git commit -m "feat: per-screen integration health banners + API verification

Spec items 9.1-9.3. Banner shows at top of each browser view when
service is unhealthy. Health checks now verify actual API access.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Settings Cleanup (spec items 14.2, 14.3, 14.5, 14.6, 14.8)

**Problem:** Exec Assistant settings not separated from Profile. Dashboard appearance section may be dead code. Notification settings lack descriptions. BPOP metrics blank. Feedback not in About.

**Files:**
- Modify: `BoomiSRE/Sources/Views/SettingsView.swift`
- Possibly create: `BoomiSRE/Sources/Views/Settings/ExecAssistantSettingsContent.swift`

- [ ] **Step 1: Extract Exec Assistant settings to own section**

Move Exec Assistant config fields out of Profile into a new "Executive Assistant" settings tab. Follow the pattern of existing settings content views.

- [ ] **Step 2: Audit Dashboard appearance section**

Check if `Appearance > Dashboard` in Settings syncs with the actual Home > Dashboard settings. If it's dead code (settings have no effect), remove it. If it works but doesn't sync, add bidirectional sync.

- [ ] **Step 3: Add descriptions to notification settings**

In the notification settings section, add `.help()` tooltips or caption text below each toggle explaining what it controls.

- [ ] **Step 4: Fix BPOP metrics**

Investigate why BPOP auto-populated metrics show blank. Check if the data pipeline in `BPOPData.swift` or the VM is failing silently. Add error display if data can't load.

- [ ] **Step 5: Move Feedback to About**

Move the Feedback section from Settings > Advanced to Settings > About.

- [ ] **Step 6: Build and commit**

```bash
swift build -c release
git add BoomiSRE/Sources/
git commit -m "fix: settings cleanup — exec assistant tab, notification descriptions, BPOP fix

Spec items 14.2, 14.3, 14.5, 14.6, 14.8.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Tier 3: Lower Impact

### Task 6: Knowledge & Tools Fixes (spec items 10.1, 10.3)

**Problem:** "No results for ''" bug. Confluence spaces don't reflect product context.

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/KnowledgeBaseView.swift`
- Modify: `BoomiSRE/Sources/ViewModels/KnowledgeBaseViewModel.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift`

- [ ] **Step 1: Fix empty search query bug**

Find where the search is triggered with an empty string. Add a guard: if search text is empty, show the default landing view instead of executing a search.

- [ ] **Step 2: Filter Confluence spaces by product context**

Use `appState.activeConfluenceSpaces` to filter the space list. Add `onChange(of: appState.activeProductIds)` to refresh when product changes.

- [ ] **Step 3: Build and commit**

```bash
swift build -c release
git add BoomiSRE/Sources/
git commit -m "fix: KB empty search bug, Confluence product context filtering

Spec items 10.1, 10.3.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Global UI Fixes (spec items 15.1, 15.5, 15.6, 15.7)

**Problem:** Global Search is navigator-only. Collapsed sidebar clips badge, confusing icons, team section disappears.

**Files:**
- Modify: `BoomiSRE/Sources/Views/SidebarView.swift`
- Modify: `BoomiSRE/Sources/ContentView.swift`

- [ ] **Step 1: Collapsed sidebar — widen or reposition notification badge**

Adjust the badge position so it doesn't clip when sidebar is collapsed. Use `.offset()` or increase collapsed sidebar minimum width.

- [ ] **Step 2: Add tooltips to collapsed sidebar icons**

Add `.help("Alerts & On-Call")` etc. to each sidebar item so they show tooltips on hover when collapsed.

- [ ] **Step 3: Keep team section visible when collapsed**

Show a compact team icon when sidebar is collapsed instead of hiding the section entirely.

- [ ] **Step 4: Global Search — add content search**

Either rename "Search" to "Navigate" to set correct expectations, or add basic content search that searches across tickets, pages, and notifications by keyword.

- [ ] **Step 5: Build and commit**

```bash
swift build -c release
git add BoomiSRE/Sources/
git commit -m "fix: sidebar collapse fixes, tooltips, team section, search

Spec items 15.1, 15.5, 15.6, 15.7.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Menu Bar — Factory Reset (spec item 16.5)

**Problem:** Factory Reset is accessible from Help menu — too dangerous for a quick-access location.

**Files:**
- Modify: `BoomiSRE/Sources/BoomiSREApp.swift` (or wherever the Help menu commands are defined)

- [ ] **Step 1: Remove Factory Reset from Help menu**

Find the `CommandGroup` or `Commands` that adds Factory Reset to Help. Remove it. Keep the one in Settings > Advanced.

- [ ] **Step 2: Build and commit**

```bash
swift build -c release
git add BoomiSRE/Sources/
git commit -m "fix: remove Factory Reset from Help menu — keep only in Settings

Spec item 16.5.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Theme Polish (spec items 3.2, 14.4)

**Problem:** Brand colors underutilized. AI Preferences summary missing from Copilot screen.

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/CopilotChatView.swift`
- Modify: Various view files for theme pass

- [ ] **Step 1: Add AI Preferences summary to Copilot screen**

At the top of CopilotChatView, show a compact summary of current AI settings (model, depth, persona) with a "Customize" link to Settings > AI Preferences.

- [ ] **Step 2: Boomi brand color pass**

Review key surfaces (sidebar headers, section cards, badges, buttons) and apply `BoomiColors` more prominently. Focus on:
- Sidebar section headers
- Dashboard widget headers
- Status badges and pills
- Button accents

Use the existing `BoomiColors` and `DesignTokens` from `ViewStyles.swift`.

- [ ] **Step 3: Build and commit**

```bash
swift build -c release && bash build_app.sh
git add BoomiSRE/Sources/
git commit -m "feat: AI preferences summary on Copilot, brand color polish

Spec items 3.2, 14.4.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Final Step

After all tasks:

- [ ] **Full build and release**

```bash
swift build -c release && bash build_app.sh
git push && bash release.sh
```

- [ ] **Grep for any spec items still unaddressed**

Review spec one more time to confirm all 54 items are either done or explicitly deferred.

---

## Execution Notes

- **Task 2 is the largest** — consider breaking into 2 subagent dispatches (filtering + inline detail as one, SP lens as another)
- **All VMs are already @Observable** — use `withAnimation(.none)` for async property sets
- **Do NOT touch auth code** — display-layer fixes only for integration health
- **MarkdownView gotcha** — use native `Text(LocalizedStringKey(desc))` for Jira content, NOT WKWebView
- **Test each task** with `bash build_app.sh` and manual smoke test before committing

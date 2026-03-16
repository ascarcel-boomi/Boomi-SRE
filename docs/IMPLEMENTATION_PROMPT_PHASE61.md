# Boomi SRE App — Phase 61: Unify Navigation — Widget Clicks Should Go to Sidebar Panels

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/ContentView.swift` — `detailContent` view builder (lines 166-237) has TWO routing paths: one for `selectedReport` (old, direct views) and one for `selectedSidebarItem` (new, tabbed panels)
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `WidgetCard` uses `navigateTo` which sets `appState.selectedReport`
- `BoomiSRE/Sources/Views/FeedView.swift` — feed items use `navigateTo` which sets `appState.selectedReport`
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar sets `appState.selectedSidebarItem`
- `BoomiSRE/Sources/Views/BreadcrumbView.swift` — reads breadcrumb from `selectedReport.section` which still references old `ReportSection.commandCenter`
- `BoomiSRE/Sources/Models/ReportItem.swift` — `ReportSection` still has `.commandCenter` and old section names

---

## Problem

There are two separate navigation systems that show different views for the same content:

1. **Sidebar navigation** (`selectedSidebarItem`): Goes to combined tabbed panels — `AlertsOnCallPanel`, `MyWorkPanel`, etc. These are the correct, current views.

2. **Widget/Feed navigation** (`selectedReport`): Goes to raw individual views — `OnCallView()`, `NotificationCenterView()`, etc. via the old `detailContent` switch. These bypass the tabbed panels and show a different layout with old breadcrumbs like "Command Center > On-Call".

The user sees two different experiences depending on HOW they navigate to the same feature.

## Fix

### Phase 61A: Make Widget/Feed Navigation Use Sidebar Items

When a widget or feed item navigates, it should set `selectedSidebarItem` (the new system) instead of `selectedReport` (the old system). The `selectedReport` routing should only be used as a fallback.

**In `WidgetCard`** (WidgetViews.swift), change the navigation action:

```swift
Button {
    if let nav = navigateTo {
        // NEW: Navigate via sidebar items, not direct report selection
        appState.showSettings = false
        appState.selectedTicketKey = nil
        appState.selectedReport = nil  // clear old report selection

        // Map navigateTo IDs to sidebar items
        switch nav {
        case "oncall", "notifications":
            appState.selectedSidebarItem = "alerts"
        case "incidents":
            appState.selectedSidebarItem = "incidents"
        case "jira_todo", "jira_filters", "jira_boards", "github_browser", "jenkins_browser":
            appState.selectedSidebarItem = "mywork"
        case "aws_health", "aws_cost_explorer", "bitbucket_browser":
            appState.selectedSidebarItem = "infra"
        case "knowledge_base", "confluence_browser", "copilot_chat", "exec_assistant":
            appState.selectedSidebarItem = "knowledge"
        case "google_gmail", "google_calendar", "google_chat":
            appState.selectedSidebarItem = "communicate"
        default:
            // Fallback to old system for anything unmapped
            appState.selectedReport = ReportCatalog.all.first { $0.id == nav }
        }
    }
    onTap?()
} label: {
    // ... existing label
}
```

**Do the same in `FeedItemCard`** (FeedView.swift) for the "View All" navigation and any action that navigates away.

**Do the same in `ContentView.navigateTo()`** (line ~242):
```swift
private func navigateTo(_ reportId: String) {
    appState.showSettings = false
    appState.selectedTicketKey = nil
    appState.selectedReport = nil

    switch reportId {
    case "oncall", "notifications":
        appState.selectedSidebarItem = "alerts"
    case "incidents":
        appState.selectedSidebarItem = "incidents"
    case "jira_todo", "jira_filters", "jira_boards", "github_browser", "jenkins_browser":
        appState.selectedSidebarItem = "mywork"
    case "aws_health", "aws_cost_explorer", "bitbucket_browser":
        appState.selectedSidebarItem = "infra"
    case "knowledge_base", "confluence_browser", "copilot_chat", "exec_assistant":
        appState.selectedSidebarItem = "knowledge"
    case "google_gmail", "google_calendar", "google_chat":
        appState.selectedSidebarItem = "communicate"
    default:
        appState.selectedReport = ReportCatalog.all.first { $0.id == reportId }
    }
}
```

### Phase 61B: Remove or Minimize the Old selectedReport Routing

The `detailContent` switch (lines 175-217) has 18 cases that render views directly via `selectedReport`. Most of these are now redundant since the sidebar panels contain the same views as tabs.

**Simplify `detailContent`** to prioritize sidebar routing:

```swift
@ViewBuilder
private var detailContent: some View {
    if let ticketKey = appState.selectedTicketKey {
        TicketDetailView(ticketKey: ticketKey) { appState.selectedTicketKey = nil }
    } else if appState.showSettings {
        SettingsView()
    } else {
        // Primary routing: by sidebar item (new system)
        switch appState.selectedSidebarItem {
        case "home":       DashboardView()
        case "alerts":     AlertsOnCallPanel()
        case "incidents":  IncidentCommandView()
        case "mywork":     MyWorkPanel()
        case "infra":      InfrastructurePanel()
        case "knowledge":  KnowledgeToolsPanel()
        case "communicate": CommunicatePanel()
        default:           DashboardView()
        }
    }
}
```

**Remove the `selectedReport` routing entirely** — all navigation now goes through `selectedSidebarItem`. The `selectedReport` property can stay on AppState for backward compatibility, but it shouldn't drive the detail view anymore.

If some features NEED the old `selectedReport` routing (e.g., opening a specific tab within a panel), handle it within the panel views themselves. For example, `AlertsOnCallPanel` could read `appState.selectedReport?.id == "oncall"` to auto-select the On-Call tab.

### Phase 61C: Fix the Breadcrumb

The breadcrumb shows "Home > Command Center > On-Call" because it reads from `selectedReport.section` which is `ReportSection.commandCenter`. Since we're no longer using `selectedReport` for navigation, the breadcrumb should read from `selectedSidebarItem` instead:

```swift
// In BreadcrumbView:
// Instead of reading from appState.selectedReport.section:
let sectionName = {
    switch appState.selectedSidebarItem {
    case "alerts":     return "Alerts & On-Call"
    case "incidents":  return "Incidents"
    case "mywork":     return "My Work"
    case "infra":      return "Infrastructure"
    case "knowledge":  return "Knowledge & Tools"
    case "communicate": return "Communicate"
    default:           return ""
    }
}()
```

Remove any reference to `ReportSection.commandCenter` in the breadcrumb display.

### Phase 61D: Clean Up ReportSection.commandCenter

The `ReportSection.commandCenter` enum case is a leftover from the old 8-section sidebar. It's no longer displayed anywhere but still exists in the code and confuses the breadcrumb.

Options:
1. **Remove it entirely** from the enum and update all `ReportItem` entries that reference it
2. **Or rename it** to something that doesn't appear in breadcrumbs

Since `ReportItem` and `ReportCatalog` are still used for things like the global search, keep them but update the section assignments:
- `notifications` → `.alerts` or a generic section
- `incidents` → `.incidents`
- `oncall` → `.alerts`
- `copilot_chat` → `.knowledge`
- `exec_assistant` → `.knowledge`

Or simply don't show `ReportSection` in the breadcrumb anymore since we're using `selectedSidebarItem` for display.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. **Test manually:** Click the JSM Ops Alerts widget → should go to "Alerts & On-Call" with On-Call tab, same as clicking the sidebar.
4. Commit with message: "Unify navigation — widgets and feed use sidebar panels, remove Command Center breadcrumb"
5. `git push origin main`
6. `bash build_app.sh`
7. `bash release.sh`
8. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

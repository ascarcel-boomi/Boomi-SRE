# Interactive Work Map — Design Spec

**Date:** 2026-04-11
**Status:** Approved
**Scope:** New "Work Map" tab in My Work panel — D3.js tree in WKWebView

---

## Problem

The My Work panel shows tickets as flat lists (Tickets, Boards, Saved Filters). Users lack a hierarchical view showing how their epics, stories, and tasks relate. An HTML prototype exists (`~/reports/q1cy26_work_map.html`) with D3.js collapsible tree, zoom/pan, tooltips, and filtering — but it uses hardcoded data.

## Requirements

### R1: Work Map Tab

- New "Work Map" tab in the My Work panel tab picker, alongside Tickets, Boards, Saved Filters.
- Top bar with: title, stats summary (epic count, issue count, completion %), search field, status filter dropdown, "Fit to View" button, refresh button.
- Main area: WKWebView rendering D3.js collapsible tree, full width/height.
- Bottom-left legend overlay: Done (green), In Progress (amber), To Do (gray), Stale (red).

### R2: Data Fetching

- Fetch epics from active Jira projects: `issuetype = Epic AND project IN (activeProjectKeys)`.
- For each epic, fetch child issues: `parent = {epicKey}` with fields: summary, status, priority, assignee, story points.
- Build a JSON tree structure: projects at root, epics as children, stories/tasks as leaves.
- Respect the product filter (`activeProductIds`). When "all products," use all active Jira project keys.
- Use `searchIssuesRaw` with `maxResults: 200` per epic to get children.
- Parallel batch fetching: fetch children for up to 5 epics concurrently via `withTaskGroup`.

### R3: Tree Rendering (D3.js in WKWebView)

- Adapted from the prototype: collapsible tree layout, zoom/pan, expand/collapse, status coloring, tooltips.
- Remove hardcoded data from prototype; add `loadData(jsonString)` JS entry point.
- D3 tree configuration: `nodeSize([24, 250])`, depth spacing 280px.
- Node sizing: projects = 8px radius, epics = 6px, stories = 4px.
- Status colors: Done = `#1a7f37`, In Progress = `#9a6700`, To Do = `#484f58`, Stale = `#da3633`.
- Stale = status category "In Progress" but not updated in 14+ days.
- Epics collapsed by default; projects expanded.
- Tooltips: Jira key, summary, status badge, SP, assignee, "Click to open in Tickets →".
- Search: highlights matching nodes and dims others (same as prototype).
- Status filter: hides non-matching subtrees (same as prototype).
- Supports light and dark mode via `prefers-color-scheme`.

### R4: Swift ↔ JS Bridge

- **Swift → JS**: `evaluateJavaScript("loadData(\(treeJSON))")` — pass tree data after fetch.
- **Swift → JS**: `evaluateJavaScript("filterByStatus('\(status)')")` — status filter changes.
- **Swift → JS**: `evaluateJavaScript("searchNodes('\(query)')")` — search text changes.
- **Swift → JS**: `evaluateJavaScript("fitToView()")` — fit to view button.
- **JS → Swift**: `window.webkit.messageHandlers.nodeClick.postMessage(key)` — node click.
- **Swift handler**: `appState.pushNavigation(); appState.selectedTicketKey = key` — navigate to ticket detail.

### R5: WKWebView Integration

- Use `ScrollForwardingWebView` (existing) with `forwardScrollEvents = false` (D3 handles its own zoom/pan).
- Register `WKScriptMessageHandler` for `nodeClick` channel.
- HTML loaded from bundled resource (`Resources/work_map.html`).
- All network calls go through Swift (JiraService) — the WKWebView is offline, no network access needed.

## Architecture

### Files

| Action | File | Purpose |
|--------|------|---------|
| Create | `BoomiSRE/Sources/ViewModels/WorkMapViewModel.swift` | Fetch epics + children, build tree JSON, filter/search state |
| Create | `BoomiSRE/Sources/Views/Panels/WorkMapView.swift` | SwiftUI view: top bar + WKWebView + legend overlay |
| Create | `BoomiSRE/Sources/Resources/work_map.html` | D3.js tree renderer with `loadData()` entry point |
| Modify | `BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift` | Add "Work Map" tab to the picker |
| Modify | `Package.swift` | Add `work_map.html` to resources |

### ViewModel (`WorkMapViewModel`)

```
@Observable @MainActor final class WorkMapViewModel {
    var treeJSON: String = ""
    var isLoading = false
    var epicCount = 0
    var issueCount = 0
    var completionPct = 0.0
    var statusFilter: String = "All"
    var searchText: String = ""
    @ObservationIgnored private let jiraService = JiraService()

    func loadTree(appState: AppState) async { ... }
}
```

### Data Flow

```
loadTree(appState)
  → JQL: issuetype = Epic AND project IN (keys) AND statusCategory != Done
  → For each epic (batched, 5 concurrent):
      → JQL: parent = {epicKey}
  → Build tree: { name: projectKey, children: [{ name: epicKey, ..., children: [...] }] }
  → Serialize to JSON string → treeJSON
  → WKWebView.evaluateJavaScript("loadData(\(treeJSON))")
```

### Node Click Flow

```
D3 node click → JS postMessage("CAMSRE-25020")
  → WKScriptMessageHandler receives key
  → appState.pushNavigation()
  → appState.selectedTicketKey = "CAMSRE-25020"
  → TodoDashboardView switches to Tickets tab, detail pane opens
```

## Mandatory Patterns

- `@Observable` VM, `@State` in views, `withAnimation(.none)` on async mutations.
- `@ObservationIgnored` on `jiraService`.
- `ZscalerTrustURLSession.shared` for all HTTP (via JiraService).
- Design tokens from `ViewStyles.swift` for the top bar and legend.
- Product-filter-first: respect `appState.activeJiraProjectKeys`.

## Out of Scope

- Inline editing from the tree (use Tickets detail pane instead).
- Drag-and-drop reparenting of issues.
- Real-time updates / live polling (manual refresh only).
- Export to image/PDF.

## Test Plan

1. **Tab visible**: Open My Work, verify "Work Map" tab appears in picker.
2. **Data loads**: Select Work Map, verify tree renders with epics from active projects.
3. **Expand/collapse**: Click an epic node, verify children expand. Click again to collapse.
4. **Zoom/pan**: Scroll to zoom, drag to pan. Click "Fit to View" to reset.
5. **Status filter**: Select "In Progress" from dropdown, verify only matching subtrees shown.
6. **Search**: Type a ticket key, verify matching node highlighted.
7. **Navigate**: Click a story node, verify app navigates to Tickets tab with that ticket selected.
8. **Product filter**: Change product in top dropdown, verify tree reloads with different projects.
9. **Dark/light mode**: Toggle appearance, verify tree colors adapt.

# Ticket Polish — Round 1: Rich Rendering + Chart Interactivity

**Date:** 2026-04-05
**Status:** Approved
**Scope:** Ticket detail rendering improvements + chart click-to-filter + category alignment

## Problem Statement

Two usability gaps in the My Work / Tickets area:

1. **Truncated content** — Ticket descriptions and comments render via MarkdownView (WKWebView) but are capped at 500px / 300px maxHeight, cutting off long content. The ADF→markdown conversion is already wired up; the problem is purely visual.

2. **Non-interactive charts** — The "By Category" and "By Priority" charts in TodoDashboardView are display-only. Users expect to click a pie slice or bar segment to filter the ticket list (like AWS Costs charts do). Additionally, the "By Category" chart uses TodoCategory values (Overdue / In Progress / Sprint To-Do / Unplanned) while the Status filter uses TicketStatusFilter values (To Do / In Progress / Done) — a confusing mismatch.

## Requirements

1. Description section in TicketDetailView must show full content without truncation
2. Comments section in TicketDetailView must show full content without truncation
3. ReportChartView must support an optional click callback without breaking existing callers
4. Pie chart slices must be clickable with visual highlight on selection
5. Bar and stacked bar chart segments must be clickable with visual highlight on selection
6. Clicking a selected item again deselects it (toggle behavior)
7. "By Category" chart must be renamed to "By Status" and group by TicketStatusFilter values
8. Clicking a chart segment in TodoDashboardView must filter the ticket list below
9. TodoCategory enum and stat pills row remain unchanged

## Design

### A. Ticket Detail Rich Rendering

**Files:** `Views/Panels/TicketDetailView.swift`

Two frame changes:

- **Description** (line 362): `.frame(minHeight: 80, maxHeight: 500)` → `.frame(minHeight: 80, maxHeight: .infinity)`
- **Comments** (line 385): `.frame(minHeight: 40, maxHeight: 300)` → `.frame(minHeight: 40, maxHeight: .infinity)`

WKWebView handles its own internal scrolling. The parent ScrollView (line 46) handles outer scrolling. This is the same pattern used in incident detail views.

**Fallback:** If `.maxHeight: .infinity` causes layout thrashing (as it did in NotificationDetailPane), use a large fixed cap like `maxHeight: 2000`.

### B. ReportChartView Selection Callback

**Files:** `Views/Charts/ReportChartView.swift`

Add to the struct:
- `var onSelect: ((String) -> Void)? = nil` — optional, non-breaking for existing callers
- `@State private var selectedLabel: String? = nil` — tracks visual highlight

Add `.chartOverlay` with `onTapGesture` to three chart types:

- **pieChart:** Angle-based hit detection — compute angle from tap point relative to chart center, map to the corresponding slice label
- **barChart:** Y-position approach from CostExplorerView (line 563-579) — divide plot height by item count
- **stackedBarChart:** Same positional approach, detecting which category bar was tapped

Add `.opacity` modifier to chart marks: selected label gets 1.0, others get 0.4 when a selection is active. No selection = all at 1.0.

Toggle behavior: tapping the already-selected label sets `selectedLabel = nil` and calls `onSelect("")` (empty string). Consumer interprets empty string as "clear filter" (set to `.all`).

**Existing callers unaffected:** BoardsView, SavedFiltersView, and any other caller that doesn't pass `onSelect` gets `nil` — no visual selection, no callbacks.

### C. Chart Category Alignment

**Files:** `ViewModels/TodoDashboardViewModel.swift`, `Views/Panels/TodoDashboardView.swift`

**ViewModel changes:**

In `buildChartSections(from:)`, replace the TodoCategory-based "By Category" section:

```
// Before: groups by TodoCategory (Overdue, In Progress, Sprint To-Do, Unplanned)
// After: groups by status mapped to TicketStatusFilter (To Do, In Progress, Done)
```

Status mapping logic:
- "Done", "Closed", "Resolved" → Done
- "In Progress", "In Review", "In Development" → In Progress
- Everything else → To Do

Keep the stacked bar with priority as the group dimension (priority breakdown within each status bucket).

Rename section title: "By Category" → "By Status"

**View changes:**

In `TodoDashboardView.chartRow`, pass `onSelect` to both ReportChartView instances:

- "By Status" chart `onSelect`: sets `viewModel.statusFilter` to matching `TicketStatusFilter` case, or `.all` if tapping already-selected
- "By Priority" chart `onSelect`: sets `viewModel.priorityFilter` to matching `TicketPriorityFilter` case, or `.all` if tapping already-selected

## Dependencies

- `MarkdownView` (Views/Shared/MarkdownView.swift) — no changes needed
- `extractMarkdownFromADF` (ViewModels/TicketDetailViewModel.swift) — no changes needed
- `ResultSection` / `ResultRow` models — no changes needed
- `TodoCategory` enum — kept as-is, still used for stat pills

## Out of Scope

- Notification redesign (Round 2)
- Bitbucket preloading (Round 2)
- New chart types or chart component refactoring beyond adding selection
- Changes to MarkdownView internals
- Any auth/configuration code changes

## Test Plan

1. **Description rendering:** Open CAMSRE-23457 in app, compare description with Jira web UI — full content visible, links clickable, no truncation
2. **Comment rendering:** Same ticket — all comments fully visible, no truncation, markdown formatting correct
3. **Chart click — pie:** Click a priority slice → ticket list filters to that priority. Click again → filter clears.
4. **Chart click — stacked bar:** Click a status segment → ticket list filters to that status. Click again → filter clears.
5. **Chart labels:** Verify "By Status" chart shows To Do / In Progress / Done (not Overdue / Unplanned)
6. **Visual highlight:** Selected slice/bar is full opacity, others dimmed. No selection = all full opacity.
7. **Non-breaking:** BoardsView and SavedFiltersView charts still render correctly with no click behavior.
8. **Build:** `swift build` succeeds with no errors.

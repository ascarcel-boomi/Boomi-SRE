# Boomi SRE App — Phase 38: Fix Widget Sizes, Smarter Auto Mode & Alert Consolidation

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/DashboardView.swift` — dashboard layout, `widgetGrid`, `widgetRows()`, `autoWidgets()`, `urgencyScore()`, health score, customize sheet
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `WidgetCard` base component and all individual widget views (JSMOpsAlertsWidget, GrafanaAlertsWidget, etc.)
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `WidgetType`, `WidgetSize`, `DashboardWidget`
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching, `jsmOpsAlerts`, `firingAlerts`

---

## Problems to Fix

### Problem 1: Widget sizes S/M/L don't actually change the widget appearance

The S/M/L setting only affects whether widgets go side-by-side (S/M) or full-width (L) in `widgetRows()`. But the actual widget content is identical at every size. A "Small" widget shows the exact same amount of data as a "Large" one — the only difference is the column layout.

**Expected behavior:**
- **Small:** Compact — show only a count/summary (e.g., "3 open alerts"), no detail rows. Max height ~80pt.
- **Medium:** Standard — show a summary + top 3-5 items. Max height ~200pt.
- **Large:** Expanded — show everything: summary, all items (up to 10), charts if applicable. No max height constraint.

### Problem 2: Auto mode doesn't feel intelligent

The current `autoWidgets()` sorts by urgency score and assigns sizes, but the user can't see WHY it made those decisions. The urgency scores are calculated but not displayed. The auto mode should feel obviously smart — the user should look at the dashboard and think "yes, that's exactly what I need to see right now."

### Problem 3: JSM Ops Alerts and Grafana Alerts should both appear prominently

Both alert sources should be visible on the home page. Currently they're separate widgets that may or may not appear depending on configuration.

---

## Implementation

### Phase 38A: Pass Widget Size to Every Widget View

1. **Add `size: WidgetSize` parameter to `WidgetCard`:**
   ```swift
   struct WidgetCard<Content: View>: View {
       let type: WidgetType
       let size: WidgetSize       // ← NEW
       var navigateTo: String? = nil
       // ...
   }
   ```

2. **Pass the widget size from `widgetView(for:)` in DashboardView:**
   ```swift
   private func widgetView(for widget: DashboardWidget) -> some View {
       switch widget.type {
       case .jsmOpsAlerts:
           JSMOpsAlertsWidget(alerts: vm.jsmOpsAlerts, size: widget.size).environmentObject(appState)
       case .grafanaAlerts:
           GrafanaAlertsWidget(alerts: vm.firingAlerts, size: widget.size).environmentObject(appState)
       // ... same for ALL widget types
       }
   }
   ```

3. **Update EVERY widget view** to accept and respond to `size: WidgetSize`. Each widget should adapt its content based on size.

### Phase 38B: Make Every Widget Size-Responsive

Update each widget in `WidgetViews.swift` to render differently at each size. Here are the rules:

**General pattern for all widgets:**

```swift
struct SomeWidget: View {
    let data: [SomeModel]
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .someType, size: size, navigateTo: "some_destination") {
            switch size {
            case .small:
                smallView
            case .medium:
                mediumView
            case .large:
                largeView
            }
        }
    }

    private var smallView: some View {
        // Just a count + status icon, one line
        HStack(spacing: 8) {
            Text("\(data.count)").font(.title2.bold())
            Text("items").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        // Count + top 3-5 items
        VStack(alignment: .leading, spacing: 6) {
            Text("\(data.count) items").font(.callout.bold())
            ForEach(data.prefix(4)) { item in
                // compact row
            }
            if data.count > 4 { Text("+ \(data.count - 4) more").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var largeView: some View {
        // Full detail: count, all items (up to 10), any charts
        VStack(alignment: .leading, spacing: 8) {
            Text("\(data.count) items").font(.callout.bold())
            ForEach(data.prefix(10)) { item in
                // detailed row with more info
            }
            if data.count > 10 { Text("+ \(data.count - 10) more").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
```

**Specific widget size behaviors:**

| Widget | Small | Medium | Large |
|--------|-------|--------|-------|
| **JSM Ops Alerts** | "3 open · 1 P1" one-line | Counts + top 5 alerts (priority + message) | All alerts with full detail (source, tags, time) |
| **Grafana Alerts** | "2 firing" one-line | Count + top 4 alert names | All alerts with state, summary, dashboard link |
| **Active Incidents** | "1 P1 active" one-line | Count + top 3 incidents | All incidents with timeline preview |
| **My Tickets** | "8 tickets" one-line | Count + top 5 by priority | All tickets with status, assignee, due date |
| **Jenkins Builds** | "1 failed" one-line | Last 3 builds with status | Last 8 builds with duration, branch |
| **Recent PRs** | "4 open PRs" one-line | Top 3 PRs with repo + title | All PRs with author, branch, CI status |
| **Calendar** | "Next: Standup 10m" | Next 3 events with time | Today's full schedule |
| **Email** | "5 unread" one-line | Top 3 subjects | Top 8 with sender, subject, preview |
| **Service Health** | Row of colored dots only | Dots + service names | Full service list with status detail |
| **Quick Actions** | 2 icon buttons | 4 icon+label buttons | Full button bar with descriptions |
| **AI Summary** | First sentence only | First 3 sentences | Full summary |

4. **Enforce height constraints** per size to keep the layout predictable:
   ```swift
   .frame(maxHeight: size == .small ? 80 : size == .medium ? 200 : .infinity)
   .clipped()
   ```

### Phase 38C: Truly Intelligent Auto Mode

Rewrite `autoWidgets()` to be obviously smart. The user should look at their dashboard and think "wow, it knows exactly what I need."

**Rules for the AI-managed dashboard:**

1. **Emergency tier (urgency 80+) → Large, at the very top:**
   - Any P1 incident → large at position 0
   - Any P1/P2 JSM Ops alert unacknowledged → large at position 1
   - Any Grafana alert firing → large (if multiple) or medium (if 1)

2. **Action needed tier (urgency 40-79) → Medium, above the fold:**
   - Failed Jenkins builds → medium
   - Overdue Jira tickets → medium
   - Unacknowledged P3+ alerts → medium
   - PRs awaiting your review → medium

3. **Informational tier (urgency 10-39) → Small, below the fold:**
   - Open PRs (no action needed from you) → small
   - Upcoming calendar events → small (medium if meeting in <30min)
   - Unread emails → small
   - AI Summary → medium (always useful context)

4. **All clear tier (urgency <10) → Small or hidden:**
   - Service health (all green) → small
   - Quick actions → small
   - Confluence recent → small
   - AWS cost trend → small

5. **Key intelligence rules:**
   - If there are ZERO items needing attention (everything is green), show the AI Summary as large at the top with a congratulatory message, followed by quick actions
   - If the user has a meeting in <15 minutes AND unread emails, promote both calendar and email to medium
   - If all JSM Ops alerts are acknowledged, demote that widget from large to medium
   - If the SRE Health Score is 100, show a special "Perfect Score" message in the health bar
   - NEVER show an empty large widget — if a widget has no data, force it to small

6. **Show urgency reasoning in the Auto mode customize sheet:**
   ```
   AI Dashboard Manager
   ─────────────────────
   🔴 JSM Ops Alerts (urgency: 85) → Large
       2 unacknowledged P2 alerts need action
   🟡 Jenkins Builds (urgency: 55) → Medium
       1 failed build in last hour
   🟢 My Tickets (urgency: 30) → Small
       8 tickets, none overdue
   🟢 Calendar (urgency: 15) → Small
       Next meeting in 2 hours
   ```

### Phase 38D: Consolidate All Alert Sources

Create an intelligent alert summary that appears in the health score bar or as a top-level banner when there are active alerts from ANY source:

1. **In the health score bar**, add a concise alert summary line:
   ```
   🛡️ SRE Health: ████████████████░░░░ 72%  Needs Attention ⚠️
   2 JSM Ops alerts (1 P1, 1 P3) · 1 Grafana alert firing · 1 failed build
   ```

   The summary line should show counts from every alert source:
   - JSM Ops: count of open + unacknowledged
   - Grafana: count of firing alerts
   - Jenkins: count of failed builds
   - Incidents: count of active P1/P2 incidents

   Only show sources that have issues. If everything is clear:
   ```
   🛡️ SRE Health: ████████████████████ 100%  Excellent — all systems go 🟢
   ```

2. **Make the alert summary clickable** — each source count is a button:
   - Clicking "2 JSM Ops alerts" navigates to On-Call
   - Clicking "1 Grafana alert" navigates to Grafana
   - Clicking "1 failed build" navigates to Jenkins

### Phase 38E: Fix the Customize Sheet

1. **Make drag-and-drop actually work** in the customize sheet. Currently the sheet shows a drag handle icon but doesn't support actual dragging. Use SwiftUI's `List` with `onMove` modifier:
   ```swift
   List {
       ForEach($appState.dashboardWidgets.sorted(...)) { $widget in
           // widget row
       }
       .onMove { source, destination in
           appState.dashboardWidgets.move(fromOffsets: source, toOffset: destination)
           for i in appState.dashboardWidgets.indices {
               appState.dashboardWidgets[i].position = i
           }
           appState.saveConfig()
       }
   }
   .listStyle(.plain)
   ```

2. **Show a live preview** of what the dashboard will look like based on current settings. Add a small preview area at the bottom of the customize sheet showing colored rectangles representing widget sizes and positions.

3. **In Auto mode, show the urgency score** next to each widget and explain why it was placed where it is.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break existing dashboard functionality — enhance it.
- The Small size must be meaningfully different from Medium — if a widget shows the same content at both sizes, it feels broken.
- Test each widget at all 3 sizes to ensure they render correctly.
- The Auto mode should be so good that most users never switch to Custom. It should feel like having a smart assistant organizing your desk.

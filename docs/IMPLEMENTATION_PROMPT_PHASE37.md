# Boomi SRE App — Phase 37: Smart Dashboard — Drag-and-Drop, Urgency-Driven Layout & Gamification

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/DashboardView.swift` — home page: widget grid, customize sheet, MOTD, auto mode logic
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching for all widgets
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `WidgetType`, `WidgetSize`, `DashboardWidget`, defaults
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — all widget views including `WidgetCard` base component

---

## Vision

The home page should be a **living, intelligent command center** that:
1. Shows the most urgent items at the top, automatically
2. Grows widgets that need attention and shrinks those that are resolved
3. Lets users drag widgets to reorder them
4. Lets users choose widget sizes (S/M/L)
5. Gamifies the SRE workflow with an overall health score

**The home page should be so smart and useful that it's the only window an SRE needs to look at for 90% of their day.**

---

## Implementation

### Phase 37A: Drag-and-Drop Widget Reordering

**Replace the current static grid layout** with a drag-reorderable list.

1. **In `DashboardView`, replace `widgetGrid`** with a `LazyVStack` that supports drag-and-drop reordering:

   ```swift
   private var widgetGrid: some View {
       LazyVStack(spacing: 16) {
           ForEach(enabledWidgets) { widget in
               widgetView(for: widget)
                   .onDrag {
                       NSItemProvider(object: widget.id.uuidString as NSString)
                   }
                   .onDrop(of: [.text], delegate: WidgetDropDelegate(
                       item: widget,
                       items: $appState.dashboardWidgets,
                       draggedItem: $draggedWidget
                   ))
           }
       }
   }

   @State private var draggedWidget: DashboardWidget?
   ```

2. **Create a `WidgetDropDelegate`** that handles reordering:
   ```swift
   struct WidgetDropDelegate: DropDelegate {
       let item: DashboardWidget
       @Binding var items: [DashboardWidget]
       @Binding var draggedItem: DashboardWidget?

       func performDrop(info: DropInfo) -> Bool {
           draggedItem = nil
           return true
       }

       func dropEntered(info: DropInfo) {
           guard let dragged = draggedItem,
                 dragged.id != item.id,
                 let fromIndex = items.firstIndex(where: { $0.id == dragged.id }),
                 let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
           withAnimation(.easeInOut(duration: 0.2)) {
               items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
               // Update position values to match new order
               for i in items.indices { items[i].position = i }
           }
       }

       func dropUpdated(info: DropInfo) -> DropProposal? {
           DropProposal(operation: .move)
       }
   }
   ```

3. **Visual feedback during drag:**
   - The dragged widget should have reduced opacity (0.5)
   - A subtle insertion indicator (blue line) shows where the widget will be dropped
   - Animate the reorder with `.animation(.easeInOut)`

4. **Save the new order** — after any reorder, call `appState.saveConfig()` to persist.

5. **Widget size affects layout within the list:**
   - **Small widgets:** rendered side-by-side (2 per row) using an `HStack` wrapper. Group consecutive small widgets into pairs.
   - **Medium widgets:** rendered side-by-side (2 per row), same as small but with more content.
   - **Large widgets:** full width, one per row.
   - The drag-and-drop works at the widget level, regardless of size. When a user drags a small widget between two large ones, it snaps into place correctly.

### Phase 37B: Widget Size Controls Inline

Instead of only being able to change widget size in the customize sheet, add **inline size controls** visible on hover:

1. **On each `WidgetCard`, show a tiny size control on hover** (top-right corner):
   ```swift
   .overlay(alignment: .topTrailing) {
       if isHovering {
           HStack(spacing: 2) {
               Button { setSize(.small) } label: { Text("S").font(.caption2) }
               Button { setSize(.medium) } label: { Text("M").font(.caption2) }
               Button { setSize(.large) } label: { Text("L").font(.caption2) }
           }
           .buttonStyle(.bordered).controlSize(.mini)
           .padding(6)
           .transition(.opacity)
       }
   }
   .onHover { isHovering = $0 }
   ```

2. Also show a drag handle on hover (left side):
   ```swift
   .overlay(alignment: .leading) {
       if isHovering {
           Image(systemName: "line.3.horizontal")
               .font(.caption).foregroundStyle(.tertiary)
               .padding(.leading, 6)
       }
   }
   ```

### Phase 37C: Smart Auto Mode — Urgency-Driven Layout

**Completely rewrite `autoWidgets()`** to be truly intelligent. The AI-managed mode should analyze the actual data in each widget and make smart layout decisions.

```swift
private func autoWidgets(from widgets: [DashboardWidget]) -> [DashboardWidget] {
    var result = widgets

    // Filter out unconfigured services (existing logic — keep it)
    result = result.filter { widgetIsConfigured($0) }

    // Calculate urgency score for each widget
    var scored: [(widget: DashboardWidget, urgency: Int)] = result.map { widget in
        let urgency = urgencyScore(for: widget.type)
        return (widget, urgency)
    }

    // Sort by urgency (highest first)
    scored.sort { $0.urgency > $1.urgency }

    // Assign sizes based on urgency
    for i in scored.indices {
        if scored[i].urgency >= 80 {
            scored[i].widget.size = .large      // Critical — full width, maximum visibility
        } else if scored[i].urgency >= 40 {
            scored[i].widget.size = .medium     // Needs attention — standard size
        } else {
            scored[i].widget.size = .small      // All clear — compact
        }
        scored[i].widget.position = i
    }

    return scored.map(\.widget)
}
```

**Urgency scoring function:**
```swift
private func urgencyScore(for type: WidgetType) -> Int {
    // Score 0–100: higher = more urgent = shows at top + larger

    switch type {
    case .activeIncidents:
        let count = vm.activeIncidents.count
        if count == 0 { return 5 }
        let hasP1 = vm.activeIncidents.contains { $0.isHighPriority }
        return hasP1 ? 100 : 70 + min(count * 5, 25)

    case .jsmOpsAlerts:
        let openAlerts = vm.jsmOpsAlerts.filter { $0.status.lowercased() == "open" && !$0.acknowledged }
        if openAlerts.isEmpty { return 10 }
        let hasP1 = openAlerts.contains { $0.priority == "P1" }
        let hasP2 = openAlerts.contains { $0.priority == "P2" }
        if hasP1 { return 95 }
        if hasP2 { return 75 }
        return 50 + min(openAlerts.count * 3, 20)

    case .grafanaAlerts:
        let count = vm.firingAlerts.count
        if count == 0 { return 8 }
        return 60 + min(count * 10, 30)

    case .myTickets:
        let count = vm.myTickets.count
        if count == 0 { return 5 }
        let overdueCount = vm.myTickets.filter { ticket in
            guard let due = ticket.fields?.duedate, !due.isEmpty else { return false }
            // Simple check: if duedate is in the past
            return due < ISO8601DateFormatter().string(from: Date()).prefix(10).description
        }.count
        if overdueCount > 0 { return 55 + min(overdueCount * 5, 20) }
        return 30 + min(count * 2, 15)

    case .jenkinsBuilds:
        let failedCount = vm.recentBuilds.filter { $0.build.result == "FAILURE" }.count
        if failedCount == 0 { return 8 }
        return 50 + min(failedCount * 10, 30)

    case .recentPRs:
        let count = vm.recentPRs.count
        if count == 0 { return 5 }
        return 20 + min(count * 3, 15)

    case .unreadEmails:
        let count = vm.unreadEmails.count
        if count == 0 { return 3 }
        return 15 + min(count, 15)

    case .upcomingCalendar:
        let count = vm.upcomingEvents.count
        if count == 0 { return 5 }
        // Check if there's a meeting in the next 30 minutes
        let now = Date()
        let soon = vm.upcomingEvents.contains { event in
            // Simple heuristic: check if event starts within 30 min
            true // Needs proper date comparison
        }
        return soon ? 35 : 15

    case .quickActions:
        return 20  // Always useful, mid-priority

    case .serviceHealth:
        // Higher if any services are disconnected
        let disconnected = [appState.jiraAuthStatus, appState.githubAuthStatus,
                           appState.jenkinsAuthStatus, appState.grafanaAuthStatus]
            .filter { !$0.isOK }.count
        if disconnected > 0 { return 40 + disconnected * 10 }
        return 5

    case .awsCostTrend:
        return 10  // Low urgency unless there's an anomaly

    case .confluenceRecent:
        return 5  // Informational

    case .aiDailySummary:
        return 15  // Useful context but not urgent
    }
}
```

### Phase 37D: Overall SRE Health Score

Add a visual "health meter" at the top of the dashboard that gamifies the SRE's work.

1. **Calculate an overall health score (0–100):**
   ```swift
   var overallHealthScore: Int {
       var score = 100  // Start perfect, deduct for issues

       // Active P1/P2 incidents: -30 each
       score -= vm.activeIncidents.filter(\.isHighPriority).count * 30

       // Open unacked JSM alerts: -5 each (P1: -15, P2: -10)
       for alert in vm.jsmOpsAlerts where alert.status == "open" && !alert.acknowledged {
           switch alert.priority {
           case "P1": score -= 15
           case "P2": score -= 10
           default: score -= 5
           }
       }

       // Grafana alerts firing: -10 each
       score -= vm.firingAlerts.count * 10

       // Failed Jenkins builds: -5 each
       score -= vm.recentBuilds.filter { $0.build.result == "FAILURE" }.count * 5

       // Overdue Jira tickets: -3 each
       // (simplified — would need date comparison)

       // Disconnected services: -5 each
       let statuses = [appState.jiraAuthStatus, appState.githubAuthStatus,
                       appState.jenkinsAuthStatus, appState.grafanaAuthStatus,
                       appState.confluenceAuthStatus, appState.bitbucketAuthStatus]
       score -= statuses.filter { !$0.isOK && $0 != .unknown && $0 != .notConfigured }.count * 5

       return max(0, min(100, score))
   }
   ```

2. **Display as a compact health bar** between the header and the widget grid:
   ```
   ┌─────────────────────────────────────────────┐
   │  🛡️ SRE Health: ████████████████░░░░ 82%    │
   │  2 open alerts · 1 failed build · 5 tickets │
   └─────────────────────────────────────────────┘
   ```

   - Color the bar: green (80-100), yellow (50-79), orange (25-49), red (0-24)
   - Show a one-line summary of what's affecting the score
   - The health score should motivate: "Get to 100!" — when the SRE resolves an alert, the score goes up immediately on refresh
   - Use a `Gauge` or `ProgressView` styled as a health bar

3. **Health score labels:**
   - 90-100: "Excellent — all systems go 🟢"
   - 75-89: "Good — a few items need attention 🟡"
   - 50-74: "Needs Attention — check the items below ⚠️"
   - 25-49: "Critical — multiple issues require action 🔴"
   - 0-24: "Emergency — immediate action required 🚨"

### Phase 37E: Upgrade the Customize Sheet

Improve the `DashboardCustomizeView`:

1. **Add drag-and-drop reordering** to the widget list in the customize sheet (not just on the dashboard). Users should be able to drag items in the list to reorder them.

2. **Show a preview** of the current health score and how it's calculated:
   ```
   Health Score: 82/100
   ─────────────────
   -15  JSM Ops: 3 open alerts (P2)
    -5  Jenkins: 1 failed build
    +2  Bonus: All services connected
   ```

3. **In Auto mode, show an explanation** of what the AI is doing:
   ```
   AI Dashboard Manager
   ─────────────────────
   Current priorities (sorted by urgency):
   1. 🔴 JSM Ops Alerts (urgency: 75) → Large
   2. 🟡 Jenkins Builds (urgency: 55) → Medium
   3. 🟢 My Tickets (urgency: 30) → Medium
   4. 🟢 Calendar (urgency: 15) → Small
   ...

   The AI promotes widgets with actionable items to the top
   and increases their size. Resolved items shrink and move down.
   ```

### Phase 37F: Time-Based Urgency Escalation

In Auto mode, widgets that have unresolved issues should **grow over time** if the SRE doesn't take action:

1. **Track when an issue was first detected:**
   Add `@Published var widgetFirstAlerted: [WidgetType: Date] = [:]` to `DashboardViewModel`.

   When a widget first gets a non-zero urgency score, record the timestamp. When it drops back to zero, clear it.

2. **Escalate urgency based on time:**
   In `urgencyScore()`, add a time multiplier:
   ```swift
   // If this widget has had issues for a while, escalate
   if let firstAlerted = vm.widgetFirstAlerted[type] {
       let minutesSinceAlert = Date().timeIntervalSince(firstAlerted) / 60
       if minutesSinceAlert > 60 {        // 1+ hour unresolved
           baseScore += 10
       }
       if minutesSinceAlert > 240 {       // 4+ hours unresolved
           baseScore += 15
       }
       if minutesSinceAlert > 480 {       // 8+ hours unresolved
           baseScore += 20                 // Widget is now screaming
       }
   }
   ```

3. **Visual escalation:** Widgets that have been unresolved for a long time should get a subtle pulsing border animation (accent color, slow pulse every 2 seconds). This creates visual urgency without being annoying.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break existing widgets — this is an enhancement, not a rewrite.
- The drag-and-drop should feel native and smooth — use SwiftUI's built-in drag APIs.
- The health score should update immediately when widget data changes (it's a computed property, not a stored value).
- In Custom mode, the user's manual ordering takes priority — no auto-sorting. In Auto mode, the AI manages everything.
- The gamification should be motivating, not stressful. The tone should be: "Nice work, you're at 95!" not "WARNING: 3 items unresolved."
- Persist widget order and sizes to `~/.boomi_sre_config.json` after any change.

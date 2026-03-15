# Boomi SRE App — Phase 36: Add JSM Ops Alerts to Home Page Dashboard

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/DashboardView.swift` — home page dashboard, widget rendering, `widgetView(for:)` switch
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching for all widgets, `firingAlerts` (currently Grafana only)
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `GrafanaAlertsWidget` (navigates to `grafana_browser` — WRONG)
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `WidgetType` enum (has `grafanaAlerts` but no JSM Ops alerts)
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — `listAlerts()` method (already works with Basic auth)
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — `OpsAlert` model

---

## Problems

1. The dashboard has a `grafanaAlerts` widget that shows Grafana alert rules. When clicked, it navigates to `grafana_browser`. The user wants JSM Ops alerts (Open, Unacknowledged, Assigned to Me) on the home page instead.

2. The alerts widget should navigate to the **On-Call** section (`oncall`), not Grafana.

---

## Implementation

### Phase 36A: Add `jsmOpsAlerts` Widget Type

In `WidgetModels.swift`, add a new widget type:

```swift
enum WidgetType: String, Codable, CaseIterable {
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts    // ← NEW
    case awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary
}
```

Add the display properties for the new type (icon, title, etc.) — wherever `WidgetType` has computed properties like `icon`, `title`, `displayName`, add the `jsmOpsAlerts` case:
- Title: "JSM Ops Alerts"
- Icon: `"bell.badge"` (or `"bell.badge.fill"`)
- Description: "Open and unacknowledged alerts from JSM Operations"

### Phase 36B: Fetch JSM Ops Alerts in DashboardViewModel

Add JSM Ops alert fetching to `DashboardViewModel`:

1. **Add published property:**
   ```swift
   @Published var jsmOpsAlerts: [OpsAlert] = []
   ```

2. **Add a JSMOpsService instance:**
   ```swift
   private let jsmOpsService = JSMOpsService()
   ```

3. **Add a load method:**
   ```swift
   private func loadJSMOpsAlerts(appState: AppState) async {
       guard appState.isJiraConfigured else { return }
       do {
           let allAlerts = try await jsmOpsService.listAlerts(
               baseURL: appState.jiraBaseURL,
               email: appState.jiraEmail,
               apiToken: appState.jiraAPIToken,
               limit: 50
           )
           // Show open, unacknowledged, or assigned to current user
           let userEmail = appState.jiraEmail.lowercased()
           jsmOpsAlerts = allAlerts.filter { alert in
               let isOpen = alert.status.lowercased() == "open"
               let isAcked = alert.status.lowercased() == "acked"
               let isUnacked = isOpen && !alert.acknowledged
               let isAssignedToMe = !alert.owner.isEmpty && alert.owner.lowercased() == userEmail
               return isOpen || isUnacked || isAssignedToMe || (isAcked && isAssignedToMe)
           }
       } catch {
           loadErrors.append("JSM Ops Alerts: \(error.localizedDescription)")
       }
   }
   ```

4. **Call it in `refreshAll()`** alongside the other widget data fetchers:
   ```swift
   group.addTask { await self.loadJSMOpsAlerts(appState: appState) }
   ```

5. **Add `jsmOpsAlerts` to the widget filter** in `DashboardView` — the widget should show if Jira is configured:
   ```swift
   case .jsmOpsAlerts: return appState.isJiraConfigured
   ```

### Phase 36C: Create JSM Ops Alerts Widget View

Add a new widget in `WidgetViews.swift`:

```swift
// MARK: - JSM Ops Alerts Widget

struct JSMOpsAlertsWidget: View {
    let alerts: [OpsAlert]
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .jsmOpsAlerts, navigateTo: "oncall") {   // ← navigates to On-Call
            if alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(appState.isJiraConfigured ? "No active alerts" : "Configure Jira in Settings")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    // Summary counts
                    let openCount = alerts.filter { $0.status.lowercased() == "open" && !$0.acknowledged }.count
                    let ackedCount = alerts.filter { $0.acknowledged }.count
                    let assignedCount = alerts.filter { !$0.owner.isEmpty && $0.owner.lowercased() == appState.jiraEmail.lowercased() }.count

                    HStack(spacing: 12) {
                        if openCount > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("\(openCount) open").font(.callout.bold()).foregroundStyle(.red)
                            }
                        }
                        if ackedCount > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(.orange).frame(width: 8, height: 8)
                                Text("\(ackedCount) acked").font(.callout.bold()).foregroundStyle(.orange)
                            }
                        }
                        if assignedCount > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(.blue).frame(width: 8, height: 8)
                                Text("\(assignedCount) mine").font(.callout.bold()).foregroundStyle(.blue)
                            }
                        }
                    }

                    // Show the most critical alerts (up to 5)
                    ForEach(alerts.prefix(5)) { alert in
                        HStack(spacing: 6) {
                            Text(alert.priority)
                                .font(.caption2.bold())
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Capsule().fill(alertPriorityColor(alert.priority).opacity(0.15)))
                                .foregroundStyle(alertPriorityColor(alert.priority))
                            Text(alert.message)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(alert.source)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if alerts.count > 5 {
                        Text("+ \(alerts.count - 5) more")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func alertPriorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .yellow
        case "P4": return .blue
        default:   return .secondary
        }
    }
}
```

### Phase 36D: Wire the New Widget into DashboardView

In `DashboardView.swift`:

1. **Add the widget rendering** in the `widgetView(for:)` switch:
   ```swift
   case .jsmOpsAlerts:
       JSMOpsAlertsWidget(alerts: vm.jsmOpsAlerts).environmentObject(appState)
   ```

2. **Add `jsmOpsAlerts` to the default widget set** (so it appears for new users or in "auto" mode). Place it near the top — active alerts are high priority:
   - Position it right after `activeIncidents` and before `myTickets` in the default widget order

3. **Keep the existing `grafanaAlerts` widget** — it shows Grafana-specific alert rules and is still useful. But fix its navigation to go to `grafana_browser` (that's correct for Grafana alerts). The new `jsmOpsAlerts` widget is separate and goes to `oncall`.

### Phase 36E: Sort Alerts by Priority

In the `loadJSMOpsAlerts()` method and in the widget, sort alerts so the most critical appear first:

```swift
jsmOpsAlerts = filteredAlerts.sorted { a, b in
    let priorityOrder = ["P1": 0, "P2": 1, "P3": 2, "P4": 3, "P5": 4]
    let pa = priorityOrder[a.priority] ?? 5
    let pb = priorityOrder[b.priority] ?? 5
    if pa != pb { return pa < pb }
    return a.createdAt > b.createdAt  // newer first within same priority
}
```

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break existing dashboard widgets — the Grafana alerts widget stays, the new JSM Ops alerts widget is additive.
- The JSM Ops alerts widget should use the **same** accent orange color scheme as the On-Call section for visual consistency.
- The widget card background should tint red if there are any P1 alerts, orange for P2, or neutral for P3+.

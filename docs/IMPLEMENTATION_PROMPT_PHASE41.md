# Boomi SRE App — Phase 41: Fix Dashboard — Missing Widgets, Auto Mode & Customize UX

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `WidgetType` enum (has 15 types), `DashboardWidget.defaults` (has 15 entries)
- `BoomiSRE/Sources/Models/AppState.swift` — `dashboardWidgets` property, `loadConfig()`, `saveConfig()`
- `BoomiSRE/Sources/Views/DashboardView.swift` — dashboard layout, `enabledWidgets`, `autoWidgets()`, `DashboardCustomizeView`
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching for all widgets

---

## Root Causes

### Problem 1: New widgets don't appear because they're not in the user's saved config

The `DashboardWidget.defaults` now has 15 widget types, but the user's `~/.boomi_sre_config.json` was saved with only 9 widgets (from an older version). When `loadConfig()` loads the saved widgets, it uses those 9 — the 6 new widgets (`jsmOpsAlerts`, `notifications`, `onCallSchedule`, `unreadEmails`, `confluenceRecent`, `awsCostTrend`) are never added.

**Current saved config:**
```
aiDailySummary, activeIncidents, serviceHealth, grafanaAlerts,
upcomingCalendar, myTickets, jenkinsBuilds, recentPRs, quickActions
```

**Missing from saved config:**
```
jsmOpsAlerts, notifications, onCallSchedule, unreadEmails, confluenceRecent, awsCostTrend
```

### Problem 2: Auto mode uses the user's widget list (which is incomplete)

`autoWidgets(from:)` takes `from widgets` which is `appState.dashboardWidgets.filter(\.isEnabled)` — if the user disabled all widgets, Auto mode has nothing to work with. Auto mode should generate its own complete widget list from ALL available types, ignoring the user's custom configuration entirely.

### Problem 3: Customize popup is too small

The sheet uses `.frame(minWidth: 480, minHeight: 520)` which cuts off the widget list and requires scrolling. With 15 widgets, it needs more space.

---

## Implementation

### Phase 41A: Auto-Migrate Saved Widget Config

In `AppState`, after loading `dashboardWidgets` from config, check for missing widget types and add them:

```swift
// In loadConfig(), after loading dashboardWidgets:
if let savedWidgets = config.dashboardWidgets {
    dashboardWidgets = savedWidgets
} else {
    dashboardWidgets = DashboardWidget.defaults
}

// Always ensure all widget types are present (handles upgrades)
let existingTypes = Set(dashboardWidgets.map(\.type))
let maxPosition = dashboardWidgets.map(\.position).max() ?? -1
var nextPosition = maxPosition + 1
for defaultWidget in DashboardWidget.defaults {
    if !existingTypes.contains(defaultWidget.type) {
        var newWidget = defaultWidget
        newWidget.position = nextPosition
        newWidget.isEnabled = true   // new widgets start enabled
        dashboardWidgets.append(newWidget)
        nextPosition += 1
    }
}
```

This ensures that every time the app launches, any new widget types added in code updates are automatically added to the user's widget list. Existing widget settings (enabled/disabled, size, position) are preserved.

### Phase 41B: Rewrite Auto Mode — Completely Independent from User Config

Auto mode should NOT read from the user's custom widget list. It should build its own widget set from scratch based on real-time data.

**Rewrite `autoWidgets()` in `DashboardView`:**

```swift
private func autoWidgets(from _: [DashboardWidget]) -> [DashboardWidget] {
    // Auto mode builds its own list from ALL widget types — ignores user's custom config
    let allTypes = WidgetType.allCases

    // Filter out unconfigured services
    let configuredTypes = allTypes.filter { type in
        switch type {
        case .recentPRs: return !appState.githubToken.isEmpty
        case .jenkinsBuilds: return !appState.jenkinsToken.isEmpty
        case .grafanaAlerts: return !appState.grafanaToken.isEmpty
        case .jsmOpsAlerts: return appState.isJiraConfigured
        case .awsCostTrend: return !appState.awsSSOProfile.isEmpty
        case .upcomingCalendar, .unreadEmails: return appState.googleCredentials != nil
        case .confluenceRecent: return !appState.confluenceAPIToken.isEmpty
        case .myTickets, .activeIncidents: return appState.isJiraConfigured
        case .onCallSchedule: return appState.isJiraConfigured && !appState.favoriteJSMTeams.isEmpty
        case .notifications: return true
        default: return true
        }
    }

    // Score each type by urgency
    var scored: [(type: WidgetType, urgency: Int)] = configuredTypes.map { type in
        (type, urgencyScore(for: type))
    }

    // Sort by urgency (highest first)
    scored.sort { $0.urgency > $1.urgency }

    // Assign sizes based on urgency AND whether widget has data
    return scored.enumerated().map { idx, pair in
        var size: WidgetSize
        let hasData = widgetHasData(pair.type)

        if !hasData {
            size = .small   // Never show empty widget as large
        } else if pair.urgency >= 80 {
            size = .large
        } else if pair.urgency >= 40 {
            size = .medium
        } else if pair.urgency >= 15 {
            size = .small
        } else {
            size = .small
        }

        // Special: if everything is green (health score 100), make AI Summary large at top
        // and Quick Actions medium — celebrate the clean state
        if pair.type == .aiDailySummary && overallHealthScore >= 95 {
            size = .large
        }

        return DashboardWidget(type: pair.type, position: idx, size: size, isEnabled: true)
    }
}

private func widgetHasData(_ type: WidgetType) -> Bool {
    switch type {
    case .activeIncidents: return !vm.activeIncidents.isEmpty
    case .jsmOpsAlerts:    return !vm.jsmOpsAlerts.isEmpty
    case .grafanaAlerts:   return !vm.firingAlerts.isEmpty
    case .myTickets:       return !vm.myTickets.isEmpty
    case .jenkinsBuilds:   return !vm.recentBuilds.isEmpty
    case .recentPRs:       return !vm.recentPRs.isEmpty
    case .upcomingCalendar: return !vm.upcomingEvents.isEmpty
    case .unreadEmails:    return !vm.unreadEmails.isEmpty
    case .notifications:   return !vm.recentNotifications.isEmpty
    case .onCallSchedule:  return !vm.onCallSchedules.isEmpty
    case .confluenceRecent: return false  // stub — no data yet
    case .awsCostTrend:    return false   // stub — no data yet
    default: return true
    }
}
```

**Key Auto mode behaviors:**
- Uses ALL widget types from `WidgetType.allCases` — not the user's saved list
- Filters out unconfigured services
- Sorts by urgency (P1 alerts at top, empty widgets at bottom)
- Assigns sizes dynamically: urgent = large, action needed = medium, informational = small
- Empty widgets always get small (never an empty large card)
- When health score is 95+, promotes AI Summary to large at the top (celebrate the clean state)

### Phase 41C: Fix the Customize Dashboard Popup

The popup is too small and requires scrolling to see all widgets. Fix:

1. **Increase the sheet size** — change the frame in `DashboardView`:
   ```swift
   .sheet(isPresented: $showCustomize) {
       DashboardCustomizeView()
           .environmentObject(appState)
           .frame(minWidth: 540, minHeight: 700, maxHeight: 900)
   }
   ```

2. **In `DashboardCustomizeView`, use the full height efficiently:**
   - The mode picker and explanation at the top should be compact
   - The widget list should use a `List` with enough room to show all 15 widgets without scrolling (each row is ~44pt, 15 × 44 = 660pt)
   - If the window is tall enough, don't scroll — show everything

3. **In Auto mode, show what the AI is doing:**
   Instead of just "AI automatically selects and prioritizes widgets...", show a live preview:
   ```
   Auto mode is active. Widgets are sorted by urgency:

   🔴 JSM Ops Alerts — 2 unacked P2 alerts → Large
   🟡 Active Incidents — 1 active P3 → Medium
   🟡 Jenkins Builds — 1 failure → Medium
   🟢 My Tickets — 8 tickets, none overdue → Small
   🟢 On-Call — 3 schedules → Small
   🟢 Notifications — 2 unread → Small
   🟢 Calendar — next in 2h → Small
   ⚪ Email — 0 unread → Small
   ⚪ Service Health — all connected → Small
   ```
   Each line shows the icon, name, WHY it's ranked where it is (the data summary), and the assigned size. This makes the AI feel transparent and obviously intelligent.

4. **In Custom mode, show ALL 15 widgets** (including new ones that were added via Phase 41A migration). The list should be sorted by position. Each row has:
   - Drag handle (left)
   - Icon
   - Widget name
   - Enable/disable toggle
   - S/M/L size picker
   - A tiny count badge showing how many items the widget currently has (e.g., "3" for 3 alerts)

### Phase 41D: Also Update `enabledWidgets` in DashboardView

The current `enabledWidgets` computed property:
```swift
var enabledWidgets: [DashboardWidget] {
    let widgets = appState.dashboardWidgets.filter(\.isEnabled)
        .sorted { $0.position < $1.position }
    if appState.dashboardMode == "auto" {
        return autoWidgets(from: widgets)
    }
    return widgets
}
```

For Auto mode, change to pass nothing (Auto builds its own list):
```swift
var enabledWidgets: [DashboardWidget] {
    if appState.dashboardMode == "auto" {
        return autoWidgets()   // Auto mode builds from scratch
    }
    return appState.dashboardWidgets
        .filter(\.isEnabled)
        .sorted { $0.position < $1.position }
}
```

Update `autoWidgets()` signature to take no arguments.

### Phase 41E: Verify All Widget Views Exist

Check that `widgetView(for:)` in `DashboardView` has a case for ALL 15 widget types. If any are missing, add them. Even if the widget just shows "Coming soon" placeholder text, it must not crash.

Specifically verify these exist:
- `case .jsmOpsAlerts:` → `JSMOpsAlertsWidget`
- `case .notifications:` → `NotificationsWidget`
- `case .onCallSchedule:` → `OnCallWidget`
- `case .unreadEmails:` → `EmailWidget`
- `case .confluenceRecent:` → placeholder
- `case .awsCostTrend:` → placeholder

If `NotificationsWidget` or `OnCallWidget` views don't exist yet, create them with basic S/M/L rendering:

**NotificationsWidget (if missing):**
- Small: unread count
- Medium: unread count + last 4 notifications (title only)
- Large: last 8 notifications with type icon, title, and body preview

**OnCallWidget (if missing):**
- Small: number of active schedules
- Medium: favorite team schedules with primary on-call person name
- Large: all favorite schedules with all participants

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- The Auto mode fix (41B) is the highest priority — it should work independently from the user's saved widget config.
- The migration (41A) ensures existing users get the new widgets without losing their customizations.
- The customize popup (41C) should feel polished and professional — no scrolling if possible, clean layout.
- After all changes, the user should see ALL widgets on the home page in Auto mode, intelligently sorted and sized based on real-time data.

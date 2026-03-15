# Boomi SRE App — Phase 40: Dashboard Overhaul — More Widgets, Filters & User Control

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `WidgetType` enum, `DashboardWidget`, defaults list
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching for all widgets (NOTE: `activeIncidents` is never populated, `loadIncidents` is missing)
- `BoomiSRE/Sources/Views/DashboardView.swift` — dashboard layout, widget rendering, health score, auto mode
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — all individual widget views
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — on-call data loading (schedules, participants)
- `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift` — Jira incident loading
- `BoomiSRE/Sources/ViewModels/NotificationViewModel.swift` — notification data

---

## Problems

1. **Missing widget types:** No widgets for Notifications, On-Call Schedules, or Incidents from Jira. The `activeIncidents` widget exists but its data is never loaded (no `loadIncidents()` in DashboardViewModel).

2. **No filtering within widgets:** The user can't filter what each widget shows. For example, JSM Ops Alerts shows everything — the user should be able to filter by team, priority, or status directly on the widget.

3. **Several declared widgets are stubs:** `awsCostTrend` and `confluenceRecent` show placeholder text, not real data.

4. **Defaults list is incomplete:** Missing `unreadEmails`, `confluenceRecent`, `awsCostTrend` from the defaults.

---

## Implementation

### Phase 40A: Add New Widget Types

Add these new widget types to the `WidgetType` enum in `WidgetModels.swift`:

```swift
enum WidgetType: String, Codable, CaseIterable {
    // Existing
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts, awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary
    // NEW
    case notifications      // Recent notifications from the notification system
    case onCallSchedule     // Who's currently on call
}
```

Add `title` and `icon` for the new types:
- `notifications`: title "Notifications", icon "bell.fill"
- `onCallSchedule`: title "On-Call", icon "phone.badge.waveform"

Update `DashboardWidget.defaults` to include ALL widget types in a sensible order:
```swift
static var defaults: [DashboardWidget] {
    [
        DashboardWidget(type: .serviceHealth,    position: 0,  size: .small),
        DashboardWidget(type: .quickActions,     position: 1,  size: .small),
        DashboardWidget(type: .activeIncidents,  position: 2,  size: .medium),
        DashboardWidget(type: .jsmOpsAlerts,     position: 3,  size: .medium),
        DashboardWidget(type: .grafanaAlerts,    position: 4,  size: .medium),
        DashboardWidget(type: .onCallSchedule,   position: 5,  size: .medium),
        DashboardWidget(type: .notifications,    position: 6,  size: .medium),
        DashboardWidget(type: .myTickets,        position: 7,  size: .medium),
        DashboardWidget(type: .jenkinsBuilds,    position: 8,  size: .medium),
        DashboardWidget(type: .recentPRs,        position: 9,  size: .medium),
        DashboardWidget(type: .upcomingCalendar, position: 10, size: .medium),
        DashboardWidget(type: .unreadEmails,     position: 11, size: .small),
        DashboardWidget(type: .awsCostTrend,     position: 12, size: .small),
        DashboardWidget(type: .confluenceRecent, position: 13, size: .small),
        DashboardWidget(type: .aiDailySummary,   position: 14, size: .large),
    ]
}
```

### Phase 40B: Load Missing Data in DashboardViewModel

**Fix `activeIncidents` — it's never populated:**

Add incident loading. Since incidents now come from Jira (Phase 14), fetch them using the configured incident JQL:

```swift
@Published var activeIncidents: [Incident] = []  // already exists but never populated
@Published var onCallParticipants: [String: [OnCallParticipant]] = [:]  // scheduleId -> participants
@Published var onCallSchedules: [OpsSchedule] = []
@Published var recentNotifications: [SRENotification] = []

private let incidentService = JiraService()  // for incident JQL
private let onCallService = JSMOpsService()
```

Add these load methods:

```swift
private func loadIncidents(appState: AppState) async {
    guard appState.isJiraConfigured else { return }
    do {
        // Use the incident JQL from settings, or a default
        let jql = appState.incidentJQL.isEmpty
            ? "project = \"Boomi Incident Management\" AND statusCategory NOT IN (Done) ORDER BY created DESC"
            : appState.incidentJQL
        let result = try await incidentService.searchIssues(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken,
            jql: jql, fields: ["summary", "status", "priority", "created", "assignee"], maxResults: 10)
        // Map to Incident model (simplified — just need key, title, severity, status)
        activeIncidents = result.issues.compactMap { issue in
            let severity: IncidentSeverity = {
                switch issue.fields.priority?.name?.lowercased() ?? "" {
                case "highest", "blocker": return .p1
                case "high", "critical": return .p2
                case "medium": return .p3
                default: return .p4
                }
            }()
            let status: IncidentStatus = {
                switch issue.fields.status?.statusCategory?.key ?? "" {
                case "done": return .resolved
                case "indeterminate": return .identified
                default: return .investigating
                }
            }()
            return Incident(title: issue.fields.summary ?? issue.key,
                           severity: severity, status: status,
                           jiraTicketKey: issue.key)
        }
    } catch {
        loadErrors.append("Incidents: \(error.localizedDescription)")
    }
}

private func loadOnCall(appState: AppState) async {
    guard appState.isJiraConfigured else { return }
    do {
        onCallSchedules = try await onCallService.listSchedules(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken)
        // Load on-call for favorite teams' schedules
        for teamId in appState.favoriteJSMTeams {
            let teamSchedules = onCallSchedules.filter { $0.teamId == teamId }
            for schedule in teamSchedules {
                let participants = try await onCallService.getOnCall(
                    baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken, scheduleId: schedule.id)
                onCallParticipants[schedule.id] = participants
            }
        }
    } catch {
        loadErrors.append("On-Call: \(error.localizedDescription)")
    }
}

private func loadNotifications(notificationVM: NotificationViewModel) {
    // Get the most recent notifications (this data is already in NotificationViewModel)
    recentNotifications = Array(notificationVM.notifications.prefix(10))
}
```

**Add these to `refreshAll()`:**
```swift
if jiraOK {
    group.addTask { await self.loadJiraTickets(appState: appState) }
    group.addTask { await self.loadJSMOpsAlerts(appState: appState) }
    group.addTask { await self.loadIncidents(appState: appState) }    // NEW
    group.addTask { await self.loadOnCall(appState: appState) }        // NEW
}
```

For notifications, pass the `NotificationViewModel` to `refreshAll()`:
```swift
func refreshAll(appState: AppState, notificationVM: NotificationViewModel? = nil) async {
    // ... existing code ...
    if let nvm = notificationVM {
        loadNotifications(notificationVM: nvm)
    }
}
```

Update the call site in `DashboardView.onAppear` and the refresh button to pass `notificationVM`.

### Phase 40C: Create Widget Views for New Types

#### Notifications Widget
```swift
struct NotificationsWidget: View {
    let notifications: [SRENotification]
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .notifications, size: size, navigateTo: "notifications") {
            switch size {
            case .small:
                // Count + unread badge
                HStack {
                    let unread = notifications.filter { !$0.isRead }.count
                    Text("\(unread)").font(.title2.bold()).foregroundStyle(unread > 0 ? .red : .green)
                    Text("unread").font(.caption).foregroundStyle(.secondary)
                }
            case .medium:
                // Unread count + last 4 notifications
                VStack(alignment: .leading, spacing: 6) {
                    let unread = notifications.filter { !$0.isRead }.count
                    if unread > 0 {
                        Text("\(unread) unread").font(.callout.bold()).foregroundStyle(.red)
                    }
                    ForEach(notifications.prefix(4)) { n in
                        HStack(spacing: 6) {
                            if !n.isRead { Circle().fill(.blue).frame(width: 6, height: 6) }
                            Image(systemName: n.type.icon).font(.caption2).foregroundStyle(n.type.color)
                            Text(n.title).font(.caption).lineLimit(1)
                        }
                    }
                }
            case .large:
                // Full notification list with more detail
                VStack(alignment: .leading, spacing: 6) {
                    let unread = notifications.filter { !$0.isRead }.count
                    Text("\(notifications.count) recent · \(unread) unread").font(.callout.bold())
                    ForEach(notifications.prefix(8)) { n in
                        HStack(spacing: 6) {
                            if !n.isRead { Circle().fill(.blue).frame(width: 6, height: 6) }
                            Image(systemName: n.type.icon).font(.caption2).foregroundStyle(n.type.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.title).font(.caption).lineLimit(1)
                                Text(n.body).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
```

#### On-Call Widget
```swift
struct OnCallWidget: View {
    let schedules: [OpsSchedule]
    let participants: [String: [OnCallParticipant]]
    let displayNames: [String: String]  // accountId -> name
    let size: WidgetSize
    @EnvironmentObject var appState: AppState

    var body: some View {
        WidgetCard(type: .onCallSchedule, size: size, navigateTo: "oncall") {
            let favSchedules = schedules.filter { s in
                appState.favoriteJSMTeams.contains(s.teamId ?? "")
            }
            switch size {
            case .small:
                // Just "3 schedules active"
                HStack {
                    Text("\(favSchedules.count)").font(.title2.bold())
                    Text("on-call schedules").font(.caption).foregroundStyle(.secondary)
                }
            case .medium:
                // Schedule names with primary on-call person
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(favSchedules.prefix(4)) { schedule in
                        let people = participants[schedule.id] ?? []
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill").font(.caption2).foregroundStyle(.accentColor)
                            Text(schedule.name).font(.caption).lineLimit(1)
                            Spacer()
                            if let primary = people.first {
                                Text(displayNames[primary.name] ?? primary.name)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            case .large:
                // Full schedule detail with all participants
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(favSchedules.prefix(6)) { schedule in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(schedule.name).font(.caption.bold())
                            let people = participants[schedule.id] ?? []
                            if people.isEmpty {
                                Text("No one on call").font(.caption2).foregroundStyle(.tertiary)
                            } else {
                                ForEach(Array(people.enumerated()), id: \.offset) { i, p in
                                    HStack(spacing: 6) {
                                        Image(systemName: i == 0 ? "person.fill" : "person")
                                            .font(.caption2)
                                            .foregroundStyle(i == 0 ? .accentColor : .secondary)
                                        Text(displayNames[p.name] ?? p.name).font(.caption)
                                        if i == 0 { Text("Primary").font(.caption2).foregroundStyle(.accentColor) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Phase 40D: Wire New Widgets into DashboardView

In `widgetView(for:)` in `DashboardView.swift`, add cases for the new widget types:

```swift
case .notifications:
    NotificationsWidget(notifications: vm.recentNotifications, size: widget.size)
        .environmentObject(appState)
case .onCallSchedule:
    OnCallWidget(schedules: vm.onCallSchedules,
                 participants: vm.onCallParticipants,
                 displayNames: vm.onCallDisplayNames,
                 size: widget.size)
        .environmentObject(appState)
```

Also fix the `widgetIsConfigured()` check:
```swift
case .notifications: return true  // notifications are always available
case .onCallSchedule: return appState.isJiraConfigured && !appState.favoriteJSMTeams.isEmpty
```

Add these to the urgency scoring:
```swift
case .notifications:
    let unread = vm.recentNotifications.filter { !$0.isRead }.count
    let highPri = vm.recentNotifications.filter { !$0.isRead && $0.type.isHighPriority }.count
    if highPri > 0 { base = 60 + min(highPri * 10, 20) }
    else if unread > 0 { base = 20 + min(unread * 2, 15) }
    else { base = 5 }

case .onCallSchedule:
    base = 25  // always useful context, moderate priority
```

### Phase 40E: Add Per-Widget Filtering

**Goal:** Each widget should have a small filter control that lets the user narrow what's shown without leaving the home page.

1. **Add a `widgetFilters` dictionary to AppState** (persisted):
   ```swift
   @Published var widgetFilters: [String: [String: String]] = [:]
   // Key: widget type raw value
   // Value: dictionary of filter key -> filter value
   // Example: ["jsmOpsAlerts": ["priority": "P1,P2", "team": "CAM SRE"]]
   ```

2. **Add a filter popover to `WidgetCard`:**
   On each widget card header, add a small filter icon (funnel) that shows a popover when clicked:
   ```swift
   // In WidgetCard header, next to the chevron:
   if type.hasFilters {
       Button {
           showFilterPopover.toggle()
       } label: {
           Image(systemName: "line.3.horizontal.decrease")
               .font(.caption2)
               .foregroundStyle(hasActiveFilters ? .accentColor : .tertiary)
       }
       .buttonStyle(.plain)
       .popover(isPresented: $showFilterPopover) {
           widgetFilterContent(for: type)
               .padding(12)
               .frame(width: 250)
       }
   }
   ```

3. **Per-widget filter options:**

   | Widget | Filter Options |
   |--------|---------------|
   | **JSM Ops Alerts** | Priority (P1/P2/P3/P4/P5 toggles), Status (Open/Acked/Closed), Team |
   | **Grafana Alerts** | State (Alerting/Pending/Normal) |
   | **My Tickets** | Priority, Status (To Do/In Progress), Project |
   | **Jenkins Builds** | Result (Success/Failure/Unstable), Job name pattern |
   | **Recent PRs** | State (Open/Merged/Closed), Repo |
   | **Notifications** | Type (Jira/Jenkins/Grafana/GitHub), Read/Unread |
   | **Active Incidents** | Severity (P1/P2/P3/P4), Status |
   | **On-Call** | Team (from favorites) |

4. **Apply filters in the widget views:**
   Each widget reads its filters from `appState.widgetFilters[type.rawValue]` and filters the data before rendering. For example:
   ```swift
   var filteredAlerts: [OpsAlert] {
       let filters = appState.widgetFilters["jsmOpsAlerts"] ?? [:]
       var result = alerts
       if let priorities = filters["priority"], !priorities.isEmpty {
           let allowed = Set(priorities.split(separator: ",").map(String.init))
           result = result.filter { allowed.contains($0.priority) }
       }
       if let status = filters["status"], !status.isEmpty {
           result = result.filter { $0.status.lowercased() == status.lowercased() }
       }
       return result
   }
   ```

5. **Show a filter badge** on the widget header when filters are active — a small colored dot next to the funnel icon, or the funnel icon turns accent-colored.

6. **"Reset Filters" button** in the filter popover to clear all filters for that widget.

### Phase 40F: Resolve On-Call Display Names in DashboardViewModel

The On-Call widget needs display names for participant accountIds. Add:

```swift
@Published var onCallDisplayNames: [String: String] = [:]

// After loading on-call participants, resolve names:
for (_, participants) in onCallParticipants {
    for p in participants where onCallDisplayNames[p.name] == nil {
        if let name = try? await onCallService.resolveDisplayName(
            accountId: p.name,
            baseURL: appState.jiraBaseURL,
            email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken) {
            onCallDisplayNames[p.name] = name
        }
    }
}
```

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break existing widgets — only add new ones and enhance existing.
- The filter system should be lightweight — simple key-value pairs, not complex query builders.
- Widgets with no data should show a clean empty state appropriate to their size (Small: just "0", Medium: "No items", Large: helpful message with action link).
- All new widgets must support all 3 sizes (S/M/L) with meaningfully different content at each size.

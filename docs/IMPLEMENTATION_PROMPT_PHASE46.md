# Boomi SRE App — Phase 46: Intelligent Feed (Home Page v2)

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. This is Phase B of the v2 evolution (see `docs/VISION_V2.md`).

**Read these files first:**
- `docs/VISION_V2.md` — the full vision document, especially the "Intelligent Feed" section and the mockup
- `BoomiSRE/Sources/Views/DashboardView.swift` — current home page (widget grid to be replaced)
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — data fetching for all sources
- `BoomiSRE/Sources/Models/WidgetModels.swift` — current widget model (will be supplemented, not removed)
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — current widget views
- `BoomiSRE/Sources/Models/AppState.swift` — `selectedProductId`, `selectedProduct`, `dashboardMode`
- `BoomiSRE/Sources/Models/ProductContext.swift` — product filter patterns (from Phase 45)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — on-call data model
- `BoomiSRE/Sources/ViewModels/NotificationViewModel.swift` — notification data
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI analysis

---

## Goal

Replace the widget grid home page with a **single intelligent feed** — a prioritized, AI-enriched, actionable stream of everything the SRE needs to know. The SRE opens the app, sees what needs attention, takes action inline, and moves on.

The feed combines data from ALL sources (JSM Ops alerts, Grafana alerts, Jira tickets, GitHub PRs, Jenkins builds, on-call status, notifications, incidents) into a single sorted stream. Each item has the AI's analysis and action buttons inline — no clicking into separate sections.

**Important:** Keep the existing widget grid as an option. The user should be able to choose between "Feed" mode (new) and "Widgets" mode (existing) in the Customize popup. The feed is the new default.

---

## Implementation

### Phase 46A: Define the Feed Item Model

Create `BoomiSRE/Sources/Models/FeedItem.swift`:

```swift
import Foundation
import SwiftUI

struct FeedItem: Identifiable {
    let id: String                    // unique ID (source + sourceId)
    let source: FeedSource
    let priority: FeedPriority
    let title: String
    let subtitle: String              // secondary info line
    let detail: String                // longer description or AI analysis
    let timestamp: Date
    let actions: [FeedAction]         // inline action buttons
    let navigateTo: String?           // sidebar section ID to navigate to for "View all"
    let metadata: [String: String]    // source-specific data (alertId, ticketKey, prNumber, etc.)

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

enum FeedSource: String {
    case jsmAlert = "JSM Alert"
    case grafanaAlert = "Grafana Alert"
    case incident = "Incident"
    case jiraTicket = "Jira"
    case githubPR = "GitHub PR"
    case jenkinsBuild = "Jenkins"
    case onCall = "On-Call"
    case notification = "Notification"
    case aiSummary = "AI Summary"

    var icon: String {
        switch self {
        case .jsmAlert:      return "bell.badge.fill"
        case .grafanaAlert:  return "bell.badge"
        case .incident:      return "exclamationmark.shield"
        case .jiraTicket:    return "checklist"
        case .githubPR:      return "arrow.triangle.pull"
        case .jenkinsBuild:  return "hammer"
        case .onCall:        return "phone.badge.waveform"
        case .notification:  return "bell.fill"
        case .aiSummary:     return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .jsmAlert, .grafanaAlert: return .red
        case .incident:      return .red
        case .jiraTicket:    return .blue
        case .githubPR:      return .purple
        case .jenkinsBuild:  return .orange
        case .onCall:        return .green
        case .notification:  return .secondary
        case .aiSummary:     return .accentColor
        }
    }
}

enum FeedPriority: Int, Comparable {
    case critical = 0     // P1 alerts, P1 incidents — need immediate action
    case high = 1         // P2 alerts, failed builds, unacked alerts
    case medium = 2       // assigned tickets, PR reviews, P3 alerts
    case low = 3          // informational — on-call status, calendar, all-clear messages
    case info = 4         // AI summary, MOTD, service health

    static func < (lhs: FeedPriority, rhs: FeedPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct FeedAction: Identifiable {
    let id: String
    let label: String
    let icon: String
    let style: ActionStyle
    let action: () async -> Void

    enum ActionStyle {
        case primary      // prominent button (e.g., ACK)
        case secondary    // bordered button (e.g., View)
        case destructive  // red button (e.g., Close)
    }
}
```

### Phase 46B: Build Feed Items from Existing Data

Add a method to `DashboardViewModel` that converts all the existing data into a sorted feed:

```swift
/// Build a unified feed from all data sources, sorted by priority then timestamp.
func buildFeed(appState: AppState) -> [FeedItem] {
    var items: [FeedItem] = []

    // JSM Ops Alerts → feed items
    for alert in jsmOpsAlerts {
        let priority: FeedPriority = {
            if alert.priority == "P1" { return .critical }
            if alert.priority == "P2" || (alert.status == "open" && !alert.acknowledged) { return .high }
            return .medium
        }()
        items.append(FeedItem(
            id: "jsm-\(alert.id)",
            source: .jsmAlert,
            priority: priority,
            title: alert.message,
            subtitle: "\(alert.priority) · \(alert.source) · \(alert.status.capitalized)",
            detail: "",  // AI will enrich this in Phase 46E
            timestamp: parseISO8601(alert.createdAt) ?? Date(),
            actions: buildAlertActions(alert, appState: appState),
            navigateTo: "oncall",
            metadata: ["alertId": alert.id, "priority": alert.priority, "status": alert.status]
        ))
    }

    // Grafana Alerts → feed items
    for alert in firingAlerts {
        items.append(FeedItem(
            id: "grafana-\(alert.uid)",
            source: .grafanaAlert,
            priority: .high,
            title: alert.title,
            subtitle: "Grafana · \(alert.state)",
            detail: alert.summary,
            timestamp: Date(),  // Grafana alerts don't always have timestamps
            actions: [
                FeedAction(id: "view-grafana-\(alert.uid)", label: "View in Grafana",
                          icon: "safari", style: .secondary) { /* navigate */ }
            ],
            navigateTo: "grafana_browser",
            metadata: ["uid": alert.uid]
        ))
    }

    // Active Incidents → feed items
    for incident in activeIncidents {
        let priority: FeedPriority = incident.severity == .p1 ? .critical : incident.severity == .p2 ? .high : .medium
        items.append(FeedItem(
            id: "incident-\(incident.id)",
            source: .incident,
            priority: priority,
            title: "[\(incident.severity.label)] \(incident.title)",
            subtitle: "\(incident.status.rawValue) · \(incident.elapsedString)",
            detail: "",
            timestamp: incident.createdAt,
            actions: [
                FeedAction(id: "view-incident-\(incident.id)", label: "View Incident",
                          icon: "exclamationmark.shield", style: .primary) { /* navigate */ }
            ],
            navigateTo: "incidents",
            metadata: ["ticketKey": incident.jiraTicketKey ?? ""]
        ))
    }

    // My Tickets (only overdue or high priority) → feed items
    for ticket in myTickets {
        let isOverdue = {
            guard let due = ticket.fields.duedate, !due.isEmpty else { return false }
            return due < String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        }()
        let priorityName = ticket.fields.priority?.name?.lowercased() ?? ""
        let isHighPri = priorityName == "highest" || priorityName == "high"

        // Only include overdue or high-priority tickets in the feed
        // All tickets are still available in My TODO
        guard isOverdue || isHighPri else { continue }

        items.append(FeedItem(
            id: "jira-\(ticket.key)",
            source: .jiraTicket,
            priority: isOverdue ? .high : .medium,
            title: "\(ticket.key) \(ticket.fields.summary ?? "")",
            subtitle: "\(ticket.fields.status?.name ?? "") · \(ticket.fields.priority?.name ?? "")\(isOverdue ? " · OVERDUE" : "")",
            detail: "",
            timestamp: parseISO8601(ticket.fields.updated ?? "") ?? Date(),
            actions: [
                FeedAction(id: "view-ticket-\(ticket.key)", label: "Open Ticket",
                          icon: "ticket", style: .secondary) { /* set selectedTicketKey */ }
            ],
            navigateTo: "jira_todo",
            metadata: ["ticketKey": ticket.key]
        ))
    }

    // Jenkins Failures → feed items
    for (jobName, build) in recentBuilds where build.result == "FAILURE" {
        items.append(FeedItem(
            id: "jenkins-\(jobName)-\(build.number)",
            source: .jenkinsBuild,
            priority: .high,
            title: "Build failed: \(jobName) #\(build.number)",
            subtitle: "Jenkins · \(build.result ?? "FAILURE")",
            detail: "",
            timestamp: Date(timeIntervalSince1970: TimeInterval(build.timestamp) / 1000),
            actions: [
                FeedAction(id: "view-jenkins-\(jobName)", label: "View Build",
                          icon: "hammer", style: .secondary) { /* navigate */ }
            ],
            navigateTo: "jenkins_browser",
            metadata: ["jobName": jobName, "buildNumber": String(build.number)]
        ))
    }

    // GitHub PRs needing review → feed items
    for pr in recentPRs {
        items.append(FeedItem(
            id: "pr-\(pr.id)",
            source: .githubPR,
            priority: .medium,
            title: "PR #\(pr.number): \(pr.title)",
            subtitle: "@\(pr.authorLogin) · \(pr.headBranch) → \(pr.baseBranch)",
            detail: "",
            timestamp: parseISO8601(pr.updatedAt) ?? Date(),
            actions: [
                FeedAction(id: "view-pr-\(pr.id)", label: "View PR",
                          icon: "arrow.triangle.pull", style: .secondary) { /* navigate */ }
            ],
            navigateTo: "github_browser",
            metadata: ["prNumber": String(pr.number)]
        ))
    }

    // On-Call Status → single feed item (always present, low priority)
    if !onCallSchedules.isEmpty {
        let summaryParts = onCallSchedules.prefix(3).compactMap { schedule -> String? in
            guard let participants = onCallParticipants[schedule.id], let primary = participants.first else { return nil }
            let name = onCallDisplayNames[primary.name] ?? primary.name
            return "\(schedule.name): \(name)"
        }
        items.append(FeedItem(
            id: "oncall-status",
            source: .onCall,
            priority: .low,
            title: "On-Call",
            subtitle: summaryParts.joined(separator: " · "),
            detail: "",
            timestamp: Date(),
            actions: [
                FeedAction(id: "view-oncall", label: "View Schedules",
                          icon: "phone.badge.waveform", style: .secondary) { /* navigate */ }
            ],
            navigateTo: "oncall",
            metadata: [:]
        ))
    }

    // AI Daily Summary → single feed item (always at the bottom)
    if let summary = aiSummary {
        items.append(FeedItem(
            id: "ai-summary",
            source: .aiSummary,
            priority: .info,
            title: "AI Daily Brief",
            subtitle: aiSummaryDate.map { "Generated \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()))" } ?? "",
            detail: summary,
            timestamp: aiSummaryDate ?? Date(),
            actions: [],
            navigateTo: nil,
            metadata: [:]
        ))
    }

    // Sort: by priority first (critical → info), then by timestamp (newest first within same priority)
    items.sort { a, b in
        if a.priority != b.priority { return a.priority < b.priority }
        return a.timestamp > b.timestamp
    }

    return items
}

private func parseISO8601(_ string: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}
```

For the alert actions, create a helper that builds ACK/Close/Snooze buttons:

```swift
private func buildAlertActions(_ alert: OpsAlert, appState: AppState) -> [FeedAction] {
    var actions: [FeedAction] = []
    if alert.status.lowercased() == "open" && !alert.acknowledged {
        actions.append(FeedAction(id: "ack-\(alert.id)", label: "ACK", icon: "checkmark.circle", style: .primary) {
            try? await self.jsmOpsService.acknowledgeAlert(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, alertId: alert.id)
            await self.refreshAll(appState: appState)
        })
    }
    if alert.status.lowercased() != "closed" {
        actions.append(FeedAction(id: "close-\(alert.id)", label: "Close", icon: "xmark.circle", style: .destructive) {
            try? await self.jsmOpsService.closeAlert(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, alertId: alert.id)
            await self.refreshAll(appState: appState)
        })
    }
    return actions
}
```

Note: The `FeedAction.action` closure captures `appState` and `self` — you may need to adjust for actor isolation. Use `@Sendable` or pass the needed values explicitly.

### Phase 46C: Create the Feed View

Create `BoomiSRE/Sources/Views/FeedView.swift`:

```swift
struct FeedView: View {
    let items: [FeedItem]
    @EnvironmentObject var appState: AppState

    var body: some View {
        if items.isEmpty {
            allClearView
        } else {
            LazyVStack(spacing: 12) {
                // Urgent items (critical + high)
                let urgent = items.filter { $0.priority <= .high }
                let normal = items.filter { $0.priority == .medium }
                let calm = items.filter { $0.priority >= .low }

                ForEach(urgent) { item in
                    FeedItemCard(item: item)
                }

                if !urgent.isEmpty && !normal.isEmpty {
                    dividerLabel("Needs Attention")
                }

                ForEach(normal) { item in
                    FeedItemCard(item: item)
                }

                if (!urgent.isEmpty || !normal.isEmpty) && !calm.isEmpty {
                    dividerLabel("All Clear Below")
                }

                ForEach(calm) { item in
                    FeedItemCard(item: item)
                }
            }
        }
    }

    private func dividerLabel(_ text: String) -> some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
        }
        .padding(.vertical, 8)
    }

    private var allClearView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
            Text("All Clear").font(.title2.bold())
            Text("No items need your attention right now.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
```

Create the individual feed item card:

```swift
struct FeedItemCard: View {
    let item: FeedItem
    @EnvironmentObject var appState: AppState
    @State private var isActioning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: source badge + title + timestamp
            HStack(alignment: .top, spacing: 10) {
                // Priority indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(priorityColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    // Source + time
                    HStack(spacing: 6) {
                        Image(systemName: item.source.icon)
                            .font(.caption)
                            .foregroundStyle(item.source.color)
                        Text(item.source.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(item.source.color)
                        Spacer()
                        Text(item.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Title
                    Text(item.title)
                        .font(.callout.bold())
                        .lineLimit(2)

                    // Subtitle
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Detail / AI analysis
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                    }

                    // Action buttons
                    if !item.actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(item.actions) { action in
                                Button {
                                    isActioning = true
                                    Task {
                                        await action.action()
                                        isActioning = false
                                    }
                                } label: {
                                    Label(action.label, systemImage: action.icon)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(action.style == .destructive ? .red : action.style == .primary ? .accentColor : nil)
                                .disabled(isActioning)
                            }
                            if isActioning { ProgressView().scaleEffect(0.6) }
                            Spacer()
                            if let nav = item.navigateTo {
                                Button {
                                    appState.selectedReport = ReportCatalog.all.first { $0.id == nav }
                                    appState.showSettings = false
                                } label: {
                                    Label("View All", systemImage: "chevron.right")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(item.priority == .critical ? Color.red.opacity(0.4) :
                              item.priority == .high ? Color.orange.opacity(0.2) :
                              Color.secondary.opacity(0.1))
        )
    }

    private var priorityColor: Color {
        switch item.priority {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .blue
        case .low:      return .green
        case .info:     return .secondary
        }
    }
}
```

### Phase 46D: Integrate Feed into DashboardView

Update `DashboardView` to support both Feed mode and Widget mode:

1. **Add a new dashboard mode option.** Change `dashboardMode` from "auto"/"custom" to support three modes:
   - `"feed"` — the new intelligent feed (NEW DEFAULT)
   - `"auto"` — auto-managed widget grid (existing)
   - `"widgets"` — custom widget grid (existing, renamed from "custom")

2. **In the dashboard body, switch on mode:**
   ```swift
   ScrollView {
       VStack(spacing: 0) {
           switch appState.dashboardMode {
           case "feed":
               FeedView(items: vm.buildFeed(appState: appState))
                   .environmentObject(appState)
                   .padding(20)
           case "auto":
               widgetGrid.padding(20)
           default:  // "widgets" (custom)
               widgetGrid.padding(20)
           }

           // MOTD at the bottom (all modes)
           MOTDView(message: currentMOTD) { cycleMOTD() }
               .opacity(motdOpacity)
               .padding(.horizontal, 20).padding(.bottom, 20)
       }
   }
   ```

3. **Update the Customize popup** to offer three modes:
   ```swift
   Picker("Dashboard Mode", selection: $appState.dashboardMode) {
       Text("Feed").tag("feed")
       Text("Auto Widgets").tag("auto")
       Text("Custom Widgets").tag("widgets")
   }
   .pickerStyle(.segmented)
   ```
   - In Feed mode: show a brief explanation: "A single prioritized stream of everything that needs your attention. Most urgent items at the top with inline actions."
   - In Auto Widgets mode: show the AI priority explanation
   - In Custom Widgets mode: show the widget toggle list

4. **Set "feed" as the new default** for new users and when resetting to defaults.

### Phase 46E: AI Enrichment for Feed Items (Optional Enhancement)

For the highest-priority feed items (critical and high), automatically request a one-sentence AI analysis and inject it into the `detail` field:

```swift
// After building the feed, enrich the top items with AI context
func enrichFeedWithAI(items: inout [FeedItem], appState: AppState) async {
    guard claudeService.discoverAPIKey() != nil else { return }
    let topItems = items.prefix(5).filter { $0.priority <= .high && $0.detail.isEmpty }
    guard !topItems.isEmpty else { return }

    // Build a single prompt with all top items
    let context = topItems.map { "- [\($0.source.rawValue)] \($0.title): \($0.subtitle)" }.joined(separator: "\n")
    let prompt = """
    For each of the following SRE items, provide ONE sentence of actionable context (what to check first, what it likely means, or what to do):
    \(context)
    Respond with one line per item, in the same order. Be specific and concise.
    """

    if let response = try? await claudeService.chat(
        messages: [("user", prompt)],
        systemPrompt: "You are an SRE assistant. Give one-sentence actionable advice per item." +
            (appState.userProfile.experienceLevel.analysisDepthHint.isEmpty ? "" : "\n" + appState.userProfile.experienceLevel.analysisDepthHint),
        maxTokens: 300
    ) {
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() where i < topItems.count {
            if let idx = items.firstIndex(where: { $0.id == topItems[i].id }) {
                items[idx] = FeedItem(
                    id: items[idx].id, source: items[idx].source, priority: items[idx].priority,
                    title: items[idx].title, subtitle: items[idx].subtitle,
                    detail: line.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[-•\\d]+\\.?\\s*", with: "", options: .regularExpression),
                    timestamp: items[idx].timestamp, actions: items[idx].actions,
                    navigateTo: items[idx].navigateTo, metadata: items[idx].metadata
                )
            }
        }
    }
}
```

Call this after `buildFeed()` in the dashboard's refresh flow. Cache the enrichments so they don't re-generate on every scroll.

### Phase 46F: Feed Item Navigation Actions

The "View All" and action buttons in feed items need to actually navigate. Wire them up:

- **Alert actions** (ACK, Close): call the JSMOpsService methods (already implemented in OnCallViewModel — reuse the pattern). After the action completes, refresh the feed.
- **"Open Ticket"**: set `appState.selectedTicketKey = ticketKey`
- **"View PR"**: set `appState.selectedReport` to the GitHub browser
- **"View Build"**: set `appState.selectedReport` to the Jenkins browser
- **"View Schedules"**: set `appState.selectedReport` to the On-Call section
- **"View in Grafana"**: set `appState.selectedReport` to the Grafana browser

Since `FeedAction.action` is an async closure, the navigation can be done inside the closure by accessing `appState` (passed via environment or captured).

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Add Intelligent Feed — unified prioritized stream for the home page"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

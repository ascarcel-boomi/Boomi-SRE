# Boomi SRE App — Phase 49: Productivity Tracker

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. This is Phase E of the v2 evolution (see `docs/VISION_V2.md`).

**Read these files first:**
- `docs/VISION_V2.md` — the "Productivity Tracker" section
- `BoomiSRE/Sources/Models/AppState.swift` — central state
- `BoomiSRE/Sources/Views/DashboardView.swift` — home page (health score bar where "time saved" will appear)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — alert actions (ACK, Close, Snooze, Add Note)
- `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift` — incident AI analysis, postmortem, status update
- `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` — PR summarize, review
- `BoomiSRE/Sources/ViewModels/ChatViewModel.swift` — copilot queries
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — AI daily summary
- `BoomiSRE/Sources/ViewModels/CostExplorerViewModel.swift` — cost analysis
- `BoomiSRE/Sources/ViewModels/GrafanaBrowserViewModel.swift` — dashboard explain, alert analyze
- `BoomiSRE/Sources/ViewModels/ConfluenceBrowserViewModel.swift` — page summarize, draft
- `BoomiSRE/Sources/ViewModels/BitbucketBrowserViewModel.swift` — PR summarize, review
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — for understanding file-based persistence

---

## Goal

Track every meaningful action the SRE takes in the app and estimate how much time it saved them compared to doing it manually. Display this as a motivating badge ("You've saved 2.3 hours today") and provide a detailed analytics view for individual and team-level reporting.

This proves the 50x productivity mandate and motivates adoption — even skeptics engage when they see the numbers.

---

## Implementation

### Phase 49A: Define the Productivity Model

Create `BoomiSRE/Sources/Models/ProductivityModels.swift`:

```swift
import Foundation

struct ProductivityEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let action: ProductivityAction
    let detail: String              // human-readable description
    let estimatedMinutesSaved: Double
    let source: String              // which screen/feature generated this

    init(id: UUID = UUID(), action: ProductivityAction, detail: String,
         estimatedMinutesSaved: Double, source: String) {
        self.id = id
        self.timestamp = Date()
        self.action = action
        self.detail = detail
        self.estimatedMinutesSaved = estimatedMinutesSaved
        self.source = source
    }
}

enum ProductivityAction: String, Codable {
    // Alert actions
    case alertAcknowledged       // 2 min saved (vs. logging into JSM, finding alert, clicking)
    case alertClosed             // 2 min saved
    case alertSnoozed            // 1 min saved
    case alertNoteAdded          // 2 min saved

    // AI features
    case aiCopilotQuery          // 3 min saved (vs. researching the answer)
    case aiPRSummary             // 10 min saved (vs. reading the full PR)
    case aiPRReview              // 15 min saved (vs. doing a full SRE review manually)
    case aiIncidentAnalysis      // 15 min saved
    case aiPostmortemDraft       // 30 min saved
    case aiStatusUpdateDraft     // 10 min saved
    case aiRemediationSuggestion // 10 min saved
    case aiDashboardExplain      // 5 min saved
    case aiAlertAnalyze          // 5 min saved
    case aiPageSummarize         // 5 min saved
    case aiPageDraft             // 20 min saved
    case aiCostAnalysis          // 10 min saved
    case aiDailySummary          // 15 min saved
    case aiPCRGeneration         // 30 min saved

    // Navigation/context savings
    case kbArticleLookup         // 5 min saved (vs. searching Confluence, asking a colleague)
    case ticketViewedInApp       // 1 min saved (vs. opening Jira in browser)
    case prViewedInApp           // 1 min saved (vs. opening GitHub in browser)
    case buildViewedInApp        // 1 min saved (vs. opening Jenkins in browser)
    case incidentCreated         // 5 min saved (vs. creating in Jira manually)
    case productContextSwitch    // 3 min saved (vs. reconfiguring filters manually)

    // Bulk actions
    case bulkAlertAcknowledge    // 1 min per alert saved
    case bulkAlertClose          // 1 min per alert saved

    var estimatedMinutes: Double {
        switch self {
        case .alertAcknowledged, .alertClosed, .alertNoteAdded: return 2
        case .alertSnoozed: return 1
        case .aiCopilotQuery: return 3
        case .aiPRSummary: return 10
        case .aiPRReview: return 15
        case .aiIncidentAnalysis, .aiRemediationSuggestion, .aiStatusUpdateDraft, .aiCostAnalysis: return 10
        case .aiPostmortemDraft, .aiPCRGeneration: return 30
        case .aiDashboardExplain, .aiAlertAnalyze, .aiPageSummarize: return 5
        case .aiPageDraft: return 20
        case .aiDailySummary: return 15
        case .kbArticleLookup: return 5
        case .ticketViewedInApp, .prViewedInApp, .buildViewedInApp: return 1
        case .incidentCreated: return 5
        case .productContextSwitch: return 3
        case .bulkAlertAcknowledge, .bulkAlertClose: return 1
        }
    }

    var category: String {
        switch self {
        case .alertAcknowledged, .alertClosed, .alertSnoozed, .alertNoteAdded,
             .bulkAlertAcknowledge, .bulkAlertClose:
            return "Alert Management"
        case .aiCopilotQuery, .aiPRSummary, .aiPRReview, .aiIncidentAnalysis,
             .aiPostmortemDraft, .aiStatusUpdateDraft, .aiRemediationSuggestion,
             .aiDashboardExplain, .aiAlertAnalyze, .aiPageSummarize, .aiPageDraft,
             .aiCostAnalysis, .aiDailySummary, .aiPCRGeneration:
            return "AI Assistance"
        case .kbArticleLookup:
            return "Knowledge"
        case .ticketViewedInApp, .prViewedInApp, .buildViewedInApp,
             .incidentCreated, .productContextSwitch:
            return "Navigation"
        }
    }
}
```

### Phase 49B: Create the Productivity Tracker Service

Create `BoomiSRE/Sources/Services/ProductivityTracker.swift`:

```swift
import Foundation

/// Singleton that logs productivity events and calculates time savings.
/// Persists events to ~/.boomi_sre_productivity.json
@MainActor
final class ProductivityTracker: ObservableObject {
    static let shared = ProductivityTracker()

    @Published var events: [ProductivityEvent] = []

    private let storageURL: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        storageURL = home.appendingPathComponent(".boomi_sre_productivity.json")
        loadEvents()
    }

    // MARK: - Log an event

    func log(_ action: ProductivityAction, detail: String = "", source: String = "") {
        let event = ProductivityEvent(
            action: action,
            detail: detail.isEmpty ? action.rawValue : detail,
            estimatedMinutesSaved: action.estimatedMinutes,
            source: source
        )
        events.append(event)
        saveEvents()
    }

    // MARK: - Computed Metrics

    /// Total minutes saved today
    var minutesSavedToday: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return events
            .filter { $0.timestamp >= startOfDay }
            .reduce(0) { $0 + $1.estimatedMinutesSaved }
    }

    /// Total minutes saved this week
    var minutesSavedThisWeek: Double {
        let startOfWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return events
            .filter { $0.timestamp >= startOfWeek }
            .reduce(0) { $0 + $1.estimatedMinutesSaved }
    }

    /// Total minutes saved this month
    var minutesSavedThisMonth: Double {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let startOfMonth = Calendar.current.date(from: comps) ?? Date()
        return events
            .filter { $0.timestamp >= startOfMonth }
            .reduce(0) { $0 + $1.estimatedMinutesSaved }
    }

    /// Formatted string for display
    var timeSavedTodayFormatted: String {
        let mins = minutesSavedToday
        if mins < 60 { return "\(Int(mins)) min" }
        let hours = mins / 60
        if hours < 10 { return String(format: "%.1f hours", hours) }
        return "\(Int(hours)) hours"
    }

    /// Action count today
    var actionsToday: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return events.filter { $0.timestamp >= startOfDay }.count
    }

    /// Events grouped by category for today
    var todayByCategory: [(category: String, minutes: Double, count: Int)] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayEvents = events.filter { $0.timestamp >= startOfDay }
        let grouped = Dictionary(grouping: todayEvents) { $0.action.category }
        return grouped.map { (category: $0.key, minutes: $0.value.reduce(0) { $0 + $1.estimatedMinutesSaved }, count: $0.value.count) }
            .sorted { $0.minutes > $1.minutes }
    }

    /// Daily totals for the past 7 days (for a chart)
    var weeklyTrend: [(date: Date, minutes: Double)] {
        let cal = Calendar.current
        return (0..<7).reversed().map { daysAgo in
            let date = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let mins = events.filter { $0.timestamp >= start && $0.timestamp < end }
                .reduce(0) { $0 + $1.estimatedMinutesSaved }
            return (date: start, minutes: mins)
        }
    }

    // MARK: - Persistence

    private func loadEvents() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ProductivityEvent].self, from: data) else { return }
        // Keep only last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        events = decoded.filter { $0.timestamp >= cutoff }
    }

    private func saveEvents() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}
```

### Phase 49C: Instrument All Trackable Actions

Add `ProductivityTracker.shared.log(...)` calls at every action point across the app. Do NOT change any existing functionality — just add a one-line log call after each action succeeds.

**Alert actions (OnCallViewModel.swift):**
```swift
// After acknowledgeAlert succeeds:
ProductivityTracker.shared.log(.alertAcknowledged, detail: "ACK: \(alert.message)", source: "On-Call")

// After closeAlert succeeds:
ProductivityTracker.shared.log(.alertClosed, detail: "Closed: \(alert.message)", source: "On-Call")

// After snoozeAlert succeeds:
ProductivityTracker.shared.log(.alertSnoozed, detail: "Snoozed: \(alert.message)", source: "On-Call")

// After addNoteToAlert succeeds:
ProductivityTracker.shared.log(.alertNoteAdded, detail: "Note on: \(alert.message)", source: "On-Call")

// After bulkAcknowledge:
ProductivityTracker.shared.log(.bulkAlertAcknowledge, detail: "Bulk ACK \(alerts.count) alerts", source: "On-Call")

// After bulkClose:
ProductivityTracker.shared.log(.bulkAlertClose, detail: "Bulk close \(alerts.count) alerts", source: "On-Call")
```

**AI features (various ViewModels):**
```swift
// ChatViewModel.send() — after successful response:
ProductivityTracker.shared.log(.aiCopilotQuery, detail: String(inputText.prefix(50)), source: "AI Copilot")

// GitHubBrowserViewModel.summarizePR():
ProductivityTracker.shared.log(.aiPRSummary, detail: "PR #\(pr.number)", source: "GitHub")

// GitHubBrowserViewModel.reviewPR():
ProductivityTracker.shared.log(.aiPRReview, detail: "PR #\(pr.number)", source: "GitHub")

// IncidentViewModel.analyzeIncident():
ProductivityTracker.shared.log(.aiIncidentAnalysis, detail: incident.title, source: "Incidents")

// IncidentViewModel.draftPostmortem():
ProductivityTracker.shared.log(.aiPostmortemDraft, detail: incident.title, source: "Incidents")

// IncidentViewModel.draftStatusUpdate():
ProductivityTracker.shared.log(.aiStatusUpdateDraft, detail: incident.title, source: "Incidents")

// IncidentViewModel.suggestRemediation():
ProductivityTracker.shared.log(.aiRemediationSuggestion, detail: incident.title, source: "Incidents")

// GrafanaBrowserViewModel.explainDashboard():
ProductivityTracker.shared.log(.aiDashboardExplain, source: "Grafana")

// GrafanaBrowserViewModel.analyzeAlerts():
ProductivityTracker.shared.log(.aiAlertAnalyze, source: "Grafana")

// ConfluenceBrowserViewModel.summarizePage():
ProductivityTracker.shared.log(.aiPageSummarize, source: "Confluence")

// ConfluenceBrowserViewModel.draftNewPage():
ProductivityTracker.shared.log(.aiPageDraft, source: "Confluence")

// CostExplorerViewModel.analyzeCosts():
ProductivityTracker.shared.log(.aiCostAnalysis, source: "AWS Costs")

// DashboardViewModel.generateAISummary():
ProductivityTracker.shared.log(.aiDailySummary, source: "Dashboard")

// BitbucketBrowserViewModel.summarizePR() / reviewPR():
ProductivityTracker.shared.log(.aiPRSummary, source: "Bitbucket")
ProductivityTracker.shared.log(.aiPRReview, source: "Bitbucket")
```

**Navigation savings:**
```swift
// When product context changes (AppState or wherever selectedProductId is set):
ProductivityTracker.shared.log(.productContextSwitch, detail: "Switched to \(product.name)", source: "Product Context")

// When a ticket is opened via selectedTicketKey:
ProductivityTracker.shared.log(.ticketViewedInApp, detail: ticketKey, source: "Jira")

// When KB article is viewed (KnowledgeBaseViewModel):
ProductivityTracker.shared.log(.kbArticleLookup, detail: article.title, source: "Knowledge Base")
```

**Important:** Only log on SUCCESS. If an AI call fails or an alert action errors, don't log a productivity event.

### Phase 49D: Display Time Saved in the Dashboard Header

Add a "time saved" badge next to the health score in the dashboard header:

```swift
// In DashboardView, add to the health score bar area:
HStack(spacing: 6) {
    Image(systemName: "clock.arrow.circlepath")
        .font(.caption)
        .foregroundStyle(.green)
    Text("Saved \(ProductivityTracker.shared.timeSavedTodayFormatted) today")
        .font(.caption.bold())
        .foregroundStyle(.green)
}
.padding(.horizontal, 8).padding(.vertical, 3)
.background(Capsule().fill(Color.green.opacity(0.1)))
.help("Estimated time saved by using Boomi SRE instead of manual tools")
```

This should be subtle and motivating — not dominant. Place it in the health score bar or next to the greeting.

### Phase 49E: Create Productivity Analytics View

Create `BoomiSRE/Sources/Views/Panels/ProductivityView.swift` — a detailed analytics view accessible from Settings or a new sidebar item:

```swift
import SwiftUI
import Charts

struct ProductivityView: View {
    @ObservedObject var tracker = ProductivityTracker.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Productivity Analytics").font(.title2.bold())

                // Summary cards
                HStack(spacing: 16) {
                    metricCard("Today", value: tracker.timeSavedTodayFormatted,
                              subtitle: "\(tracker.actionsToday) actions", color: .green)
                    metricCard("This Week", value: formatMinutes(tracker.minutesSavedThisWeek),
                              subtitle: "", color: .blue)
                    metricCard("This Month", value: formatMinutes(tracker.minutesSavedThisMonth),
                              subtitle: "", color: .purple)
                }

                // Weekly trend chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 7 Days").font(.headline)
                    Chart(tracker.weeklyTrend, id: \.date) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes Saved", point.minutes)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .frame(height: 150)
                    .chartYAxisLabel("Minutes")
                }

                // Today's breakdown by category
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today by Category").font(.headline)
                    ForEach(tracker.todayByCategory, id: \.category) { cat in
                        HStack {
                            Text(cat.category).font(.callout)
                            Spacer()
                            Text("\(cat.count) actions").font(.caption).foregroundStyle(.secondary)
                            Text(formatMinutes(cat.minutes)).font(.callout.bold())
                        }
                        .padding(.vertical, 4)
                    }
                    if tracker.todayByCategory.isEmpty {
                        Text("No actions recorded today yet. Start using the app!")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                // Recent activity log
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity").font(.headline)
                    ForEach(tracker.events.suffix(20).reversed()) { event in
                        HStack(spacing: 8) {
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospaced()).foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .trailing)
                            Text(event.detail)
                                .font(.caption).lineLimit(1)
                            Spacer()
                            Text("+\(Int(event.estimatedMinutesSaved))m")
                                .font(.caption.bold()).foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func metricCard(_ title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(color)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.08)))
    }

    private func formatMinutes(_ mins: Double) -> String {
        if mins < 60 { return "\(Int(mins)) min" }
        let hours = mins / 60
        if hours < 10 { return String(format: "%.1f hours", hours) }
        return "\(Int(hours)) hours"
    }
}
```

### Phase 49F: Make Productivity View Accessible

Add the Productivity view to the app:

1. **In Settings** — add a "Productivity" tab showing the `ProductivityView`:
   ```swift
   settingsTab("productivity", label: "Productivity", icon: "chart.line.uptrend.xyaxis", status: nil)
   ```

2. **In the dashboard health score bar** — make the "Saved X today" badge clickable. Clicking it opens Settings → Productivity tab.

3. **Add `ProductivityTracker.shared` as an `@EnvironmentObject`** if needed for views that access it. Since it's a singleton, views can also access it directly via `ProductivityTracker.shared`.

4. **Add to factory reset** — `~/.boomi_sre_productivity.json` should be in the list of files deleted during factory reset (in `AppState.factoryReset()`).

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Add Productivity Tracker — measure and display time saved"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

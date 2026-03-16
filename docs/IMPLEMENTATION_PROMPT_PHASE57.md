# Boomi SRE App — Phase 57: BPOP Dashboard & Gamified Productivity Metrics

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `~/Downloads/Combined_SRE_BPOP_FY27_v2.csv` — the combined BPOP with 5 pillars × 3 metrics = 15 metrics
- `BoomiSRE/Sources/Models/ProductContext.swift` — product/team definitions (CAM SRE, MFT SRE, DI SRE, MCS SRE, Boomi SRE)
- `BoomiSRE/Sources/Models/ProductivityModels.swift` — existing productivity tracking (events, time saved)
- `BoomiSRE/Sources/Services/ProductivityTracker.swift` — existing productivity tracker singleton
- `BoomiSRE/Sources/Views/Panels/ProductivityView.swift` — existing productivity analytics view
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira API (currently no agile/sprint API methods)
- `BoomiSRE/Sources/Models/JiraModels.swift` — JiraSprint model (id, name, state, startDate, endDate)
- `BoomiSRE/Sources/Models/AppState.swift` — team/product configuration

**Key Jira fields:**
- Sprint: `customfield_10020` (array of sprint objects)
- Story points: `customfield_10015` (number)
- Epic link: `customfield_10014` or `parent` field

---

## Goal

1. **BPOP Dashboard** — A live view of the 15 BPOP metrics with per-team and combined tracking. Managers see the aggregated view. Individual SREs see their team's contribution.

2. **Sprint/Epic Velocity** — Pull story points from Jira per sprint and per epic, broken down by team. Show velocity trends over time.

3. **Gamified Productivity** — Leaderboards, streaks, and achievements that motivate teams to hit their BPOP targets.

---

## Implementation

### Phase 57A: BPOP Data Model

Create `BoomiSRE/Sources/Models/BPOPModels.swift`:

```swift
import Foundation
import SwiftUI

enum BPOPPillar: String, Codable, CaseIterable {
    case culture = "Culture"
    case platform = "Platform"
    case growth = "Growth"
    case trust = "Trust"
    case focus = "Focus"

    var icon: String {
        switch self {
        case .culture:  return "person.3.fill"
        case .platform: return "server.rack"
        case .growth:   return "chart.line.uptrend.xyaxis"
        case .trust:    return "shield.checkmark"
        case .focus:    return "target"
        }
    }

    var color: Color {
        switch self {
        case .culture:  return .purple
        case .platform: return .blue
        case .growth:   return .green
        case .trust:    return .orange
        case .focus:    return .red
        }
    }
}

struct BPOPMetric: Identifiable, Codable {
    let id: String                    // unique key: "culture-enps", "platform-sla", etc.
    let pillar: BPOPPillar
    let name: String                  // short name: "eNPS Improvement"
    let description: String           // full metric text from BPOP
    let targetValue: Double           // target number (e.g., 5 for 5pt improvement, 99.99 for SLA)
    let unit: MetricUnit              // how to display the value
    var currentValue: Double?         // latest measured value (nil = not yet measured)
    var teamValues: [String: Double]  // teamId -> value (for per-team breakdown)
    var dataSource: MetricDataSource  // where the data comes from
    var lastUpdated: Date?

    var progressPercent: Double {
        guard let current = currentValue, targetValue != 0 else { return 0 }
        return min(100, (current / targetValue) * 100)
    }

    var status: MetricStatus {
        guard let _ = currentValue else { return .notMeasured }
        let pct = progressPercent
        if pct >= 90 { return .onTrack }
        if pct >= 60 { return .atRisk }
        return .offTrack
    }
}

enum MetricUnit: String, Codable {
    case points       // "5 pts"
    case percent      // "99.99%"
    case count        // "45"
    case days         // "5 days"
    case hours        // "10 hrs"
    case ratio        // "70%"
}

enum MetricStatus: String {
    case onTrack    // green — 90%+ of target
    case atRisk     // yellow — 60-89% of target
    case offTrack   // red — <60% of target
    case notMeasured // grey — no data yet

    var color: Color {
        switch self {
        case .onTrack:     return .green
        case .atRisk:      return .yellow
        case .offTrack:    return .red
        case .notMeasured: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .onTrack:     return "checkmark.circle.fill"
        case .atRisk:      return "exclamationmark.triangle.fill"
        case .offTrack:    return "xmark.circle.fill"
        case .notMeasured: return "questionmark.circle"
        }
    }
}

enum MetricDataSource: String, Codable {
    case automatic    // pulled from Jira, JSM, app analytics automatically
    case manual       // entered by a manager (eNPS, retention, compliance)
    case hybrid       // some data automatic, some manual
}
```

### Phase 57B: Define the 15 BPOP Metrics

Create `BoomiSRE/Sources/Models/BPOPData.swift`:

```swift
extension BPOPMetric {
    static let allMetrics: [BPOPMetric] = [
        // ── CULTURE ─────────────────────────────────────────
        BPOPMetric(id: "culture-enps", pillar: .culture,
                   name: "eNPS & Retention",
                   description: "5pt improvement in eNPS YoY with 90%+ high-performer retention",
                   targetValue: 5, unit: .points, teamValues: [:], dataSource: .manual),
        BPOPMetric(id: "culture-ai-adoption", pillar: .culture,
                   name: "AI Adoption",
                   description: "90% of SRE workflows using approved AI tools with measured productivity gains",
                   targetValue: 90, unit: .percent, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "culture-training", pillar: .culture,
                   name: "BPOP & Training",
                   description: "100% BPOP participation; 10hr IC / 8hr manager coursework completed",
                   targetValue: 100, unit: .percent, teamValues: [:], dataSource: .manual),

        // ── PLATFORM ────────────────────────────────────────
        BPOPMetric(id: "platform-sla", pillar: .platform,
                   name: "SLA & Security",
                   description: "99.99% Platform and Runtime SLA with A+ security scorecard — including acquisitions",
                   targetValue: 99.99, unit: .percent, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "platform-resilience", pillar: .platform,
                   name: "Resilience & Testing",
                   description: "Quarterly DR game days; 90% test coverage for new modules; 30% regression expansion",
                   targetValue: 4, unit: .count, teamValues: [:], dataSource: .hybrid),
        BPOPMetric(id: "platform-recurring", pillar: .platform,
                   name: "Recurring Issues",
                   description: "5 recurring operational issues identified and remediated per quarter",
                   targetValue: 20, unit: .count, teamValues: [:], dataSource: .manual),

        // ── GROWTH ──────────────────────────────────────────
        BPOPMetric(id: "growth-transition", pillar: .growth,
                   name: "Service Transition",
                   description: "Transition deployment + infra ops for 20 services from Element teams to SRE",
                   targetValue: 20, unit: .count, teamValues: [:], dataSource: .manual),
        BPOPMetric(id: "growth-golden-metrics", pillar: .growth,
                   name: "Golden Metrics",
                   description: "Improve service management golden metrics by 50% vs FY26; reduce change lead time by 20%",
                   targetValue: 50, unit: .percent, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "growth-compliance-ai", pillar: .growth,
                   name: "Compliance & AI",
                   description: "All compliance attestations retained; at least one AI Agent per SRE element",
                   targetValue: 100, unit: .percent, teamValues: [:], dataSource: .hybrid),

        // ── TRUST ───────────────────────────────────────────
        BPOPMetric(id: "trust-rca-capa", pillar: .trust,
                   name: "RCA & CAPA",
                   description: "Sev-1 RCAs within 5 business days (95%); CAPA within 3 weeks for High/Critical",
                   targetValue: 95, unit: .percent, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "trust-mttd-mttr", pillar: .trust,
                   name: "MTTD/MTTR",
                   description: "25% improvement in MTTD and MTTR via AI anomaly detection — one per element",
                   targetValue: 25, unit: .percent, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "trust-defects", pillar: .trust,
                   name: "Defect Reduction",
                   description: "Bug backlog reduced 45%; release Sev-1/2 reduced 15%; zero DNS/cert disruptions",
                   targetValue: 45, unit: .percent, teamValues: [:], dataSource: .automatic),

        // ── FOCUS ───────────────────────────────────────────
        BPOPMetric(id: "focus-health-metrics", pillar: .focus,
                   name: "Engineering Health",
                   description: "5 health metrics tracked monthly — at least 4 improving by FY27 end",
                   targetValue: 4, unit: .count, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "focus-ai-generation", pillar: .focus,
                   name: "AI Code Generation",
                   description: "70% of code, docs, and test cases generated with AI tools with quality gates",
                   targetValue: 70, unit: .percent, teamValues: [:], dataSource: .automatic),
        BPOPMetric(id: "focus-change-safety", pillar: .focus,
                   name: "Change Safety",
                   description: "100% production changes validated in lower environments; SRE engaged early",
                   targetValue: 100, unit: .percent, teamValues: [:], dataSource: .hybrid),
    ]
}
```

### Phase 57C: Add Jira Agile API Methods for Sprint Velocity

Add sprint and story point methods to `JiraService`:

```swift
// In JiraService:

/// Fetch boards for a project
func listBoards(baseURL: String, email: String, apiToken: String,
                projectKey: String) async throws -> [AgileBoard] {
    // GET {baseURL}/rest/agile/1.0/board?projectKeyOrId={projectKey}
    // Returns: {"values": [{"id": 123, "name": "CAMSRE Board", "type": "scrum"}]}
}

/// Fetch sprints for a board
func listSprints(baseURL: String, email: String, apiToken: String,
                 boardId: Int, state: String = "active,closed") async throws -> [JiraSprint] {
    // GET {baseURL}/rest/agile/1.0/board/{boardId}/sprint?state={state}&maxResults=20
    // Returns: {"values": [{"id": 456, "name": "Sprint 24", "state": "closed", "startDate": "...", "endDate": "..."}]}
}

/// Fetch issues in a sprint with story points
func listSprintIssues(baseURL: String, email: String, apiToken: String,
                      sprintId: Int) async throws -> [SprintIssue] {
    // GET {baseURL}/rest/agile/1.0/sprint/{sprintId}/issue?fields=summary,status,assignee,customfield_10015,issuetype&maxResults=200
    // customfield_10015 = story points
    // Returns issues with their story point values
}

struct AgileBoard: Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String  // "scrum", "kanban"
}

struct SprintIssue: Identifiable, Sendable {
    let id: Int
    let key: String
    let summary: String
    let status: String
    let assignee: String
    let storyPoints: Double?
    let issueType: String
}
```

### Phase 57D: Sprint Velocity ViewModel

Create `BoomiSRE/Sources/ViewModels/VelocityViewModel.swift`:

```swift
@MainActor
final class VelocityViewModel: ObservableObject {
    @Published var sprints: [SprintVelocity] = []
    @Published var epicProgress: [EpicProgress] = []
    @Published var isLoading = false
    @Published var error: String?

    private let jiraService = JiraService()

    struct SprintVelocity: Identifiable {
        let id: Int          // sprint ID
        let name: String
        let state: String    // "closed", "active"
        let startDate: String
        let endDate: String
        let committed: Double   // total story points in sprint
        let completed: Double   // story points with status "Done"
        let teamId: String      // product/team context
    }

    struct EpicProgress: Identifiable {
        let id: String       // epic key
        let name: String
        let totalPoints: Double
        let completedPoints: Double
        let remainingPoints: Double
        let issueCount: Int
        let completedCount: Int
    }

    func loadVelocity(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isLoading = true; error = nil

        do {
            // For each configured Jira project, find boards and sprints
            let projectKeys = appState.selectedProduct?.jiraProjectKeys ?? appState.jiraProjectKeys
            var allSprints: [SprintVelocity] = []

            for projectKey in projectKeys {
                let boards = try await jiraService.listBoards(
                    baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken, projectKey: projectKey)

                for board in boards.filter({ $0.type == "scrum" }).prefix(3) {
                    let sprints = try await jiraService.listSprints(
                        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken, boardId: board.id)

                    for sprint in sprints.prefix(10) {
                        let issues = try await jiraService.listSprintIssues(
                            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                            apiToken: appState.jiraAPIToken, sprintId: sprint.id)

                        let committed = issues.compactMap(\.storyPoints).reduce(0, +)
                        let completed = issues.filter { $0.status.lowercased() == "done" }
                            .compactMap(\.storyPoints).reduce(0, +)

                        allSprints.append(SprintVelocity(
                            id: sprint.id, name: sprint.name, state: sprint.state,
                            startDate: sprint.startDate ?? "", endDate: sprint.endDate ?? "",
                            committed: committed, completed: completed,
                            teamId: projectKey))
                    }
                }
            }

            sprints = allSprints.sorted { $0.startDate > $1.startDate }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadEpicProgress(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        do {
            let projectKeys = appState.selectedProduct?.jiraProjectKeys ?? appState.jiraProjectKeys
            for projectKey in projectKeys {
                // Fetch epics: issuetype = Epic AND project = {key} AND statusCategory != Done
                let jql = "issuetype = Epic AND project = \"\(projectKey)\" AND statusCategory NOT IN (Done) ORDER BY priority ASC"
                let result = try await jiraService.searchIssues(
                    baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken, jql: jql,
                    fields: ["summary", "status", "customfield_10015"], maxResults: 20)

                // For each epic, count child story points
                // This requires additional queries per epic — do it for top 5 only
            }
        } catch { }
    }
}
```

### Phase 57E: BPOP Dashboard View

Create `BoomiSRE/Sources/Views/Panels/BPOPDashboardView.swift`:

```swift
import SwiftUI
import Charts

struct BPOPDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var metrics = BPOPMetric.allMetrics
    @State private var selectedPillar: BPOPPillar? = nil
    @State private var viewMode: ViewMode = .combined

    enum ViewMode: String, CaseIterable {
        case combined = "All Teams"
        case perTeam = "Per Team"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("BPOP — FY27 Plan on a Page").font(.title2.bold())
                Spacer()
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 200)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Overall progress ring
                    overallProgressCard

                    // Pillar cards
                    ForEach(BPOPPillar.allCases, id: \.self) { pillar in
                        pillarCard(pillar)
                    }
                }
                .padding(20)
            }
        }
    }

    private var overallProgressCard: some View {
        let measured = metrics.filter { $0.currentValue != nil }
        let onTrack = measured.filter { $0.status == .onTrack }.count
        let total = metrics.count

        return HStack(spacing: 24) {
            // Progress ring
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: Double(onTrack) / Double(total))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text("\(onTrack)/\(total)").font(.title.bold())
                    Text("On Track").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            // Pillar summary bars
            VStack(alignment: .leading, spacing: 8) {
                ForEach(BPOPPillar.allCases, id: \.self) { pillar in
                    let pillarMetrics = metrics.filter { $0.pillar == pillar }
                    let avgProgress = pillarMetrics.compactMap({ $0.currentValue != nil ? $0.progressPercent : nil }).reduce(0, +) / max(1, Double(pillarMetrics.count))
                    HStack(spacing: 8) {
                        Image(systemName: pillar.icon).foregroundStyle(pillar.color).frame(width: 20)
                        Text(pillar.rawValue).font(.caption).frame(width: 60, alignment: .leading)
                        ProgressView(value: avgProgress, total: 100)
                            .tint(avgProgress >= 90 ? .green : avgProgress >= 60 ? .yellow : .red)
                        Text("\(Int(avgProgress))%").font(.caption.monospaced()).frame(width: 35)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func pillarCard(_ pillar: BPOPPillar) -> some View {
        let pillarMetrics = metrics.filter { $0.pillar == pillar }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: pillar.icon).foregroundStyle(pillar.color)
                Text(pillar.rawValue).font(.headline)
                Spacer()
            }

            ForEach(pillarMetrics) { metric in
                metricRow(metric)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func metricRow(_ metric: BPOPMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: metric.status.icon)
                    .foregroundStyle(metric.status.color)
                Text(metric.name).font(.callout.bold())
                Spacer()
                if let current = metric.currentValue {
                    Text(formatValue(current, unit: metric.unit))
                        .font(.callout.bold()).foregroundStyle(metric.status.color)
                    Text("/ \(formatValue(metric.targetValue, unit: metric.unit))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not measured").font(.caption).foregroundStyle(.tertiary)
                }
            }

            // Progress bar
            ProgressView(value: metric.progressPercent, total: 100)
                .tint(metric.status.color)

            // Description
            Text(metric.description)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)

            // Per-team breakdown (if viewMode == .perTeam)
            if viewMode == .perTeam && !metric.teamValues.isEmpty {
                ForEach(Array(metric.teamValues.sorted(by: { $0.key < $1.key })), id: \.key) { teamId, value in
                    HStack(spacing: 8) {
                        let teamName = appState.products.first { $0.id == teamId }?.shortName ?? teamId
                        Text(teamName).font(.caption2).frame(width: 50, alignment: .leading)
                        ProgressView(value: value, total: metric.targetValue)
                            .tint(.accentColor)
                        Text(formatValue(value, unit: metric.unit))
                            .font(.caption2.monospaced())
                    }
                }
            }
        }
    }

    private func formatValue(_ value: Double, unit: MetricUnit) -> String {
        switch unit {
        case .percent: return "\(Int(value))%"
        case .points:  return "\(Int(value)) pts"
        case .count:   return "\(Int(value))"
        case .days:    return "\(Int(value))d"
        case .hours:   return "\(Int(value))h"
        case .ratio:   return "\(Int(value))%"
        }
    }
}
```

### Phase 57F: Sprint Velocity View

Create `BoomiSRE/Sources/Views/Panels/VelocityView.swift`:

A chart-driven view showing story points per sprint per team:

```swift
import SwiftUI
import Charts

struct VelocityView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = VelocityViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sprint Velocity").font(.title2.bold())
                Spacer()
                if vm.isLoading { ProgressView().scaleEffect(0.8) }
                Button { Task { await vm.loadVelocity(appState: appState) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.bordered)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()

            if vm.sprints.isEmpty && !vm.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "chart.bar").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("No sprint data yet").font(.headline).foregroundStyle(.secondary)
                    Text("Configure Jira projects to see velocity trends.")
                        .font(.callout).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Velocity chart — committed vs completed per sprint
                        Chart(vm.sprints.prefix(10)) { sprint in
                            BarMark(x: .value("Sprint", sprint.name),
                                    y: .value("Points", sprint.committed))
                                .foregroundStyle(.blue.opacity(0.3))
                            BarMark(x: .value("Sprint", sprint.name),
                                    y: .value("Points", sprint.completed))
                                .foregroundStyle(.green)
                        }
                        .frame(height: 250)
                        .chartLegend(.visible)

                        // Sprint summary table
                        ForEach(vm.sprints.prefix(10)) { sprint in
                            HStack {
                                Text(sprint.name).font(.callout).frame(width: 120, alignment: .leading)
                                Text(sprint.teamId).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(Int(sprint.completed)) / \(Int(sprint.committed)) pts")
                                        .font(.callout.bold())
                                    let pct = sprint.committed > 0 ? Int((sprint.completed / sprint.committed) * 100) : 0
                                    Text("\(pct)% completion").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear {
            if vm.sprints.isEmpty { Task { await vm.loadVelocity(appState: appState) } }
        }
    }
}
```

### Phase 57G: Gamification — Team Leaderboard & Achievements

Add gamification elements to the Productivity view:

```swift
// In ProductivityView, add a "Team Leaderboard" section:

struct TeamLeaderboard: View {
    let teams: [ProductContext]
    let tracker: ProductivityTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team Leaderboard — This Week").font(.headline)

            // Rank teams by total time saved this week
            // (In practice, you'd need per-team tracking — for now, show app-wide)
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                Text("Your Team").font(.callout.bold())
                Spacer()
                Text(tracker.timeSavedTodayFormatted).font(.callout.bold()).foregroundStyle(.green)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.08)))
        }
    }
}

// Achievements / Badges:
struct Achievement: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let earned: Bool
}

// Example achievements:
// "First ACK" — acknowledged your first alert via the app
// "AI Ninja" — used AI features 50 times
// "Velocity Master" — completed 100% of sprint story points
// "Zero Defect" — zero release incidents for a quarter
// "Cross-Product Hero" — covered on-call for a product that isn't your primary
```

### Phase 57H: Register BPOP and Velocity Views

1. **Add BPOP Dashboard to the sidebar** — either as a sub-tab in an existing section or as its own view:
   - Option A: Add to "My Work" as a "BPOP" sub-tab
   - Option B: Add to the Home feed as a widget
   - Option C: Add to Settings → Productivity alongside the existing analytics

   **Recommended:** Add "BPOP" and "Velocity" as sub-tabs in the Productivity section (Settings → Productivity → [Analytics | BPOP | Velocity])

2. **Add BPOP summary to the Home feed** — a feed item that shows the overall BPOP progress (e.g., "BPOP: 11/15 metrics on track") with a link to the full dashboard.

3. **Persist BPOP metric values** in `~/.boomi_sre_bpop.json` — current values and team breakdowns. Manual entries are saved here. Automatic values are re-fetched but cached.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift test` to verify tests pass.
3. Commit with message: "Add BPOP Dashboard, Sprint Velocity, and Gamified Productivity"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

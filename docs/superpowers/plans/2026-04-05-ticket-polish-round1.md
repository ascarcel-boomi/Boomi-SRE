# Ticket Polish Round 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove content truncation from ticket detail views and add click-to-filter interactivity to ticket charts with aligned status categories.

**Architecture:** View-layer changes to TicketDetailView (frame constraints), a selection callback added to the shared ReportChartView component, and a chart data source change in TodoDashboardViewModel to group by Jira's `statusCategoryName` instead of `TodoCategory`.

**Tech Stack:** SwiftUI, Swift Charts, WKWebView (via MarkdownView)

**Spec:** `docs/superpowers/specs/2026-04-05-ticket-polish-round1-design.md`

**Key rules:**
- Read `CLAUDE.md` at repo root before any work
- DO NOT touch integration auth/configuration code
- MarkdownView (WKWebView) handles its own scrolling — NEVER wrap in ScrollView
- All `extractMarkdownFromADF` copies handle links — keep them in sync
- Use `ViewStyles.swift` design tokens for any UI additions

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Views/Panels/TicketDetailView.swift` | Modify (lines 362, 385) | Remove maxHeight caps on description + comments |
| `Views/Charts/ReportChartView.swift` | Modify (full file) | Add optional `onSelect` callback + tap handling to pie, bar, stacked bar |
| `ViewModels/TodoDashboardViewModel.swift` | Modify (lines 335-360) | Replace TodoCategory grouping with statusCategoryName grouping |
| `Views/Panels/TodoDashboardView.swift` | Modify (lines 137-158) | Wire `onSelect` to set status/priority filters |

All paths relative to `BoomiSRE/Sources/`.

---

### Task 1: Remove TicketDetailView Content Truncation

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift:362,385`

- [ ] **Step 1: Remove description maxHeight cap**

In `TicketDetailView.swift`, change line 362 from:

```swift
                MarkdownView(markdown: d.description, appTheme: appState.appTheme)
                    .frame(minHeight: 80, maxHeight: 500)
                    .frame(maxWidth: .infinity, alignment: .leading)
```

to:

```swift
                MarkdownView(markdown: d.description, appTheme: appState.appTheme)
                    .frame(minHeight: 80, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, alignment: .leading)
```

- [ ] **Step 2: Remove comments maxHeight cap**

In the same file, change line 385 from:

```swift
                        MarkdownView(markdown: c.bodyText, appTheme: appState.appTheme)
                            .frame(minHeight: 40, maxHeight: 300)
```

to:

```swift
                        MarkdownView(markdown: c.bodyText, appTheme: appState.appTheme)
                            .frame(minHeight: 40, maxHeight: .infinity)
```

- [ ] **Step 3: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Views/Panels/TicketDetailView.swift
git commit -m "fix: remove maxHeight truncation from ticket description and comments"
```

---

### Task 2: Add Selection Callback to ReportChartView

**Files:**
- Modify: `BoomiSRE/Sources/Views/Charts/ReportChartView.swift`

- [ ] **Step 1: Add onSelect property and selection state**

Add the callback property and state after the existing `section` property (line 6):

```swift
struct ReportChartView: View {
    let section: ResultSection
    var onSelect: ((String) -> Void)? = nil

    @State private var selectedLabel: String? = nil
```

- [ ] **Step 2: Add selection opacity helper**

Add this helper after the existing `formatCompact` method (after line 208):

```swift
    private func opacity(for label: String) -> Double {
        guard let selected = selectedLabel else { return 1.0 }
        return label == selected ? 1.0 : 0.4
    }

    private func handleTap(_ label: String) {
        if selectedLabel == label {
            selectedLabel = nil
            onSelect?("")
        } else {
            selectedLabel = label
            onSelect?(label)
        }
    }
```

- [ ] **Step 3: Add tap handling to pieChart**

Replace the `pieChart` computed property (lines 150-170) with:

```swift
    private var pieChart: some View {
        Chart(chartRows) { row in
            SectorMark(
                angle: .value("Value", row.value),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value("Category", row.label))
            .cornerRadius(4)
            .opacity(opacity(for: row.label))
            .annotation(position: .overlay) {
                let pct = row.value / chartRows.reduce(0) { $0 + $1.value } * 100
                if pct > 5 {
                    Text(String(format: "%.0f%%", pct))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .chartLegend(position: .trailing, alignment: .top)
        .frame(minHeight: 350)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotRect = geo[plotFrame]
                        let center = CGPoint(x: plotRect.midX, y: plotRect.midY)
                        let dx = location.x - center.x
                        let dy = location.y - center.y
                        let distance = sqrt(dx * dx + dy * dy)
                        let outerRadius = min(plotRect.width, plotRect.height) / 2
                        let innerRadius = outerRadius * 0.5
                        guard distance >= innerRadius && distance <= outerRadius else { return }

                        var angle = atan2(dy, dx) * 180 / .pi
                        angle = (angle - 90).truncatingRemainder(dividingBy: 360)
                        if angle < 0 { angle += 360 }

                        let total = chartRows.reduce(0.0) { $0 + $1.value }
                        var cumulative = 0.0
                        for row in chartRows {
                            let sliceAngle = row.value / total * 360
                            if angle >= cumulative && angle < cumulative + sliceAngle {
                                handleTap(row.label)
                                return
                            }
                            cumulative += sliceAngle
                        }
                    }
            }
        }
    }
```

- [ ] **Step 4: Add tap handling to barChart**

Replace the `barChart` computed property (lines 49-80) with:

```swift
    private var barChart: some View {
        Chart(chartRows) { row in
            if hasGroups {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(by: .value("Group", row.group))
                .position(by: .value("Group", row.group))
                .opacity(opacity(for: row.label))
            } else {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
                .opacity(opacity(for: row.label))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotOrigin = geo[plotFrame].origin
                        let plotWidth = geo[plotFrame].width
                        let uniqueLabels = chartRows.map(\.label).uniqued()
                        let barWidth = plotWidth / CGFloat(uniqueLabels.count)
                        let relativeX = location.x - plotOrigin.x
                        let index = Int(relativeX / barWidth)
                        if index >= 0 && index < uniqueLabels.count {
                            handleTap(uniqueLabels[index])
                        }
                    }
            }
        }
    }
```

Note: `uniqued()` may not exist. If it doesn't compile, replace with:
```swift
let uniqueLabels = Array(NSOrderedSet(array: chartRows.map(\.label))) as! [String]
```

- [ ] **Step 5: Add tap handling to stackedBarChart**

Replace the `stackedBarChart` computed property (lines 174-197) with:

```swift
    private var stackedBarChart: some View {
        Chart(chartRows) { row in
            if hasGroups {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(by: .value("Group", row.group))
                .opacity(opacity(for: row.label))
            } else {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
                .opacity(opacity(for: row.label))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotOrigin = geo[plotFrame].origin
                        let plotWidth = geo[plotFrame].width
                        let uniqueLabels = Array(NSOrderedSet(array: chartRows.map(\.label))) as! [String]
                        let barWidth = plotWidth / CGFloat(uniqueLabels.count)
                        let relativeX = location.x - plotOrigin.x
                        let index = Int(relativeX / barWidth)
                        if index >= 0 && index < uniqueLabels.count {
                            handleTap(uniqueLabels[index])
                        }
                    }
            }
        }
    }
```

- [ ] **Step 6: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: `Build complete!`

If `uniqued()` causes a compile error, apply the `NSOrderedSet` fallback from Step 4.

- [ ] **Step 7: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Views/Charts/ReportChartView.swift
git commit -m "feat: add optional click-to-select to ReportChartView (pie, bar, stacked bar)"
```

---

### Task 3: Replace Chart Category Grouping with Status Grouping

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/TodoDashboardViewModel.swift:335-360`

- [ ] **Step 1: Replace buildChartSections category grouping with status grouping**

Replace the `buildChartSections` method (lines 335-360) with:

```swift
    private func buildChartSections(from source: [TodoItem]) -> [ResultSection] {
        let byPriority = Dictionary(grouping: source, by: \.priority).map { (key, val) in
            ResultRow(label: key, value: Double(val.count))
        }.sorted { $0.value > $1.value }

        let prioritySection = ResultSection(
            title: "By Priority", rows: byPriority, chartHint: .pie
        )

        let statusOrder = ["To Do", "In Progress", "Done"]
        var statusRows: [ResultRow] = []
        for statusCat in statusOrder {
            let statusItems = source.filter { $0.statusCategoryName == statusCat }
            let byPri = Dictionary(grouping: statusItems, by: \.priority)
            for (pri, priItems) in byPri {
                statusRows.append(ResultRow(
                    label: statusCat, value: Double(priItems.count), group: pri
                ))
            }
        }

        let statusSection = ResultSection(
            title: "By Status", rows: statusRows, chartHint: .stackedBar
        )

        return [statusSection, prioritySection]
    }
```

- [ ] **Step 2: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/ViewModels/TodoDashboardViewModel.swift
git commit -m "feat: align chart categories with status filter (To Do / In Progress / Done)"
```

---

### Task 4: Wire Chart Selection to TodoDashboardView Filters

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift:137-158`

- [ ] **Step 1: Replace chartRow to pass onSelect callbacks**

Replace the `chartRow` computed property (lines 137-158) with:

```swift
    private var chartRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.filteredChartSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ReportChartView(section: section, onSelect: { label in
                            if section.title == "By Status" {
                                if label.isEmpty || viewModel.statusFilter.rawValue == label {
                                    viewModel.statusFilter = .all
                                } else if let match = TicketStatusFilter.allCases.first(where: { $0.rawValue == label }) {
                                    viewModel.statusFilter = match
                                }
                            } else if section.title == "By Priority" {
                                if label.isEmpty || viewModel.priorityFilter.rawValue == label {
                                    viewModel.priorityFilter = .all
                                } else if let match = TicketPriorityFilter.allCases.first(where: { $0.rawValue == label }) {
                                    viewModel.priorityFilter = match
                                }
                            }
                        })
                        .frame(width: 340, height: 220)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, DesignTokens.panelPadding)
            .padding(.vertical, 8)
        }
        .frame(height: 270)
        .background(Color(nsColor: .controlBackgroundColor))
    }
```

- [ ] **Step 2: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift
git commit -m "feat: wire chart click-to-filter in TodoDashboardView"
```

---

### Task 5: Verify All Changes End-to-End

- [ ] **Step 1: Full build**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -10`
Expected: `Build complete!` with no warnings in changed files.

- [ ] **Step 2: Verify existing callers unaffected**

Grep for all ReportChartView usages and confirm no compile errors:

```bash
cd ~/github/Boomi-SRE && grep -rn "ReportChartView" BoomiSRE/Sources/
```

Expected: BoardsView.swift, SavedFiltersView.swift, TodoDashboardView.swift all compile. BoardsView and SavedFiltersView don't pass `onSelect` — they get `nil` default.

- [ ] **Step 3: Commit any fixups if needed**

Only if Steps 1-2 revealed issues. Otherwise skip.

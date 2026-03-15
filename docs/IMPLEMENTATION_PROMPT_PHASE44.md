# Boomi SRE App — Phase 44: Dashboard Reset — Simple Grid Layout

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first (you will be rewriting large portions of them):**
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `DashboardWidget` model (SIMPLIFY)
- `BoomiSRE/Sources/Views/DashboardView.swift` — dashboard layout and `DashboardCustomizeView` (REWRITE)
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `WidgetCard` and all widget views (SIMPLIFY)
- `BoomiSRE/Sources/Models/AppState.swift` — `dashboardWidgets`, `dashboardMode`, `dashboardColumns`

---

## Philosophy

The current dashboard is over-engineered with column spans, drag-to-resize corners, S/M/L sizing, and complex AI layout management. None of it works well. We're stripping it all out and replacing it with a simple system that actually works.

**New rules:**
1. All widgets are the **same width** — exactly one column wide. No variable sizing.
2. User picks **column count** (1, 2, 3, or 4). Widgets flow into the grid left-to-right, top-to-bottom.
3. User **drags to reorder** widgets — simple up/down reordering.
4. User **toggles visibility** — show or hide each widget.
5. **AI auto mode** just reorders by urgency. Same sizes, same columns. Just smarter ordering.
6. Widget content adapts to available width naturally (wider in 2-col, narrower in 4-col).

That's the entire system. No S/M/L. No column spans. No resize handles. No complexity.

---

## Implementation

### Phase 44A: Simplify the Widget Model

**Rewrite `WidgetModels.swift`:**

```swift
import Foundation

enum WidgetType: String, Codable, CaseIterable {
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts, awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary
    case notifications, onCallSchedule

    var title: String {
        // ... keep existing switch — no changes needed
    }

    var icon: String {
        // ... keep existing switch — no changes needed
    }

    // Remove hasFilters for now — can add back later
}

struct DashboardWidget: Identifiable, Codable, Equatable {
    var id: UUID
    var type: WidgetType
    var position: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), type: WidgetType, position: Int, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.position = position
        self.isEnabled = isEnabled
    }

    static func == (lhs: DashboardWidget, rhs: DashboardWidget) -> Bool {
        lhs.id == rhs.id
    }
}

extension DashboardWidget {
    static var defaults: [DashboardWidget] {
        [
            DashboardWidget(type: .activeIncidents,  position: 0),
            DashboardWidget(type: .jsmOpsAlerts,     position: 1),
            DashboardWidget(type: .grafanaAlerts,    position: 2),
            DashboardWidget(type: .onCallSchedule,   position: 3),
            DashboardWidget(type: .notifications,    position: 4),
            DashboardWidget(type: .myTickets,        position: 5),
            DashboardWidget(type: .jenkinsBuilds,    position: 6),
            DashboardWidget(type: .recentPRs,        position: 7),
            DashboardWidget(type: .serviceHealth,    position: 8),
            DashboardWidget(type: .quickActions,     position: 9),
            DashboardWidget(type: .upcomingCalendar, position: 10),
            DashboardWidget(type: .unreadEmails,     position: 11),
            DashboardWidget(type: .awsCostTrend,     position: 12),
            DashboardWidget(type: .confluenceRecent, position: 13),
            DashboardWidget(type: .aiDailySummary,   position: 14),
        ]
    }
}
```

**Remove entirely:**
- `WidgetSize` enum — delete it
- `columnSpan` property — delete it
- `size` property — delete it
- `effectiveSize` computed property — delete it
- `customDefaults` and `customDefaultColumns` from AppState — delete them

**Keep in AppState:**
- `dashboardWidgets: [DashboardWidget]` — simplified (no size/span)
- `dashboardMode: String` — "auto" or "custom"
- `dashboardColumns: Int` — 1, 2, 3, or 4 (default: 3)

**Handle old saved configs:** When loading, if the decoded widget has extra fields (`size`, `columnSpan`), they'll just be ignored by the new simpler struct since they're not declared. Codable will skip unknown keys if you use a custom decoder or just let the defaults work. If the old config causes decode failures, catch the error and fall back to `DashboardWidget.defaults`.

### Phase 44B: Rewrite the Dashboard Grid

**Replace the entire `widgetGrid` in `DashboardView` with a simple `LazyVGrid`:**

```swift
private var widgetGrid: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 16),
                        count: appState.dashboardColumns)

    LazyVGrid(columns: columns, spacing: 16) {
        ForEach(enabledWidgets) { widget in
            widgetView(for: widget)
        }
    }
}
```

That's the entire grid. No row packing, no span calculations, no complex layout engine. SwiftUI's `LazyVGrid` handles everything.

**Update `enabledWidgets`:**
```swift
var enabledWidgets: [DashboardWidget] {
    if appState.dashboardMode == "auto" {
        return autoWidgets()
    }
    return appState.dashboardWidgets
        .filter(\.isEnabled)
        .sorted { $0.position < $1.position }
}
```

**Update `autoWidgets()` — just reorder by urgency:**
```swift
private func autoWidgets() -> [DashboardWidget] {
    // Start with ALL widget types (not the user's custom list)
    let allTypes = WidgetType.allCases

    // Filter out unconfigured services
    let configured = allTypes.filter { widgetIsConfigured($0) }

    // Score by urgency and sort
    let sorted = configured
        .map { (type: $0, urgency: urgencyScore(for: $0)) }
        .sorted { $0.urgency > $1.urgency }

    // Build widget list — all enabled, ordered by urgency
    return sorted.enumerated().map { idx, pair in
        DashboardWidget(type: pair.type, position: idx, isEnabled: true)
    }
}

private func widgetIsConfigured(_ type: WidgetType) -> Bool {
    switch type {
    case .recentPRs: return !appState.githubToken.isEmpty
    case .jenkinsBuilds: return !appState.jenkinsToken.isEmpty
    case .grafanaAlerts: return !appState.grafanaToken.isEmpty
    case .jsmOpsAlerts, .myTickets, .activeIncidents: return appState.isJiraConfigured
    case .onCallSchedule: return appState.isJiraConfigured && !appState.favoriteJSMTeams.isEmpty
    case .awsCostTrend: return !appState.awsSSOProfile.isEmpty
    case .upcomingCalendar, .unreadEmails: return appState.googleCredentials != nil
    case .confluenceRecent: return !appState.confluenceAPIToken.isEmpty
    default: return true
    }
}
```

Keep the existing `urgencyScore(for:)` function — it works fine for ordering.

### Phase 44C: Simplify All Widget Views

**Remove the `size: WidgetSize` parameter from every widget view.** Each widget should render its content at whatever width it gets — no size switching.

**Simplify `WidgetCard`:**
```swift
struct WidgetCard<Content: View>: View {
    let type: WidgetType
    var navigateTo: String? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            if let nav = navigateTo {
                appState.selectedReport = ReportCatalog.all.first { $0.id == nav }
                appState.showSettings = false
                appState.selectedTicketKey = nil
            }
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: type.icon).foregroundStyle(.secondary)
                    Text(type.title).font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    if navigateTo != nil {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                // Content
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
```

**No resize handles. No drag handles on hover. No isEditable flag. No size parameter. No onResize callback.** Just a clean card.

**Update each widget view** — remove the `size: WidgetSize` parameter and the `switch size` blocks. Each widget should show a reasonable amount of content:
- Title/header with count
- Up to 5-6 items
- "View all →" if more items exist

The content naturally adapts to the card width because the card fills one grid column.

### Phase 44D: Rewrite DashboardCustomizeView — Dead Simple

**The entire Customize popup should be:**

```swift
struct DashboardCustomizeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Customize Dashboard").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Mode + Columns
            HStack(spacing: 20) {
                Picker("Mode", selection: $appState.dashboardMode) {
                    Text("Auto").tag("auto")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: appState.dashboardMode) { appState.saveConfig() }

                Picker("Columns", selection: $appState.dashboardColumns) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: appState.dashboardColumns) { appState.saveConfig() }

                Spacer()

                Button("Reset") {
                    appState.dashboardWidgets = DashboardWidget.defaults
                    appState.dashboardColumns = 3
                    appState.dashboardMode = "auto"
                    appState.saveConfig()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal).padding(.vertical, 10)

            Divider()

            if appState.dashboardMode == "auto" {
                // Auto mode explanation
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI manages your dashboard automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Widgets are sorted by urgency — critical items at the top, calm items at the bottom. The column count above still applies.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
                Spacer()
            } else {
                // Custom mode: simple reorderable list with toggles
                List {
                    ForEach($appState.dashboardWidgets
                        .sorted(by: { $0.position.wrappedValue < $1.position.wrappedValue }),
                        id: \.id) { $widget in
                        HStack(spacing: 12) {
                            Image(systemName: widget.type.icon)
                                .foregroundStyle(widget.isEnabled ? .accentColor : .secondary)
                                .frame(width: 20)
                            Text(widget.type.title)
                                .foregroundStyle(widget.isEnabled ? .primary : .secondary)
                            Spacer()
                            Toggle("", isOn: $widget.isEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: widget.isEnabled) { appState.saveConfig() }
                        }
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
            }
        }
        .frame(minWidth: 420, minHeight: 500)
    }
}
```

**That's the entire Customize view.** Mode picker, column picker, reset button, and a drag-reorderable list with toggles. No S/M/L. No column spans. No bulk actions. No complexity.

### Phase 44E: Clean Up Dashboard Header

The dashboard header should be clean:

```swift
HStack(alignment: .firstTextBaseline) {
    VStack(alignment: .leading, spacing: 2) {
        Text(greeting).font(.title.bold())
        Text(Date(), style: .date).font(.callout).foregroundStyle(.secondary)
    }
    Spacer()
    if vm.isLoading { ProgressView().scaleEffect(0.8) }
    Button {
        Task { await vm.refreshAll(appState: appState, notificationVM: notificationVM) }
    } label: {
        Image(systemName: "arrow.clockwise")
    }
    .buttonStyle(.plain).help("Refresh")
    Button {
        showCustomize = true
    } label: {
        Label("Customize", systemImage: "slider.horizontal.3")
    }
    .buttonStyle(.bordered)
}
```

**No column picker in the header** — it's in the Customize popup. Keep the header clean.

### Phase 44F: Remove Dead Code

Search the entire codebase and remove:
- All references to `WidgetSize` (the enum itself and every usage)
- All references to `columnSpan`
- All references to `effectiveSize`
- All references to `onResize` callback in WidgetCard and widget views
- All references to `isEditable` in WidgetCard
- All references to `customDefaults` and `customDefaultColumns` in AppState
- The `widgetRows()` function
- The `WidgetDropDelegate` struct (drag-and-drop between widgets on the dashboard itself — not needed with LazyVGrid, reordering happens in the Customize popup)
- Any resize gesture code
- The `layoutWidgetsIntoRows()` function

Make sure `swift build` still compiles after removing each piece.

### Phase 44G: Auto-Migrate Old Configs

In `AppState.loadConfig()`, handle the old config format gracefully:
- If `dashboardWidgets` fails to decode (because old configs have `size` and `columnSpan` fields that no longer exist), catch the error and fall back to `DashboardWidget.defaults`
- Ensure new widget types are added (the migration from Phase 41A should still work)
- If `dashboardColumns` is missing, default to 3

```swift
// In loadConfig:
if let data = config.dashboardWidgets {
    dashboardWidgets = data
} else {
    dashboardWidgets = DashboardWidget.defaults
}
// Ensure all widget types present
let existing = Set(dashboardWidgets.map(\.type))
var nextPos = (dashboardWidgets.map(\.position).max() ?? -1) + 1
for def in DashboardWidget.defaults where !existing.contains(def.type) {
    dashboardWidgets.append(DashboardWidget(type: def.type, position: nextPos))
    nextPos += 1
}
```

If the `DashboardWidget` decoder fails because of old fields, add a custom `init(from decoder:)` that ignores unknown keys:
```swift
extension DashboardWidget: Codable {
    enum CodingKeys: String, CodingKey {
        case id, type, position, isEnabled
    }
    // This automatically ignores size, columnSpan, etc. from old configs
}
```

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Dashboard reset — simple grid layout, remove sizing complexity"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

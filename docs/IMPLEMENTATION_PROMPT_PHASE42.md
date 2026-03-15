# Boomi SRE App — Phase 42: Dashboard Grid Redesign — Drag-Resize, Column Layout & Custom Defaults

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Models/WidgetModels.swift` — `DashboardWidget` model (currently has `size: WidgetSize` with S/M/L)
- `BoomiSRE/Sources/Views/DashboardView.swift` — dashboard layout, widget grid, customize sheet
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `WidgetCard` and all widget views (accept `size: WidgetSize`)
- `BoomiSRE/Sources/Models/AppState.swift` — `dashboardWidgets`, `dashboardMode`, `dashboardColumns` (add if missing)

---

## New Design

Replace the S/M/L size system with a **grid-based layout** where widgets can span multiple columns and the user can drag to resize.

### Concept:
- The dashboard is a **grid with configurable columns** (2, 3, or 4)
- Each widget occupies a **column span** (1 to maxColumns) — this replaces S/M/L
  - span 1 = small (like S), span 2 = medium (like M in a 4-col grid), span = maxColumns = full-width (like L)
- Widgets are laid out top-to-bottom, left-to-right, filling the grid row by row
- Users **drag the bottom-right corner** of any widget to resize its column span
- Users **drag the widget title bar** to reorder
- The Customize Dashboard popup shows the **same grid layout** as the dashboard itself — it's a live preview

---

## Implementation

### Phase 42A: Update the Widget Model

Replace `WidgetSize` with a column span system:

```swift
// Keep WidgetSize for backward compatibility with saved configs,
// but add columnSpan as the primary sizing mechanism.

struct DashboardWidget: Identifiable, Codable {
    var id: UUID
    var type: WidgetType
    var position: Int
    var size: WidgetSize          // keep for backward compat
    var columnSpan: Int           // NEW: how many grid columns this widget spans (1...maxColumns)
    var isEnabled: Bool

    init(id: UUID = UUID(), type: WidgetType, position: Int,
         size: WidgetSize = .medium, columnSpan: Int = 1, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.position = position
        self.size = size
        self.columnSpan = columnSpan
        self.isEnabled = isEnabled
    }

    /// Convert columnSpan to WidgetSize for widget views that use size
    var effectiveSize: WidgetSize {
        switch columnSpan {
        case 1: return .small
        case 2: return .medium
        default: return .large
        }
    }
}
```

Add `dashboardColumns` to `AppState` (persisted):
```swift
@Published var dashboardColumns: Int = 3   // 2, 3, or 4
```

Update `DashboardWidget.defaults` to use `columnSpan`:
```swift
static func defaults(columns: Int = 3) -> [DashboardWidget] {
    [
        DashboardWidget(type: .activeIncidents,  position: 0,  columnSpan: columns),  // full width
        DashboardWidget(type: .jsmOpsAlerts,     position: 1,  columnSpan: 2),
        DashboardWidget(type: .grafanaAlerts,    position: 2,  columnSpan: 1),
        DashboardWidget(type: .onCallSchedule,   position: 3,  columnSpan: 1),
        DashboardWidget(type: .notifications,    position: 4,  columnSpan: 1),
        DashboardWidget(type: .myTickets,        position: 5,  columnSpan: 1),
        DashboardWidget(type: .jenkinsBuilds,    position: 6,  columnSpan: 1),
        DashboardWidget(type: .recentPRs,        position: 7,  columnSpan: 1),
        DashboardWidget(type: .serviceHealth,    position: 8,  columnSpan: 1),
        DashboardWidget(type: .quickActions,     position: 9,  columnSpan: 1),
        DashboardWidget(type: .upcomingCalendar, position: 10, columnSpan: 1),
        DashboardWidget(type: .unreadEmails,     position: 11, columnSpan: 1),
        DashboardWidget(type: .awsCostTrend,     position: 12, columnSpan: 1),
        DashboardWidget(type: .confluenceRecent, position: 13, columnSpan: 1),
        DashboardWidget(type: .aiDailySummary,   position: 14, columnSpan: columns),  // full width
    ]
}
```

Handle backward compatibility: if a loaded widget has `columnSpan` of 0 or missing (old config), derive it from `size`:
```swift
// In loadConfig migration:
for i in dashboardWidgets.indices {
    if dashboardWidgets[i].columnSpan == 0 {
        switch dashboardWidgets[i].size {
        case .small: dashboardWidgets[i].columnSpan = 1
        case .medium: dashboardWidgets[i].columnSpan = 2
        case .large: dashboardWidgets[i].columnSpan = dashboardColumns
        }
    }
}
```

### Phase 42B: Grid Layout Engine

Rewrite `widgetGrid` in `DashboardView` to use a proper grid layout:

```swift
private var widgetGrid: some View {
    let columns = appState.dashboardColumns
    let widgets = enabledWidgets

    // Lay out widgets into rows, respecting column spans
    let rows = layoutWidgetsIntoRows(widgets: widgets, columns: columns)

    LazyVStack(spacing: 16) {
        ForEach(rows.indices, id: \.self) { rowIndex in
            HStack(spacing: 16) {
                ForEach(rows[rowIndex], id: \.id) { widget in
                    widgetCell(widget, totalColumns: columns)
                }
                // Fill remaining space if row isn't full
                let usedSpan = rows[rowIndex].reduce(0) { $0 + $1.columnSpan }
                if usedSpan < columns {
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Pack widgets into rows, greedy bin-packing by column span
private func layoutWidgetsIntoRows(widgets: [DashboardWidget], columns: Int) -> [[DashboardWidget]] {
    var rows: [[DashboardWidget]] = []
    var currentRow: [DashboardWidget] = []
    var currentSpan = 0

    for widget in widgets {
        let span = min(widget.columnSpan, columns)  // clamp to max columns
        if currentSpan + span > columns {
            // Current row is full, start a new one
            if !currentRow.isEmpty { rows.append(currentRow) }
            currentRow = [widget]
            currentSpan = span
        } else {
            currentRow.append(widget)
            currentSpan += span
        }
    }
    if !currentRow.isEmpty { rows.append(currentRow) }
    return rows
}
```

Each widget cell uses `frame` proportional to its span:
```swift
@ViewBuilder
private func widgetCell(_ widget: DashboardWidget, totalColumns: Int) -> some View {
    let spanRatio = CGFloat(widget.columnSpan) / CGFloat(totalColumns)
    // Use GeometryReader or flexible frames
    widgetView(for: widget)
        .frame(maxWidth: .infinity) // Each widget fills its allocated space
        // The HStack distributes space naturally when widgets have the right flex
}
```

Actually, the simplest approach: use `GridItem` with `.flexible()` and let widgets specify how many grid items they span. SwiftUI's `LazyVGrid` doesn't natively support column spanning, so the `HStack`-per-row approach above is better.

### Phase 42C: Drag-to-Resize Widget Corners

Add a resize handle to the bottom-right corner of each `WidgetCard`:

```swift
// In WidgetCard, add a resize handle overlay:
.overlay(alignment: .bottomTrailing) {
    if isHovering {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(6)
            .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Calculate new column span based on drag distance
                        let threshold: CGFloat = 100  // pixels per column
                        let delta = Int(value.translation.width / threshold)
                        let currentSpan = widgetColumnSpan
                        let newSpan = max(1, min(maxColumns, currentSpan + delta))
                        if newSpan != currentSpan {
                            onResize?(newSpan)
                        }
                    }
            )
            .cursor(.resizeLeftRight)
    }
}
```

Add `onResize` callback to `WidgetCard`:
```swift
var onResize: ((Int) -> Void)? = nil
var widgetColumnSpan: Int = 1
var maxColumns: Int = 3
```

In `DashboardView`, pass the resize handler:
```swift
WidgetCard(type: widget.type, size: widget.effectiveSize,
           widgetColumnSpan: widget.columnSpan,
           maxColumns: appState.dashboardColumns,
           navigateTo: "...",
           onResize: { newSpan in
               if let idx = appState.dashboardWidgets.firstIndex(where: { $0.id == widget.id }) {
                   appState.dashboardWidgets[idx].columnSpan = newSpan
                   appState.saveConfig()
               }
           }) {
    // widget content
}
```

### Phase 42D: Column Count Selector

Add a column count picker to the dashboard header (next to the Customize button):

```swift
// In the dashboard header HStack:
Picker("", selection: $appState.dashboardColumns) {
    Image(systemName: "rectangle.split.1x2").tag(2)
    Image(systemName: "rectangle.split.3x1").tag(3)
    Image(systemName: "rectangle.split.3x3").tag(4)
}
.pickerStyle(.segmented)
.frame(width: 120)
.onChange(of: appState.dashboardColumns) {
    // Clamp any widget spans that exceed the new column count
    for i in appState.dashboardWidgets.indices {
        if appState.dashboardWidgets[i].columnSpan > appState.dashboardColumns {
            appState.dashboardWidgets[i].columnSpan = appState.dashboardColumns
        }
    }
    appState.saveConfig()
}
```

Also add it to the Customize Dashboard popup header area.

### Phase 42E: Save Custom Defaults

Let the user save their current layout as their personal default:

1. **Add `customDefaults` to AppState** (persisted separately):
   ```swift
   @Published var customDefaults: [DashboardWidget]? = nil  // nil = use system defaults
   @Published var customDefaultColumns: Int? = nil
   ```

2. **"Save as My Default" button** in the Customize Dashboard popup:
   ```swift
   Button("Save as My Default") {
       appState.customDefaults = appState.dashboardWidgets
       appState.customDefaultColumns = appState.dashboardColumns
       appState.saveConfig()
       savedFeedback = true  // show brief "Saved ✓" feedback
   }
   .buttonStyle(.borderedProminent)
   ```

3. **"Reset to Defaults" uses custom defaults first:**
   ```swift
   Button("Reset to Defaults") {
       if let custom = appState.customDefaults {
           appState.dashboardWidgets = custom
           if let cols = appState.customDefaultColumns {
               appState.dashboardColumns = cols
           }
       } else {
           appState.dashboardWidgets = DashboardWidget.defaults(columns: appState.dashboardColumns)
       }
       appState.saveConfig()
   }
   ```

4. **"Reset to Factory Defaults"** — a separate button that ignores custom defaults and uses the system defaults:
   ```swift
   Button("Reset to Factory Defaults") {
       appState.customDefaults = nil
       appState.customDefaultColumns = nil
       appState.dashboardWidgets = DashboardWidget.defaults(columns: appState.dashboardColumns)
       appState.saveConfig()
   }
   .buttonStyle(.bordered)
   .foregroundStyle(.red)
   ```

5. **Show which defaults are active:**
   ```
   [Save as My Default]  [Reset to Defaults]  [Reset to Factory Defaults]
   Currently using: My saved defaults (saved Mar 15, 2026)
   ```
   Or: "Currently using: Factory defaults"

### Phase 42F: Redesign the Customize Dashboard Popup

The popup should now mirror the actual grid layout instead of showing a flat list:

1. **Top section** (compact, fixed):
   - Dashboard Mode picker (Auto / Custom)
   - Column count picker (2 / 3 / 4)
   - Bulk actions: Enable All, Disable All
   - Save/Reset buttons

2. **Bottom section** (fills remaining space):
   - **In Custom mode:** Show a miniature grid preview matching the dashboard layout. Each widget is a small card showing:
     - Icon + title
     - A toggle (visible/hidden)
     - The card's width reflects its column span
     - Drag the card to reorder
     - Drag the right edge of the card to resize (change column span)
   - **In Auto mode:** Show the AI priority list (existing behavior, but also as a mini grid preview)

3. **The popup should be wide enough** to show the grid preview comfortably. Use `.frame(minWidth: 700, minHeight: 600)` for a 3-column grid.

4. **Widget cards in the customizer** should be interactive:
   - Click to toggle enabled/disabled (with visual dimming for disabled)
   - Drag to reorder
   - Drag right edge to resize column span
   - Show a tooltip on hover with the widget's current data count (e.g., "3 alerts")

### Phase 42G: Update Widget Views for the New Sizing

All widget views currently accept `size: WidgetSize`. Update them to also work with `columnSpan`:

1. In `widgetView(for:)`, pass `widget.effectiveSize` (derived from `columnSpan`):
   ```swift
   // effectiveSize is computed from columnSpan:
   // span 1 = .small, span 2 = .medium, span >= 3 = .large
   ```

2. The widget content should adapt to the available width, not just S/M/L. Use `GeometryReader` or let the content naturally flow based on the frame width. Widgets with `columnSpan = 1` should show compact content; widgets spanning the full width should show full detail.

3. The transition between sizes should feel smooth — when the user drags to resize, the content should adapt immediately.

---

## General Guidelines

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit all changes with a descriptive message.
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

- The grid layout should feel natural — like arranging widgets on a real dashboard
- Drag-to-resize should have clear visual feedback (cursor change, outline showing the new size)
- The column count change should immediately reflow all widgets
- Keep backward compatibility: old configs with S/M/L sizes should auto-migrate to columnSpan

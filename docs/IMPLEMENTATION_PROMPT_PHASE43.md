# Boomi SRE App — Phase 43: Hide Manual Controls in Auto Mode & Fix Column Picker Icons

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/DashboardView.swift` — dashboard header (column picker at line ~184), widget grid with resize handles, `DashboardCustomizeView` (column picker at line ~571, bulk actions, sizing controls)
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `WidgetCard` with resize handle and drag handle overlays on hover

---

## Problem 1: Auto mode shows manual controls that don't work

When `appState.dashboardMode == "auto"`, the user still sees:
- Column count picker (2/3/4) in the dashboard header and in the Customize popup
- Resize handles on widget corners (hover shows drag-to-resize)
- Drag-to-reorder handles on widgets
- Bulk action buttons (Enable All, Disable All, All 1, All 2, Full) in Customize popup
- "Save as My Default" button in Customize popup

This is confusing — the user tries to interact with these controls and nothing happens, or it gets overridden by the AI.

**Principle:** Auto mode = the AI controls everything. The user should only see the mode picker (to switch to Custom) and the AI's explanation of what it's doing.

## Problem 2: Column picker icons don't represent vertical columns

Current icons:
- `rectangle.split.1x2` for 2 columns — shows 2 horizontal ROWS, not columns
- `rectangle.split.3x1` for 3 columns — shows 3 horizontal rows
- `rectangle.split.3x3` for 4 columns — shows a 3×3 grid, not 4 columns

---

## Fix

### Phase 43A: Hide Manual Controls in Auto Mode — Dashboard Header

In `DashboardView`, find the dashboard header `HStack` (around line 160-200). Wrap the column count picker with a condition:

```swift
if appState.dashboardMode != "auto" {
    Picker("Columns", selection: $appState.dashboardColumns) {
        // ...column options...
    }
    // ...
}
```

In Auto mode, the header should just show: Greeting, date, refresh button, and Customize button. No column picker.

### Phase 43B: Hide Manual Controls in Auto Mode — Widget Cards

In `WidgetCard` (in `WidgetViews.swift`), the resize handle and drag handle show on hover. These should only appear in Custom mode.

Pass a `isEditable: Bool` parameter to `WidgetCard`:
```swift
struct WidgetCard<Content: View>: View {
    // ... existing properties ...
    var isEditable: Bool = true   // false in Auto mode
}
```

Wrap the hover overlays:
```swift
// Resize handle — only in Custom mode
.overlay(alignment: .bottomTrailing) {
    if isHovering && isEditable {
        // resize handle...
    }
}

// Drag handle — only in Custom mode
.overlay(alignment: .leading) {
    if isHovering && isEditable {
        // drag handle...
    }
}
```

In `DashboardView.widgetView(for:)`, pass `isEditable`:
```swift
WidgetCard(type: widget.type, size: sz,
           isEditable: appState.dashboardMode != "auto",
           onResize: appState.dashboardMode == "auto" ? nil : { ... },
           // ...
)
```

Also disable the `.onDrag` modifier on widgets in Auto mode:
```swift
// In draggableWidget():
if appState.dashboardMode != "auto" {
    widgetView(for: widget, onResize: resizeHandler)
        .onDrag { ... }
        .onDrop(...)
} else {
    widgetView(for: widget, onResize: nil)
    // No drag/drop in auto mode
}
```

### Phase 43C: Hide Manual Controls in Auto Mode — Customize Popup

In `DashboardCustomizeView`, when mode is "auto":
- Show the mode picker (Auto / Custom) — always visible
- Show the AI priority explanation (`autoModeExplanation`) — already exists
- Do NOT show: column picker, bulk action buttons, Save as My Default, widget list with toggles/sizing

When mode is "custom":
- Show everything: column picker, bulk actions, widget list, Save/Reset buttons

Structure:
```swift
var body: some View {
    VStack(spacing: 0) {
        // Header — always visible
        HStack {
            Text("Customize Dashboard").font(.headline)
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.escape)
        }
        .padding()
        Divider()

        // Mode picker — always visible
        Picker("Dashboard Mode", selection: $appState.dashboardMode) {
            Text("Auto (AI-managed)").tag("auto")
            Text("Custom").tag("custom")
        }
        .pickerStyle(.radioGroup)
        .padding(.horizontal)
        .padding(.top, 12)
        .onChange(of: appState.dashboardMode) { appState.saveConfig() }

        if appState.dashboardMode == "auto" {
            // Auto mode: just show the AI explanation, filling the space
            autoModeExplanation
                .padding()
            Spacer()
        } else {
            // Custom mode: all the controls
            customModeContent
        }
    }
}
```

### Phase 43D: Fix Column Picker Icons

Replace the wrong SF Symbol names in BOTH the dashboard header AND the Customize popup. Use clear text labels since SF Symbols for vertical column layouts are unreliable:

```swift
Picker("Columns", selection: $appState.dashboardColumns) {
    Text("2 Col").tag(2)
    Text("3 Col").tag(3)
    Text("4 Col").tag(4)
}
.pickerStyle(.segmented)
.frame(width: 180)
.help("Number of widget columns on the dashboard")
```

Find and replace in BOTH locations (dashboard header ~line 184 and Customize popup ~line 571).

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Hide manual layout controls in Auto mode, fix column picker icons"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

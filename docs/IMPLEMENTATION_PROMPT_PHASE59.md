# Boomi SRE App — Phase 59: Fix Trust Icon & Inline BPOP Metric Editing

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Models/BPOPModels.swift` — `BPOPPillar` enum with icon property (line 18: Trust uses `shield.checkmark` which doesn't exist)
- `BoomiSRE/Sources/Views/Panels/BPOPDashboardView.swift` — BPOP dashboard with `isEditing` toggle, `editingMetric` sheet, `editSheet()` function, `loadSavedValues()`, `saveValues()`

---

## Bug 1: Trust Pillar Has No Icon

Line 18 of `BPOPModels.swift`: `case .trust: return "shield.checkmark"`

The SF Symbol `shield.checkmark` does not exist on macOS 15. The Trust pillar shows a blank circle in the UI. The correct SF Symbol name is `checkmark.shield` (SF Symbols uses the pattern `action.object`, not `object.action`).

**Fix:** Change line 18:
```swift
// Old:
case .trust:    return "shield.checkmark"
// New:
case .trust:    return "checkmark.shield"
```

---

## Bug 2: Edit Values UX Is Too Many Clicks

Currently the user has to:
1. Click "Edit Values" to toggle edit mode
2. Click a tiny pencil icon on each individual metric
3. Enter the value in a separate sheet popup
4. Click "Save" in the sheet
5. Repeat for each of 15 metrics

That's ~60 clicks to enter all 15 values. It should be ~15 (one per metric).

**Fix:** When "Edit Values" is toggled on, show an **inline text field** next to each metric's target value directly in the metric row — no sheet needed.

1. Find the metric row code in `BPOPDashboardView.swift` (around line 200) where `if isEditing` shows the pencil button. Replace the pencil button with an inline `TextField`:

```swift
// Replace the pencil icon + sheet approach with:
if isEditing {
    TextField("Value", text: Binding(
        get: { metric.currentValue.map { String(format: "%g", $0) } ?? "" },
        set: { newText in
            if let idx = metrics.firstIndex(where: { $0.id == metric.id }) {
                metrics[idx].currentValue = Double(newText)
                saveValues()
            }
        }
    ))
    .textFieldStyle(.roundedBorder)
    .frame(width: 70)
    .onSubmit { saveValues() }
} else {
    // Show the formatted current value (existing code)
    Text(metric.formattedCurrent)
        .font(.callout.bold())
        .foregroundStyle(metric.status.color)
}
```

2. **Remove the sheet-based editing** — delete the `editingMetric` `@State` variable, the `.sheet(item: $editingMetric)` modifier, and the `editSheet(metric:)` function. They're no longer needed.

3. **Keep the `editValueText` state variable removal** — it was only used by the sheet and is no longer needed.

4. The result: clicking "Edit Values" instantly shows editable text fields inline next to every metric. The user types a number, presses Tab or Enter to move to the next, and values save automatically. Click "Done" (the button text changes from "Edit Values" to "Done" when editing) to exit edit mode.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Fix Trust icon (checkmark.shield) and inline BPOP metric editing"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

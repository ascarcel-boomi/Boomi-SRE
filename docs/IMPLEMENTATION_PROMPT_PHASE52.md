# Boomi SRE App — Phase 52: Fix Boomi Theme Colors & About "Check for Updates" Link

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Models/BoomiTheme.swift` — defines `BoomiColors`, `AppTheme`, and `AppState` extension with `themeAccent`, `themeSuccess`, `themeWarning`, `themeDanger`
- `BoomiSRE/Sources/Models/AppState.swift` — `appTheme` property
- `BoomiSRE/Sources/Views/AboutView.swift` — About popup, posts `openSettingsAboutTab` notification on "Check for Updates" click
- `BoomiSRE/Sources/Views/SettingsView.swift` — listens for `openSettingsAboutTab` notification, sets `selectedTab = "about"` but does NOT set `appState.showSettings = true`
- `BoomiSRE/Sources/Views/SidebarView.swift` — the ONLY file currently using `appState.themeAccent` (line ~38, 76, 78, 102, etc.)

---

## Bug 1: Boomi Theme Colors Don't Apply

**Root cause:** `appState.themeAccent` (and `themeSuccess`, `themeWarning`, `themeDanger`) are defined in `BoomiTheme.swift` but only used in `SidebarView.swift`. There are **132 occurrences of `.accentColor`** across 32 other files that still use the system accent color regardless of the theme setting.

**Fix:** Replace `.accentColor` with `appState.themeAccent` across all major views. Since this is a massive find-and-replace across 32 files, do it systematically:

1. **Create a SwiftUI Environment helper** so every view can access the theme color without needing `appState` directly:

   Add to `BoomiTheme.swift`:
   ```swift
   // Environment key for theme accent color
   private struct ThemeAccentKey: EnvironmentKey {
       static let defaultValue: Color = .accentColor
   }

   extension EnvironmentValues {
       var themeAccent: Color {
           get { self[ThemeAccentKey.self] }
           set { self[ThemeAccentKey.self] = newValue }
       }
   }
   ```

   Then in `ContentView.swift` (or `BoomiSREApp.swift`), set it on the root view:
   ```swift
   ContentView()
       .environment(\.themeAccent, appState.appTheme == "boomi" ? BoomiColors.boomiPurple : .accentColor)
   ```

   This way any child view can use `@Environment(\.themeAccent) var accent` without needing AppState.

2. **However, the simpler approach** for now: just use SwiftUI's `.tint()` modifier at the root level:

   In `BoomiSREApp.swift`, apply a global tint to the entire window:
   ```swift
   ContentView()
       .environmentObject(appState)
       // ... other environment objects
       .tint(appState.appTheme == "boomi" ? BoomiColors.boomiPurple : nil)
   ```

   SwiftUI's `.tint()` modifier cascades to ALL child views and affects:
   - Toggle switches
   - Button styles (`.borderedProminent`)
   - Progress views
   - Tab selection
   - Most accent-colored controls

   This single line will change the accent color for most of the app. The `nil` value means "use system default."

3. **For views that use `.foregroundStyle(.accentColor)` directly** (like icons, custom badges), those won't be affected by `.tint()`. For these, do a targeted replacement in the highest-impact files:

   **Replace in these files (the ones with the most `.accentColor` usage):**
   - `CopilotChatView.swift` (12 occurrences)
   - `AWSHealthView.swift` (10 occurrences)
   - `OnCallView.swift` (8 occurrences)
   - `OnboardingWizardView.swift` (8 occurrences)
   - `GitHubBrowserView.swift` (8 occurrences)
   - `ProductBriefingCard.swift` (7 occurrences)
   - `NotificationCenterView.swift` (6 occurrences)
   - `DashboardView.swift` (3 occurrences)
   - `FeedView.swift` (1 occurrence)
   - `WidgetViews.swift` (3 occurrences)
   - `MOTDView.swift` (5 occurrences)
   - `AboutView.swift` (5 occurrences)

   In each file, replace:
   ```swift
   .foregroundStyle(.accentColor)
   // with:
   .foregroundStyle(Color.accentColor)  // This will now respect the .tint() modifier
   ```

   Actually, `.foregroundStyle(.accentColor)` does NOT respond to `.tint()`. For these, use the `@EnvironmentObject var appState` that's already available in most views:
   ```swift
   .foregroundStyle(appState.themeAccent)
   ```

   **Priority:** Focus on the views the user sees most: DashboardView, FeedView, SidebarView (already done), OnCallView, WidgetViews, MOTDView, AIBar. Don't try to replace all 132 — get the top 10 most visible files.

4. **Also apply Boomi theme to the health score bar colors:**
   In `DashboardView`, the health score uses green/yellow/orange/red. When Boomi theme is active:
   - Healthy (80-100): `BoomiColors.boomiGreen` instead of `.green`
   - Warning (50-79): `BoomiColors.boomiCoral` instead of `.yellow`
   - Critical (25-49): `BoomiColors.boomiMagenta` instead of `.orange`
   - Emergency (0-24): `.red` (keep as-is — red is universal for danger)

---

## Bug 2: About "Check for Updates" Link Doesn't Work

**Root cause:** The About popup posts a `NotificationCenter` notification (`openSettingsAboutTab`). The SettingsView listens for it and sets `selectedTab = "about"`. But it never sets `appState.showSettings = true`, so the Settings pane never opens.

**Fix:** In `SettingsView.swift`, find the `onReceive` handler for `openSettingsAboutTab` (line ~173):

```swift
// Current:
.onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutTab)) { _ in
    selectedTab = "about"
}

// Fix — also open Settings and navigate to About:
.onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutTab)) { _ in
    appState.showSettings = true
    appState.selectedReport = nil
    selectedTab = "about"
}
```

But wait — `SettingsView` is only rendered when `appState.showSettings` is already true. So the `onReceive` handler never fires because the view doesn't exist yet.

**The real fix** — handle the notification at a higher level. In `ContentView.swift` (or `BoomiSREApp.swift`), add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutTab)) { _ in
    appState.showSettings = true
    appState.selectedReport = nil
    appState.selectedSettingsTab = "about"
}
```

Make sure `appState.selectedSettingsTab` is wired to the SettingsView's `selectedTab`. If `selectedSettingsTab` already exists on AppState and SettingsView reads from it, this should work. If SettingsView uses a local `@State` instead of AppState's `selectedSettingsTab`, change SettingsView to use `appState.selectedSettingsTab` so it can be controlled externally.

Also — the `AboutSettingsContent` view should auto-check for updates on appear (Phase 35 added this). Verify the `.onAppear { Task { await updateVM.checkForUpdate() } }` is present.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Fix Boomi theme colors applied globally, fix About Check for Updates navigation"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

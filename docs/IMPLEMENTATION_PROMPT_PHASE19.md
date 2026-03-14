# Boomi SRE App — Phase 19: Check for Updates Menu Item, Custom About Window & MOTD

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2).

**Read these files first:**
- `BoomiSRE/Sources/BoomiSREApp.swift` — app entry point with CommandMenus and the "About Boomi SRE" button in `CommandGroup(replacing: .appInfo)`
- `BoomiSRE/Sources/Views/AboutView.swift` — `showAboutPanel()` function using `NSApplication.shared.orderFrontStandardAboutPanel` (core authors, quote, credits)
- `BoomiSRE/Sources/Views/Settings/AboutSettingsContent.swift` — Settings "About" tab with version info, update check button, download & install, resource links
- `BoomiSRE/Sources/ViewModels/UpdateViewModel.swift` — `checkForUpdate()`, `downloadAndApply()`, published state
- `BoomiSRE/Sources/Models/AppState.swift` — central state
- `BoomiSRE/Sources/Views/SettingsView.swift` — settings panel with tab selection
- `BoomiSRE/Sources/Models/MOTDModels.swift` — `MOTDMessage` model, `MOTDCategory` enum
- `BoomiSRE/Sources/Models/MOTDData.swift` — `MOTDLibrary` with 42+ messages and `messageOfTheMoment()`
- `BoomiSRE/Sources/Views/Shared/MOTDView.swift` — existing MOTD display component (if it exists)

**Key constraints:**
- Pure SwiftUI. No third-party frameworks.

---

## Implementation Plan

### Phase 19A: Add "Check for Updates..." to the App Menu

**Goal:** Add the standard macOS "Check for Updates..." menu item in the Boomi SRE application menu.

**Implementation:**

1. In `BoomiSREApp.swift`, the `CommandGroup(replacing: .appInfo)` currently has just:
   ```swift
   Button("About Boomi SRE") { showAboutPanel() }
   ```
   Add a "Check for Updates..." item below it:
   ```swift
   CommandGroup(replacing: .appInfo) {
       Button("About Boomi SRE") {
           showAboutPanel()
       }
       Divider()
       Button(updateVM.availableUpdate != nil
           ? "Check for Updates… (Update Available)"
           : "Check for Updates…") {
           appState.selectedReport = nil
           appState.showSettings = true
           appState.selectedSettingsTab = "about"
       }
   }
   ```

2. **Wire `selectedSettingsTab` through AppState:**
   - Add `@Published var selectedSettingsTab: String = "preferences"` to `AppState`.
   - In `SettingsView.swift`, replace the local `@State private var selectedTab` with a binding to `appState.selectedSettingsTab` so the tab can be controlled externally.
   - This way clicking "Check for Updates..." opens Settings AND jumps directly to the About tab.

3. **No new persistence needed** — `selectedSettingsTab` is transient navigation state, not config.

---

### Phase 19B: Replace Standard About Panel with Custom About Window

**Problem:** The macOS standard `orderFrontStandardAboutPanel` has a fixed-size credits area that requires scrolling. We want all content to be visible without scrolling, and we want to include an MOTD.

**Goal:** Replace `showAboutPanel()` with a custom SwiftUI window that:
- Shows everything without scrolling (auto-sizes to fit content)
- Includes a rotating Message of the Day
- Feels polished and native

**Implementation:**

1. **Replace `showAboutPanel()` in `AboutView.swift`** with a function that opens a custom SwiftUI window:
   ```swift
   func showAboutPanel() {
       let aboutView = AboutWindowContent()
       let hostingView = NSHostingView(rootView: aboutView)
       hostingView.setFrameSize(hostingView.fittingSize)

       let window = NSWindow(
           contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
           styleMask: [.titled, .closable],
           backing: .buffered,
           defer: false
       )
       window.contentView = hostingView
       window.title = "About Boomi SRE"
       window.center()
       window.isReleasedWhenClosed = false
       window.level = .floating
       window.makeKeyAndOrderFront(nil)
   }
   ```

   Or even simpler — use a secondary `Window` scene in `BoomiSREApp.swift`:
   ```swift
   Window("About Boomi SRE", id: "about") {
       AboutWindowContent()
   }
   .windowStyle(.titleBar)
   .windowResizability(.contentSize)  // auto-sizes to fit content
   .defaultPosition(.center)
   ```
   Then `showAboutPanel()` becomes: `openWindow(id: "about")` (pass the `OpenWindowAction` environment value).

   Use whichever approach compiles cleanly. The `Window` scene approach is more SwiftUI-native. The `NSWindow` approach gives more control over sizing.

2. **Create `AboutWindowContent` view:**

   Layout (all centered, no scroll):
   ```
   ┌─────────────────────────────────────────────┐
   │                                             │
   │           ⚡ (app icon, 64pt)               │
   │                                             │
   │             Boomi SRE                       │
   │        Version 26.03.14-143022              │
   │       macOS SRE Command Center              │
   │                                             │
   │  ┌─────────────────────────────────────┐    │
   │  │ 🥷 "When we do our job well, no one │    │
   │  │    knows we exist. We are Boomi     │    │
   │  │    Ninjas."                         │    │
   │  │         — Boomi SRE Spirit          │    │
   │  └─────────────────────────────────────┘    │
   │                                             │
   │              ── Authors ──                  │
   │                                             │
   │   Adam Scarcella    Lead Idea Generator     │
   │   Claude Opus       Ph.D PM with a 250 AIQ │
   │   Claude Sonnet     Master Coder            │
   │                                             │
   │   GitHub Repository  ·  Release Notes       │
   │                                             │
   │  © 2026 Boomi, Ltd. All rights reserved.    │
   │                                             │
   └─────────────────────────────────────────────┘
   ```

3. **MOTD in the About window:**
   - Show one MOTD message in a subtle card between the version info and the Authors section
   - Use the same `MOTDLibrary.messageOfTheMoment()` to pick the message
   - Style it as a compact card: emoji + italic quote + attribution, with a thin accent-color left border (same style as the home page MOTD if `MOTDView` exists)
   - The message changes each time the About window is opened (picks a new one on appear)
   - Clicking the MOTD card cycles to a random next message (fun easter egg, same as home page)

4. **Sizing:**
   - The window should auto-size to fit all content with no scrolling
   - Use `.windowResizability(.contentSize)` if using the Window scene approach
   - Or calculate `fittingSize` if using NSWindow approach
   - Aim for approximately 420pt wide × 480-520pt tall (depends on MOTD length)
   - Fixed width, variable height based on content

5. **Keep the core authors list** from the current `showAboutPanel()`:
   - Adam Scarcella — Lead Idea Generator
   - Claude Opus — Ph.D PM with a 250 AIQ
   - Claude Sonnet — Master Coder
   - Additional git contributors from the AUTHORS file (if it exists in the bundle)
   - Style: name in medium weight, role in lighter secondary text, all centered

6. **Links row:** "GitHub Repository" and "Release Notes" as clickable links, centered, separated by a dot or pipe.

7. **Copyright footer:** `© {year} Boomi, Ltd. All rights reserved.` in tiny tertiary text at the bottom.

8. **Polish:**
   - The window should feel like a premium native macOS About panel, not a web page
   - Background: default window background (no custom colors)
   - Generous padding (24pt on all sides)
   - Subtle dividers between sections (or just spacing — don't overdo dividers)
   - The MOTD card should be the visual highlight — it's the personality of the window

---

### Phase 19C: Enhance the About Settings Tab

**Goal:** The Settings → About tab should also be enhanced with the same content, plus the update functionality.

**Changes to `AboutSettingsContent.swift`:**

1. **Larger app icon:** Change from 48pt to 64pt.

2. **Add an MOTD** below the version info, same style as the About window. Use `MOTDLibrary.messageOfTheMoment()`. Rotates every 5 minutes or on refresh.

3. **Add Authors section** below Resources:
   ```
   Adam Scarcella    Lead Idea Generator
   Claude Opus       Ph.D PM with a 250 AIQ
   Claude Sonnet     Master Coder
   ```

4. **Add copyright footer.**

5. **Keep the Update section as the centerpiece** — don't change its layout or behavior.

6. **Overall spacing:** Use `spacing: 24` between sections.

---

## General Guidelines

- Run `swift build` after each sub-phase to verify compilation.
- Don't break existing features.
- Commit after each phase (19A, 19B, 19C) with a descriptive message.

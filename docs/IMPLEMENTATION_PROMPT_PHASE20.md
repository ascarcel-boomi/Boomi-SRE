# Boomi SRE App — Phase 20: Custom About Popup Window (No Scrolling)

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/AboutView.swift` — current `showAboutPanel()` using `NSApplication.shared.orderFrontStandardAboutPanel`
- `BoomiSRE/Sources/BoomiSREApp.swift` — where `showAboutPanel()` is called from the "About Boomi SRE" menu item
- `BoomiSRE/Sources/Models/MOTDData.swift` — `MOTDLibrary` with `messageOfTheMoment()` (if it exists)
- `BoomiSRE/Sources/Models/MOTDModels.swift` — `MOTDMessage` model (if it exists)

**Key constraint:** Pure SwiftUI. No third-party frameworks.

---

## The Problem

The macOS standard `orderFrontStandardAboutPanel` renders the credits in a fixed-height scrollable `NSTextView` (~100pt tall). When the credits content is longer than that area, the user has to scroll. There is no API to change this height. The only solution is to replace it with a custom window.

---

## Implementation

### Phase 20A: Replace Standard About Panel with Custom NSWindow

**Goal:** The "Boomi SRE → About Boomi SRE" menu item should open a custom popup window where ALL content is visible without scrolling. The window auto-sizes to fit.

**Rewrite `showAboutPanel()` in `AboutView.swift`:**

1. Replace `orderFrontStandardAboutPanel` with a custom `NSWindow` containing an `NSHostingView` that wraps a SwiftUI view.

2. The SwiftUI view (`AboutPanelContent`) should replicate the look of a native About panel but with enough room for everything:

   ```
   ┌───────────────────────────────────────────┐
   │                                           │
   │          [App Icon — 64pt]                │
   │                                           │
   │            Boomi SRE                      │
   │       Version 26.03.14-143022             │
   │                                           │
   │  ┌───────────────────────────────────┐    │
   │  │ 🥷  "When we do our job well,    │    │
   │  │     no one knows we exist.        │    │
   │  │     We are Boomi Ninjas."         │    │
   │  │          — Boomi SRE Spirit       │    │
   │  └───────────────────────────────────┘    │
   │                                           │
   │  "You're only limited by your             │
   │   imagination!"                           │
   │                                           │
   │             Authors                       │
   │  Adam Scarcella   Lead Idea Generator     │
   │  Claude Opus      Ph.D PM with a 250 AIQ │
   │  Claude Sonnet    Master Coder            │
   │                                           │
   │  © 2026 Boomi, Ltd. All rights reserved.  │
   │                                           │
   └───────────────────────────────────────────┘
   ```

3. **Window properties:**
   - Style mask: `.titled` + `.closable` (no resize, no minimize)
   - NOT `.resizable` — the window should be exactly the size of its content
   - Centered on screen
   - Floating level (stays in front like a standard About panel)
   - Released when closed (or reuse a single window instance to avoid duplicates)
   - **Single instance:** If the About window is already open, bring it to front instead of creating a new one. Store the window reference in a static var.

4. **Auto-sizing:** After creating the `NSHostingView`, call:
   ```swift
   let hostingView = NSHostingView(rootView: AboutPanelContent())
   hostingView.setFrameSize(hostingView.fittingSize)
   ```
   Set the window's content size to `hostingView.fittingSize`. This makes the window exactly the right size — no scrolling, no wasted space.

5. **Fixed width, variable height:** Set a fixed width (~380pt, matching standard About panels) on the SwiftUI content with `.frame(width: 380)`. The height will be determined by `fittingSize` based on content length.

6. **MOTD card (nice to have):**
   - If `MOTDLibrary` exists, show one message between the version info and the "You're only limited..." quote
   - Use `MOTDLibrary.messageOfTheMoment()` — picks a new message each time the window opens
   - Style it as a subtle card: emoji + italic quote text + attribution in small secondary text
   - Thin accent-colored left border (3pt rounded bar)
   - If `MOTDLibrary` doesn't exist (Phase 18 wasn't implemented), just skip the MOTD — don't fail

7. **Keep all existing content** from the current `showAboutPanel()`:
   - App name: "Boomi SRE"
   - Version from `CFBundleShortVersionString`
   - The "You're only limited by your imagination!" quote in Georgia Italic
   - Authors section with core authors + git contributors from AUTHORS file
   - Copyright: "© {year} Boomi, Ltd. All rights reserved."

8. **Styling:**
   - Everything centered
   - App icon: `bolt.shield.fill` at 64pt in accent color (or `AppIcon.icns` from the bundle if available via `NSImage(named: "AppIcon")`)
   - App name: `.title.bold()`
   - Version: `.callout.secondary`
   - Authors header: `.subheadline.bold().secondary`
   - Author names: `.callout` medium weight
   - Author roles: `.caption` secondary
   - Copyright: `.caption2` tertiary
   - Padding: 28pt on all sides
   - Background: default window background (`.background` or nothing — let the window chrome handle it)

---

## General Guidelines

- Run `swift build` after implementation to verify compilation.
- The menu item in `BoomiSREApp.swift` should NOT change — it still calls `showAboutPanel()`. Only the implementation of that function changes.
- Commit with a descriptive message.

# Boomi SRE App — Phase 9: Sidebar UX Overhaul & Breadcrumb Navigation

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation (the primary file you'll be modifying)
- `BoomiSRE/Sources/Views/ContentView.swift` — NavigationSplitView root layout
- `BoomiSRE/Sources/Models/AppState.swift` — central state object (has `sidebarCollapsed` already)
- `BoomiSRE/Sources/Models/ReportItem.swift` — ReportItem model, ReportCatalog, ReportSection (each item has an `icon` String)
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point and CommandMenu

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Never macOS Keychain (unsigned app).
- Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path `/usr/local/bin/aws` (PATH stripped in .app bundle).
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira/Confluence Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 9A: Sidebar Icon Colors — Use Accent Color Consistently

**Problem:** Some sidebar icons are grey (`.secondary`) and some inherit the macOS system accent color. They should ALL use the accent color to match the user's macOS Appearance preference.

**Current state in `SidebarView.swift`:**
- Individual item icons all use `.foregroundStyle(.secondary)` (lines like `Image(systemName: report.icon).foregroundStyle(.secondary)`) — there are instances in the AI, Jira, AWS, Google, and Services sections.
- Section header icons (in `sectionHeader()` helper and inline `Label` headers for AI and Services) inherit different styling.
- The Home button icon and Settings button icon also use mixed styling.

**Changes:**
1. Change every `Image(systemName: report.icon).foregroundStyle(.secondary)` to `.foregroundStyle(.accentColor)`. There are 5 instances (one per section: AI, Jira, AWS, Google, Services).
2. In the `sectionHeader()` helper function, ensure the SF Symbol icon in `Label(title, systemImage: icon)` uses `.foregroundStyle(.accentColor)` for the icon. The header **text** should stay `.secondary`.
3. The AI section header `Label("AI", systemImage: "sparkles")` — apply `.foregroundStyle(.accentColor)` to the icon.
4. The Services section header `Label("Services", systemImage: "network")` — apply `.foregroundStyle(.accentColor)` to the icon.
5. The Home button `Label("Home", systemImage: "house")` — apply `.foregroundStyle(.accentColor)` to the icon.
6. The Settings button `Image(systemName: "gear")` — change from `.foregroundStyle(.secondary)` to `.foregroundStyle(.accentColor)`.
7. Leave status dots (green/orange/red/grey Circle views) and badge capsules completely unchanged — only SF Symbol icons change.

---

### Phase 9B: Sidebar Collapse — Icon-Only Strip Instead of Full Hide

**Problem:** When the user clicks the macOS toolbar button to collapse the sidebar, it disappears completely. Instead it should collapse to a narrow icon-only strip (~50pt wide) showing just the SF Symbol icons for each item with no text.

**Current state:**
- `ContentView.swift` uses `NavigationSplitView { SidebarView() } detail: { ... }` with `.navigationSplitViewStyle(.balanced)`.
- `AppState` already has `@Published var sidebarCollapsed = false` but it's not wired to anything.
- SwiftUI's `NavigationSplitView` does NOT natively support an "icon-only collapsed" state — it either shows the full sidebar or hides it entirely.

**Implementation:**

1. **Replace `NavigationSplitView` in `ContentView.swift`** with a custom `HStack` layout:
   ```
   HStack(spacing: 0) {
       SidebarView()
           .frame(width: appState.sidebarCollapsed ? 50 : 220)
       Divider()
       // detail content (the existing switch/routing)
   }
   ```
   Keep all the existing detail-pane routing logic (the `if let ticketKey` / `else if showSettings` / `else if let report` / `else DashboardView()` chain).

2. **Add a toolbar button** (or a button at the top of the sidebar) with SF Symbol `sidebar.left` that toggles `appState.sidebarCollapsed`.

3. **In `SidebarView.swift`**, read `appState.sidebarCollapsed` and conditionally render:
   - **When expanded (current behavior):** Show the full sidebar as-is — icon + title + description + badges.
   - **When collapsed:** Render each item as just its SF Symbol icon centered in a ~44×44pt tappable area. Use `.help(report.title)` on each icon so the name shows as a tooltip on hover. No text, no descriptions, no badges, no section header text.
   - Section headers when collapsed: show just their section icon (sparkles, ticket, cloud, envelope, network, gear) centered, with no text and no disclosure arrow.
   - Home icon and Settings icon should also appear in collapsed mode.

4. **Animate the width change** with `.animation(.easeInOut(duration: 0.2), value: appState.sidebarCollapsed)`.

5. Since we're replacing `NavigationSplitView`, the `List(selection:)` binding needs to work differently. Use a `ScrollView` with `VStack` in collapsed mode, or keep the `List` but hide text content. The key requirement: clicking an icon in collapsed mode must still set `appState.selectedReport` to navigate to that view.

---

### Phase 9C: Clickable Section Headers to Expand/Collapse

**Problem:** Sidebar sections (AI, Jira, AWS, Google, Services) only collapse when clicking the tiny disclosure arrow on the right edge. The entire section header (icon + text) should be clickable to toggle collapse.

**Implementation:**

1. Add `@State private var collapsedSections: Set<String> = []` to `SidebarView` (keyed by section name: "AI", "Jira", "AWS", "Google", "Services").

2. Replace SwiftUI's built-in `Section` disclosure with a custom implementation for each section:
   - A `Button` for the header row that toggles the section key in `collapsedSections`.
   - Below the header button, conditionally render the `ForEach` of items only when the section is NOT in `collapsedSections`.
   - The header button should show:
     - A chevron icon (`chevron.right`) that rotates 90° when expanded, 0° when collapsed — animated with `.rotationEffect`.
     - The section SF Symbol icon (in accent color per Phase 9A).
     - The section title text.
     - The status dot (for sections that have one: Jira, AWS, Google).
   - The entire header row should be tappable (use `.contentShape(Rectangle())`).

3. **When sidebar is collapsed (from Phase 9B):** Clicking a section icon in the icon-only strip should navigate to the first item in that section. For example:
   - Clicking the sparkles (AI) icon → navigates to Copilot Chat (first AI item)
   - Clicking the ticket (Jira) icon → navigates to My TODO
   - Clicking the cloud (AWS) icon → navigates to Cost Explorer
   - Clicking the envelope (Google) icon → navigates to Gmail
   - Clicking the network (Services) icon → navigates to GitHub
   - Clicking the gear icon → opens Settings

---

### Phase 9D: Breadcrumb Navigation Bar

**Problem:** When navigating deep into the app (e.g., Home → Jira → My TODO → CAMSRE-1234), there's no way to see where you are or quickly jump back to a parent level.

**Implementation:**

1. **Create `BoomiSRE/Sources/Views/BreadcrumbView.swift`:**
   - A thin horizontal strip (~28pt tall) at the top of the detail pane.
   - Shows a breadcrumb trail: `Home > [Section] > [Page]` (and optionally a 4th level for ticket detail).
   - Each crumb is separated by a `chevron.right` SF Symbol (small, grey).
   - Clickable crumbs are styled with `.foregroundStyle(.accentColor)` and are `Button`s.
   - The last (current) crumb is styled with `.foregroundStyle(.secondary)` and is plain `Text` (not clickable).
   - A subtle bottom `Divider()` separates it from the content below.
   - Font: `.callout` or `.caption` — small but readable.

2. **Breadcrumb logic** (derive entirely from existing AppState — no new state needed):
   - If `appState.showSettings`:  `Home > Settings`
   - If `appState.selectedTicketKey` is set:  `Home > Jira > My TODO > [ticketKey]`
     - Clicking "Home" → clears selectedReport, showSettings, selectedTicketKey
     - Clicking "Jira" → does nothing (no section landing page yet), or optionally navigates to first Jira item
     - Clicking "My TODO" → clears selectedTicketKey, sets selectedReport to jira_todo
   - If `appState.selectedReport` is set:  `Home > [report.section.rawValue] > [report.title]`
     - Clicking "Home" → clears selectedReport
     - "[Section]" → not clickable (shown for context)
     - "[Page title]" → current page, not clickable
   - If nothing is selected (dashboard): just show `Home` (non-clickable, grey — you're already there)

3. **Place it in `ContentView.swift`:** Wrap the detail pane content in a `VStack(spacing: 0)` with `BreadcrumbView()` at the top, then the existing view routing below:
   ```swift
   } detail: {
       VStack(spacing: 0) {
           BreadcrumbView()
           // existing if/else chain for detail views
       }
   }
   ```
   (Or the equivalent if using the custom HStack layout from Phase 9B.)

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing sidebar navigation, service browsers, and AI features must continue to work.
- **Dark mode:** All new views must support both light and dark macOS appearances.
- **Commit after each phase** (9A, 9B, 9C, 9D) with a descriptive commit message.

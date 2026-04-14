# Work Map: My Focus + Eisenhower Panel — Design Spec

**Date:** 2026-04-14
**Status:** Draft
**Scope:** "My Focus" mode for Work Map — Eisenhower classification panel, auto-zoom to user's work, bidirectional tree-panel bridge

---

## Problem

The Work Map shows the full org's Jira hierarchy (projects > epics > stories) as a D3.js tree. It answers "what does the org's work look like?" but not "what should I work on next?" Users must manually filter by assignee and visually scan to find their own work. There is no prioritization — a stale in-progress epic looks the same as a healthy to-do story.

## Philosophy

Classification follows the Eisenhower Matrix (from [CAM SRE Team Philosophies](https://boomii.atlassian.net/wiki/spaces/camsre/pages/17032054713/CAM+SRE+Team+Philosophies#Eisenhower-Matrix:)):
- **Urgent + Important → Do First**
- **Important + Not Urgent → Schedule**
- **Urgent + Not Important → Delegate**
- **Not Important + Not Urgent → Eliminate**

The map should locate the user's important work and show them what to work on next, while preserving the spatial context of the org tree.

---

## Requirements

### R1: Eisenhower Classifier

A pure Swift struct `EisenhowerClassifier` that takes the existing `[WorkMapNode]` data, a user display name, and the current quarter string, and returns an `EisenhowerResult`.

**Inputs:**
- `nodes: [WorkMapNode]` — the full parsed tree (already fetched by `WorkMapViewModel.loadTree`)
- `userDisplayName: String` — resolved from `AppState.jiraEmail`
- `watchedKeys: Set<String>` — ticket keys the user is watching (fetched once per session)
- `currentQuarter: String` — e.g., `"Q2CY26"`

**Output — `EisenhowerResult`:**
- `focusNow: [EisenhowerItem]` — top 3 priority items across all quadrants
- `doFirst: [EisenhowerItem]` — Q1: Urgent + Important
- `schedule: [EisenhowerItem]` — Q2: Important + Not Urgent
- `delegate: [EisenhowerItem]` — Q3: Urgent + Not Important
- `eliminate: [EisenhowerItem]` — Q4: Not Important + Not Urgent
- `userNodeKeys: Set<String>` — all ticket keys assigned to or watched by the user (for tree filtering)

**`EisenhowerItem`:**
- `key: String` — Jira issue key
- `name: String` — summary
- `type: String` — issue type
- `status: String` — status name
- `statusCategory: String` — new / indeterminate / done
- `staleDays: Int?` — days since last update (nil if not stale)
- `sp: Double?` — story points
- `quarter: String` — committed quarter
- `project: String` — project key
- `isDelegated: Bool` — true if user is watcher, not assignee
- `quadrant: Quadrant` — which quadrant this item belongs to

**Classification rules:**

| Quadrant | Condition |
|----------|-----------|
| **Q1: Do First** | Assigned to user AND planned type (epic/story/deploy_req) AND statusCategory == "indeterminate" AND (stale > 14 days OR quarter == currentQuarter) |
| **Q2: Schedule** | Assigned to user AND planned type AND quarter == currentQuarter AND statusCategory == "new" AND has story points |
| **Q3: Delegate** | Assigned to user AND unplanned type (task/ops_req/troubleshoot/access_req) OR watched tickets (isDelegated = true) |
| **Q4: Eliminate** | Assigned to user AND (quarter != currentQuarter OR (no SP AND no recent activity AND statusCategory == "new")) |

**Planned types:** epic, story, deploy_req
**Unplanned types:** task, ops_req, troubleshoot, access_req (matches existing `isPlannedWork()` in work_map.html)

**Focus Now top 3 selection:** Draw from Q1 first (sorted by staleDays descending — most neglected first), then Q3 (urgent unplanned), then Q2 (next planned work). Never draw from Q4.

**Tickets that are "done" are excluded entirely** — the classifier only processes non-done tickets.

### R2: Eisenhower Panel View

A native SwiftUI view (`EisenhowerPanelView`) rendered as a right-side panel alongside the WKWebView tree.

**Layout:**
- Panel width: ~280pt, resizable via drag handle (min 220, max 400)
- Appears/disappears with slide animation (~300ms) when "My Focus" is toggled
- Scrolls independently from the tree

**Sections (top to bottom):**
1. **Focus Now** header — purple accent, shows top 3 items
2. **Do First** section — red header, Q1 items sorted by staleDays desc
3. **Schedule** section — blue header, Q2 items sorted by SP desc
4. **Delegate** section — amber header, Q3 items with "Watching" badge for delegated items
5. **Eliminate** section — gray header, Q4 items

**Card design — compact single-line:**
- Left: Jira key (blue link color, bold, 11px)
- Middle: Summary text (secondary color, 10px, truncated with ellipsis, flex fill)
- Right: Status badge (abbreviated — IP/TD/DN, tiny pill) + staleness badge (red, e.g., "5d") or SP badge (blue, e.g., "3sp")

**Interactions:**
- **Click card** → navigate to in-app ticket detail (`appState.selectedTicketKey = key`) AND send `highlightAndZoomTo(key)` to tree via JS bridge
- **Right-click card** → context menu with "Open in Jira" (launches `{jiraBaseURL}/browse/{key}` in system browser)
- **Hover card** → subtle background highlight

**Quadrant section headers** show count badge (e.g., "Do First (3)").
**Empty quadrant** shows a subtle "None" label — section still visible for orientation.

### R3: "My Focus" Toggle

A new button in the Work Map top bar toolbar.

**Appearance:** Gradient background (purple→blue), text "My Focus", lightning bolt icon. Toggles between active (filled gradient) and inactive (plain button style).

**Activation (toggle on):**
1. Resolve user display name from `appState.jiraEmail` → `appState.jiraDisplayName` (cached in AppState after first resolution)
2. Fetch watched ticket keys via Jira API: `watcher = currentUser()` (one query, cached until next refresh)
3. Run `EisenhowerClassifier.classify()` on existing `allNodes` data
4. Set `eisenhowerResult` on VM — panel appears with slide animation
5. Send `focusOnUser(userNodeKeys)` to JS bridge — tree filters and zooms

**Deactivation (toggle off):**
1. Clear `eisenhowerResult` — panel slides out
2. Send JS `clearUserFocus()` — tree restores full data, fades everything back to 100%, zooms to fit-all
3. Stats pills revert to org-wide counts

**Stats pills when active:** Switch from "42 Epics / 187 Issues / 65% Done" to "7 My Epics / 16 My Issues / 3 Focus"

### R4: Tree Auto-Zoom ("focusOnUser")

New JS bridge function in `work_map.html`.

**`window.focusOnUser(keysJSON)`:**
- Input: JSON array of the user's ticket keys (from `EisenhowerResult.userNodeKeys`)
- Behavior:
  1. Auto-expand projects that contain user's epics (collapse all others)
  2. Auto-expand user's epics that are in Q1 (Do First) — show their children
  3. Keep Q2/Q3/Q4 user epics collapsed but visible
  4. Fade non-user nodes to 15% opacity (reuse existing dimming pattern)
  5. `fitToView()` scoped to only the user's visible nodes

**`window.highlightAndZoomTo(key)`:**
- Input: single ticket key string
- Behavior:
  1. Find the node in the tree by key
  2. If node's parent epic is collapsed, expand it
  3. Smooth-scroll and zoom to center the node
  4. Pulse animation on the node (reuse existing search ring pattern)
  5. Pulse fades after 3 seconds

**`window.clearUserFocus()`:**
- Restore all nodes to 100% opacity
- Re-collapse any auto-expanded nodes
- `fitToView()` to full tree

### R5: Tree → Panel Bridge

When a node is clicked on the tree while My Focus is active:

- If the clicked node's key exists in the Eisenhower panel, the panel auto-scrolls to that card and flashes its background briefly (0.3s highlight)
- Implemented via existing `WKScriptMessageHandler` — new message name `nodeHighlight` sent alongside existing `nodeClick`
- SwiftUI panel uses `ScrollViewReader` with `scrollTo(key)` for programmatic scroll

### R6: Context Menu (Open in Jira)

Both the Eisenhower panel cards and tree nodes support right-click → "Open in Jira":

- **Panel cards:** SwiftUI `.contextMenu` with "Open in Jira" button that calls `NSWorkspace.shared.open(jiraURL)`
- **Tree nodes:** JS `contextmenu` event handler that sends `openInBrowser` message to Swift via `webkit.messageHandlers`
- URL format: `{appState.jiraBaseURL}/browse/{key}`

### R7: Watcher Resolution

One additional Jira API call to support the "delegated work" classification:

- JQL: `watcher = currentUser() AND statusCategory != Done ORDER BY updated DESC`
- Fields: `key` only (minimal payload)
- Runs once when "My Focus" is first activated in a session
- Result cached in `WorkMapViewModel.watchedKeys: Set<String>` until next explicit refresh
- If the API call fails (permissions, etc.), gracefully degrade — Q3 shows only unplanned assigned work, no watched items

---

## Architecture

### New Files

| File | Type | Purpose |
|------|------|---------|
| `Models/EisenhowerClassifier.swift` | Model | Pure classification struct — no UI, no services |
| `Views/Panels/EisenhowerPanelView.swift` | View | SwiftUI right-sidebar panel with compact cards |

### Modified Files

| File | Changes |
|------|---------|
| `ViewModels/WorkMapViewModel.swift` | Add `myFocusActive`, `eisenhowerResult`, `currentUserDisplayName`, `watchedKeys`. Add `activateMyFocus()` and `deactivateMyFocus()` methods. |
| `Views/Panels/WorkMapView.swift` | Add "My Focus" button to toolbar. Wrap tree + panel in `HStack` with conditional panel. Wire bidirectional bridge. Add right-click context menu. |
| `Resources/work_map.html` | Add `focusOnUser(keysJSON)`, `highlightAndZoomTo(key)`, `clearUserFocus()` JS functions. Add `contextmenu` handler for "Open in Jira". Add `nodeHighlight` message handler. |
| `Models/AppState.swift` | Add `jiraDisplayName: String` (cached, resolved from `jiraEmail` on first My Focus activation). |

### Data Flow

```
AppState.jiraEmail
    │
    ▼
WorkMapViewModel.loadTree()              ← existing, one Jira fetch
    │
    ▼
allNodes: [WorkMapNode]                  ← existing parsed tree
    │
    ├──→ buildTreeJSON() → treeJSON      ← existing, pushes to WKWebView
    │
    └──→ activateMyFocus()               ← NEW, triggered by toggle
            │
            ├─ resolve jiraEmail → displayName (one-time, cached)
            ├─ fetch watchedKeys via JQL (one-time, cached)
            │
            ▼
         EisenhowerClassifier.classify(
           nodes: allNodes,
           userDisplayName: displayName,
           watchedKeys: watchedKeys,
           currentQuarter: "Q2CY26"
         )
            │
            ▼
         EisenhowerResult
            ├──→ EisenhowerPanelView     (SwiftUI sidebar)
            └──→ JS: focusOnUser(keys)   (tree auto-zoom + filter)
```

**No duplicate API calls.** The classifier operates on the `allNodes` data already in memory. Only two new API calls (display name resolution + watcher query), both cached for the session.

---

## Coding Constraints

Per project CLAUDE.md and macOS Swift KB:

- `EisenhowerClassifier` is a plain struct (not @Observable, not a class) — pure function input→output
- `EisenhowerPanelView` uses `@State private var vm` pattern for any local state, reads `eisenhowerResult` from parent
- All async property mutations in `WorkMapViewModel` wrapped in `withAnimation(.none) { }`
- All HTTP calls via `ZscalerTrustURLSession.shared`
- Use `ViewStyles.swift` design tokens for panel styling (`.cardStyle()`, `DesignTokens.cornerRadius`, etc.)
- Theme support: panel colors adapt via `appState.themeAccent`, `themeSuccess`, etc.
- `@ObservationIgnored` on non-UI state (cached watchedKeys, displayName)

---

## Out of Scope

- Persisting My Focus as default on launch (toggle resets each session)
- AI-generated "why you should work on this" explanations
- Drag-and-drop manual re-prioritization within quadrants
- Notification integration for stale Q1 items
- Due date field fetching (not in current WorkMapNode — future enhancement to sharpen Q1)
- Manager view ("show me my team's Eisenhower matrices")
- Eisenhower classification outside the Work Map (e.g., in My Work panel)

---

## Test Plan

1. **Classifier unit logic:** Given a set of mock WorkMapNodes with known types/statuses/quarters/assignees, verify each lands in the correct quadrant
2. **Focus Now selection:** Verify top 3 draws from Q1 first, then Q3, then Q2, never Q4
3. **Empty states:** User with no assigned work → panel shows "No work found" message, tree shows nothing focused
4. **Watcher support:** Ticket where user is watcher but not assignee → appears in Q3 with "Watching" badge, isDelegated = true
5. **Toggle on/off:** Panel slides in/out, tree zooms to user/restores, stats switch personal/org
6. **Panel → Tree bridge:** Click card in panel → tree node auto-expands, zooms, pulses
7. **Tree → Panel bridge:** Click node on tree → panel scrolls to card, highlights
8. **Right-click → Open in Jira:** Both panel cards and tree nodes open correct Jira URL in browser
9. **Theme support:** All 3 themes (dark/light/boomi) render panel correctly
10. **Graceful degradation:** Watcher API fails → Q3 shows only unplanned assigned work, no error shown
11. **Build verification:** `swift build -c release` succeeds with 0 errors, 0 warnings

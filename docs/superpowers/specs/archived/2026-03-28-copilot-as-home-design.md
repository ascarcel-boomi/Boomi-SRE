# AI Copilot as Home — Design Spec

> **STATUS: SUPERSEDED** — Reversed by [bug-fix-stabilization spec](../2026-04-02-bug-fix-stabilization-design.md) item 1.2. Dashboard is now the default home page, Copilot is the second tab.

**Goal:** Make the AI Copilot the default home page, move Dashboard/Feed under My Work, and add a toggleable auto-summary on launch.

## Navigation Changes

**New sidebar order (7 items, same count):**
1. **Home** → AI Copilot Chat (was Dashboard)
2. Alerts & On-Call (unchanged)
3. Incidents (unchanged)
4. **My Work** → Dashboard/Feed/Widgets + TODO + Boards + Filters + PCR (gains Dashboard)
5. Infrastructure (unchanged)
6. Knowledge & Tools (loses Copilot sub-tab)
7. Communicate (unchanged)

## What moves where
- AI Copilot moves from Knowledge & Tools sub-tab to Home (sidebar item `"home"`)
- Dashboard/Feed/Widgets move from Home to a new "Dashboard" sub-tab at the top of My Work
- My Work keeps existing sub-tabs and gains Dashboard as first sub-tab

## New setting: Auto-summary on launch
- Property: `@Published var copilotAutoSummaryOnLaunch: Bool = false` in AppState
- Persisted in AppConfig as `copilotAutoSummaryOnLaunch: Bool?`
- Toggle location: Settings > AI section
- Behavior when enabled: on app launch, if AI is available and no existing chat history from the last 4 hours, auto-send "Give me a brief status update — what's happening across my services right now?" to the copilot
- Behavior when disabled (default): clean chat with context chips ready to go

## Keyboard shortcuts
- ⌘0 = Home (now opens AI Copilot)
- ⌘3 = My Work (now includes Dashboard as first sub-tab)
- ⌘/ = removed as separate navigation (Home IS the copilot); or kept as alias for ⌘0

## Files to modify
- `ContentView.swift` — swap "home" case to render CopilotChatView instead of DashboardView
- `SidebarView.swift` — update Home icon from house to sparkles, update tooltip
- `MyWorkPanel.swift` — add "Dashboard" as first sub-tab, render DashboardView
- `BoomiSREApp.swift` — update ⌘/ to navigate home, add auto-summary trigger on launch
- `AppState.swift` — add `copilotAutoSummaryOnLaunch` property + persistence
- `SettingsView.swift` — add toggle in AI settings section
- `KnowledgeToolsPanel.swift` — remove Copilot sub-tab (it's now Home)

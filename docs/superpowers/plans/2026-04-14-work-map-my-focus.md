# Work Map: My Focus + Eisenhower Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "My Focus" mode to the Work Map that auto-zooms to the current user's work, classifies tickets into Eisenhower Matrix quadrants, and shows a prioritized sidebar panel with "Focus Now" top-3 recommendations.

**Architecture:** Hybrid native SwiftUI panel + D3.js tree with bidirectional bridge. A pure `EisenhowerClassifier` struct classifies existing `WorkMapNode` data into quadrants without additional API calls. The SwiftUI panel renders compact cards; the tree auto-zooms via new JS bridge functions. One new Jira query fetches watched ticket keys for delegated-work classification.

**Tech Stack:** Swift 6 / SwiftUI / macOS 15 / WKWebView / D3.js / Jira REST API v3

**Spec:** `docs/superpowers/specs/2026-04-14-work-map-my-focus-design.md`

**CLAUDE.md:** Read `~/github/Boomi-SRE/CLAUDE.md` before ANY code — it contains mandatory coding rules.

**macOS Swift KB:** Read `~/macOS-Swift-kb/03-observation-state.md` and `~/macOS-Swift-kb/04-rendering-pipeline.md` before writing ViewModel or View code.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `BoomiSRE/Sources/Models/EisenhowerClassifier.swift` | Create | Pure struct: classification logic + model types |
| `BoomiSRE/Sources/Views/Panels/EisenhowerPanelView.swift` | Create | SwiftUI right sidebar panel with compact cards |
| `BoomiSRE/Sources/ViewModels/WorkMapViewModel.swift` | Modify | Add My Focus state, activation/deactivation, watcher fetch |
| `BoomiSRE/Sources/Views/Panels/WorkMapView.swift` | Modify | Add My Focus button, panel layout, bidirectional bridge |
| `BoomiSRE/Sources/Resources/work_map.html` | Modify | Add JS bridge functions: focusOnUser, highlightAndZoomTo, clearUserFocus, contextmenu |
| `BoomiSRE/Sources/Models/AppState.swift` | Modify | Add jiraDisplayName cached property |

---

### Task 1: EisenhowerClassifier — Models and Classification Logic

**Files:**
- Create: `BoomiSRE/Sources/Models/EisenhowerClassifier.swift`

This is the pure data layer — no UI, no services, no async. All types and classification in one file.

- [ ] **Step 1: Create the model types and classifier**

Create `BoomiSRE/Sources/Models/EisenhowerClassifier.swift` with this content:

```swift
import Foundation

// MARK: - Eisenhower Types

enum Quadrant: String, CaseIterable, Sendable {
    case doFirst = "Do First"
    case schedule = "Schedule"
    case delegate = "Delegate"
    case eliminate = "Eliminate"
}

struct EisenhowerItem: Identifiable, Sendable {
    var id: String { key }
    let key: String
    let name: String
    let type: String
    let status: String
    let statusCategory: String
    let staleDays: Int?
    let sp: Double?
    let quarter: String
    let project: String
    let isDelegated: Bool
    let quadrant: Quadrant
}

struct EisenhowerResult: Sendable {
    let focusNow: [EisenhowerItem]      // top 3
    let doFirst: [EisenhowerItem]       // Q1
    let schedule: [EisenhowerItem]      // Q2
    let delegate: [EisenhowerItem]      // Q3
    let eliminate: [EisenhowerItem]     // Q4
    let userNodeKeys: Set<String>       // all keys for tree filtering

    var totalCount: Int { doFirst.count + schedule.count + delegate.count + eliminate.count }
    var isEmpty: Bool { totalCount == 0 }
}

// MARK: - Classifier

struct EisenhowerClassifier {

    static let plannedTypes: Set<String> = ["epic", "story", "deploy_req", "deployment request"]
    static let unplannedTypes: Set<String> = ["task", "ops_req", "operational request", "troubleshoot", "troubleshooting", "access_req", "access request"]
    static let staleDaysThreshold = 14

    static func classify(
        nodes: [WorkMapNode],
        userDisplayName: String,
        watchedKeys: Set<String>,
        currentQuarter: String
    ) -> EisenhowerResult {
        var doFirst: [EisenhowerItem] = []
        var schedule: [EisenhowerItem] = []
        var delegateQ: [EisenhowerItem] = []
        var eliminate: [EisenhowerItem] = []
        var allUserKeys: Set<String> = Set(watchedKeys)

        for project in nodes {
            let projectKey = project.key
            for epic in project.children {
                // Process the epic itself
                processTicket(
                    epic, projectKey: projectKey, userDisplayName: userDisplayName,
                    watchedKeys: watchedKeys, currentQuarter: currentQuarter,
                    doFirst: &doFirst, schedule: &schedule,
                    delegateQ: &delegateQ, eliminate: &eliminate,
                    allUserKeys: &allUserKeys
                )
                // Process epic's children
                for child in epic.children {
                    processTicket(
                        child, projectKey: projectKey, userDisplayName: userDisplayName,
                        watchedKeys: watchedKeys, currentQuarter: currentQuarter,
                        doFirst: &doFirst, schedule: &schedule,
                        delegateQ: &delegateQ, eliminate: &eliminate,
                        allUserKeys: &allUserKeys
                    )
                }
            }
        }

        // Sort quadrants
        doFirst.sort { ($0.staleDays ?? 0) > ($1.staleDays ?? 0) }
        schedule.sort { ($0.sp ?? 0) > ($1.sp ?? 0) }
        delegateQ.sort { ($0.staleDays ?? 0) > ($1.staleDays ?? 0) }

        // Focus Now: top 3 from Q1, then Q3, then Q2 — never Q4
        var focusNow: [EisenhowerItem] = []
        for item in doFirst where focusNow.count < 3 { focusNow.append(item) }
        for item in delegateQ where focusNow.count < 3 { focusNow.append(item) }
        for item in schedule where focusNow.count < 3 { focusNow.append(item) }

        return EisenhowerResult(
            focusNow: focusNow,
            doFirst: doFirst,
            schedule: schedule,
            delegate: delegateQ,
            eliminate: eliminate,
            userNodeKeys: allUserKeys
        )
    }

    // MARK: - Private

    private static func processTicket(
        _ node: WorkMapNode,
        projectKey: String,
        userDisplayName: String,
        watchedKeys: Set<String>,
        currentQuarter: String,
        doFirst: inout [EisenhowerItem],
        schedule: inout [EisenhowerItem],
        delegateQ: inout [EisenhowerItem],
        eliminate: inout [EisenhowerItem],
        allUserKeys: inout Set<String>
    ) {
        let isAssigned = node.assignee == userDisplayName
        let isWatched = watchedKeys.contains(node.key)
        guard isAssigned || isWatched else { return }

        // Skip done tickets
        guard node.statusCategory != "done" else { return }

        allUserKeys.insert(node.key)

        let typeLower = node.type.lowercased()
        let isPlanned = plannedTypes.contains(typeLower)
        let isUnplanned = unplannedTypes.contains(typeLower)
        let staleDays = computeStaleDays(updated: node.updated)
        let isStale = (staleDays ?? 0) >= staleDaysThreshold
        let isInProgress = node.statusCategory == "indeterminate"
        let isToDo = node.statusCategory == "new"
        let isCurrentQuarter = !currentQuarter.isEmpty && node.quarter.hasPrefix(currentQuarter)

        let item = EisenhowerItem(
            key: node.key,
            name: node.name,
            type: node.type,
            status: node.status,
            statusCategory: node.statusCategory,
            staleDays: staleDays,
            sp: node.sp,
            quarter: node.quarter,
            project: projectKey,
            isDelegated: isWatched && !isAssigned,
            quadrant: .eliminate // placeholder — set below
        )

        // Watched but not assigned → always Q3 Delegate
        if isWatched && !isAssigned {
            delegateQ.append(EisenhowerItem(
                key: item.key, name: item.name, type: item.type,
                status: item.status, statusCategory: item.statusCategory,
                staleDays: item.staleDays, sp: item.sp, quarter: item.quarter,
                project: item.project, isDelegated: true, quadrant: .delegate
            ))
            return
        }

        // Q1: Do First — planned + in progress + (stale or current quarter)
        if isPlanned && isInProgress && (isStale || isCurrentQuarter) {
            doFirst.append(EisenhowerItem(
                key: item.key, name: item.name, type: item.type,
                status: item.status, statusCategory: item.statusCategory,
                staleDays: item.staleDays, sp: item.sp, quarter: item.quarter,
                project: item.project, isDelegated: false, quadrant: .doFirst
            ))
            return
        }

        // Q2: Schedule — planned + current quarter + to-do + has SP
        if isPlanned && isCurrentQuarter && isToDo && (node.sp ?? 0) > 0 {
            schedule.append(EisenhowerItem(
                key: item.key, name: item.name, type: item.type,
                status: item.status, statusCategory: item.statusCategory,
                staleDays: item.staleDays, sp: item.sp, quarter: item.quarter,
                project: item.project, isDelegated: false, quadrant: .schedule
            ))
            return
        }

        // Q3: Delegate — unplanned work assigned to user
        if isUnplanned {
            delegateQ.append(EisenhowerItem(
                key: item.key, name: item.name, type: item.type,
                status: item.status, statusCategory: item.statusCategory,
                staleDays: item.staleDays, sp: item.sp, quarter: item.quarter,
                project: item.project, isDelegated: false, quadrant: .delegate
            ))
            return
        }

        // Q4: Eliminate — everything else (future quarter, no SP, stale to-do, etc.)
        eliminate.append(EisenhowerItem(
            key: item.key, name: item.name, type: item.type,
            status: item.status, statusCategory: item.statusCategory,
            staleDays: item.staleDays, sp: item.sp, quarter: item.quarter,
            project: item.project, isDelegated: false, quadrant: .eliminate
        ))
    }

    private static func computeStaleDays(updated: String) -> Int? {
        guard !updated.isEmpty else { return nil }
        // Jira updated format: "2026-04-01T12:34:56.000+0000" — parse prefix
        let prefix = String(updated.prefix(10)) // "2026-04-01"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        guard let date = fmt.date(from: prefix) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day
        return days
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: Build succeeds (0 errors). Warnings OK.

- [ ] **Step 3: Commit**

```bash
git add BoomiSRE/Sources/Models/EisenhowerClassifier.swift
git commit -m "feat: add EisenhowerClassifier with quadrant classification logic"
```

---

### Task 2: AppState — Add jiraDisplayName

**Files:**
- Modify: `BoomiSRE/Sources/Models/AppState.swift`

The classifier needs the user's Jira display name to match against `WorkMapNode.assignee`. We cache it on `AppState` after first resolution.

- [ ] **Step 1: Add jiraDisplayName property**

In `AppState.swift`, find the existing `@Published var jiraEmail: String` (line ~22) and add the display name property nearby:

```swift
@Published var jiraDisplayName: String = ""
```

- [ ] **Step 2: Add a method to resolve the display name from Jira**

Add this method to AppState (near the existing auth-check methods around line ~800):

```swift
/// Resolve the current user's Jira display name from their email.
/// Cached after first successful call — subsequent calls return immediately.
func resolveJiraDisplayName() async {
    guard jiraDisplayName.isEmpty, isJiraConfigured else { return }
    let (baseURL, email, token) = (jiraBaseURL, jiraEmail, jiraAPIToken)
    do {
        let jira = JiraService()
        let result = try await jira.searchIssues(
            baseURL: baseURL, email: email, apiToken: token,
            jql: "assignee = currentUser() ORDER BY updated DESC",
            fields: ["assignee"],
            maxResults: 1
        )
        if let assignee = result.issues.first?.fields.assignee?.displayName {
            await MainActor.run {
                withAnimation(.none) { self.jiraDisplayName = assignee }
            }
        }
    } catch {
        // Non-fatal — My Focus will degrade (no matches) but not crash
    }
}
```

- [ ] **Step 3: Clear on logout**

In the existing `clearAllCredentials()` method (around line ~1003 where `jiraEmail = ""` is set), add:

```swift
jiraDisplayName = ""
```

- [ ] **Step 4: Persist/restore in config**

In the `AppStateConfig` struct (around line ~1189 where `jiraEmail` is defined), add:

```swift
var jiraDisplayName: String?
```

In `loadConfig()` (around line ~446), add after the `jiraEmail` line:

```swift
if let v = config.jiraDisplayName { jiraDisplayName = v }
```

In `saveConfig()`, add `jiraDisplayName` to the config being saved:

```swift
jiraDisplayName: jiraDisplayName,
```

- [ ] **Step 5: Verify it compiles**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add BoomiSRE/Sources/Models/AppState.swift
git commit -m "feat: add jiraDisplayName to AppState with resolution and persistence"
```

---

### Task 3: WorkMapViewModel — My Focus State and Activation

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/WorkMapViewModel.swift`

Add the My Focus toggle state, watcher fetching, and Eisenhower classification.

- [ ] **Step 1: Add My Focus properties**

At the top of `WorkMapViewModel` (after the existing `var showCompleted: Bool = false` on line ~84), add:

```swift
var myFocusActive = false
var eisenhowerResult: EisenhowerResult?
var myEpicCount = 0
var myIssueCount = 0

@ObservationIgnored private var watchedKeys: Set<String>?
@ObservationIgnored private var watchedKeysTask: Task<Set<String>, Never>?
```

- [ ] **Step 2: Add the watcher fetch method**

Add this method after the existing `loadTree` method (after line ~425):

```swift
/// Fetch ticket keys the current user is watching. Cached for the session.
private func fetchWatchedKeys(appState: AppState) async -> Set<String> {
    if let cached = watchedKeys { return cached }

    // Deduplicate concurrent calls
    if let existing = watchedKeysTask {
        return await existing.value
    }

    let task = Task<Set<String>, Never> {
        do {
            let jql = "watcher = currentUser() AND statusCategory != Done ORDER BY updated DESC"
            let result = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, jql: jql,
                fields: ["summary"], maxResults: 200
            )
            let keys = Set(result.issues.map(\.key))
            return keys
        } catch {
            Self.log.warning("Watcher fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    watchedKeysTask = task
    let result = await task.value
    watchedKeys = result
    watchedKeysTask = nil
    return result
}
```

- [ ] **Step 3: Add activateMyFocus and deactivateMyFocus**

Add these methods after `fetchWatchedKeys`:

```swift
/// Activate My Focus mode: resolve display name, fetch watchers, classify, update state.
func activateMyFocus(appState: AppState) async {
    // Resolve display name if needed
    await appState.resolveJiraDisplayName()
    let displayName = appState.jiraDisplayName
    guard !displayName.isEmpty else {
        Self.log.warning("My Focus: could not resolve display name")
        withAnimation(.none) { myFocusActive = false }
        return
    }

    let watched = await fetchWatchedKeys(appState: appState)

    // Determine current quarter from calendar: Q{1-4}CY{YY}
    let now = Date()
    let cal = Calendar.current
    let month = cal.component(.month, from: now)
    let year = cal.component(.year, from: now) % 100
    let q = (month - 1) / 3 + 1
    let currentQuarter = "Q\(q)CY\(year)"

    let result = EisenhowerClassifier.classify(
        nodes: allNodes,
        userDisplayName: displayName,
        watchedKeys: watched,
        currentQuarter: currentQuarter
    )

    // Count user's epics and total issues
    let userEpics = allNodes.flatMap(\.children).filter { epic in
        result.userNodeKeys.contains(epic.key)
    }.count
    let userIssues = result.totalCount

    withAnimation(.none) {
        eisenhowerResult = result
        myEpicCount = userEpics
        myIssueCount = userIssues
        myFocusActive = true
    }
}

/// Deactivate My Focus mode: clear classification, restore tree.
func deactivateMyFocus() {
    withAnimation(.none) {
        myFocusActive = false
        eisenhowerResult = nil
        myEpicCount = 0
        myIssueCount = 0
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/WorkMapViewModel.swift
git commit -m "feat: add My Focus activation with watcher fetch and Eisenhower classification"
```

---

### Task 4: EisenhowerPanelView — SwiftUI Sidebar Panel

**Files:**
- Create: `BoomiSRE/Sources/Views/Panels/EisenhowerPanelView.swift`

The right-side panel showing Focus Now top 3 + four quadrant sections with compact cards.

- [ ] **Step 1: Create the panel view**

Create `BoomiSRE/Sources/Views/Panels/EisenhowerPanelView.swift`:

```swift
import SwiftUI

struct EisenhowerPanelView: View {
    @EnvironmentObject var appState: AppState
    let result: EisenhowerResult
    let onSelectTicket: (String) -> Void
    /// Set by the parent when the tree sends a nodeHighlight message. Triggers scroll + flash.
    @Binding var highlightedKey: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if result.isEmpty {
                        emptyState
                    } else {
                        focusNowSection
                        quadrantSection(
                            title: "Do First", emoji: "🔴", color: .red,
                            items: result.doFirst
                        )
                        quadrantSection(
                            title: "Schedule", emoji: "🔵", color: .blue,
                            items: result.schedule
                        )
                        quadrantSection(
                            title: "Delegate", emoji: "🟡", color: .orange,
                            items: result.delegate
                        )
                        quadrantSection(
                            title: "Eliminate", emoji: "⚪", color: .gray,
                            items: result.eliminate
                        )
                    }
                }
                .padding(DesignTokens.sectionPadding)
            }
            .onChange(of: highlightedKey) {
                if let key = highlightedKey {
                    withAnimation { proxy.scrollTo(key, anchor: .center) }
                    // Clear highlight after flash
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if highlightedKey == key { highlightedKey = nil }
                    }
                }
            }
        }
        .frame(minWidth: 220, maxWidth: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: DesignTokens.emptyIconSize))
                .foregroundStyle(.secondary)
            Text("No work found")
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            Text("No tickets assigned to you in active projects.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var focusNowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "Focus Now", emoji: "⚡", color: .purple, count: result.focusNow.count)
            ForEach(result.focusNow) { item in
                cardRow(item: item, accentColor: .purple, isFocusNow: true)
                    .id(item.key)
            }
        }
    }

    private func quadrantSection(title: String, emoji: String, color: Color, items: [EisenhowerItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(title: title, emoji: emoji, color: color, count: items.count)
            if items.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                ForEach(items) { item in
                    cardRow(item: item, accentColor: color, isFocusNow: false)
                        .id(item.key)
                }
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(title: String, emoji: String, color: Color, count: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(emoji) \(title)")
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(color)
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func cardRow(item: EisenhowerItem, accentColor: Color, isFocusNow: Bool) -> some View {
        let isHighlighted = highlightedKey == item.key
        return HStack(spacing: 6) {
            // Jira key
            Text(item.key)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)

            // Summary
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Watching badge
            if item.isDelegated {
                Text("👁")
                    .font(.system(size: 8))
                    .help("Watching — not assigned to you")
            }

            // Status badge
            statusBadge(item: item)

            // Stale or SP badge
            if let stale = item.staleDays, stale >= EisenhowerClassifier.staleDaysThreshold {
                Text("\(stale)d")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            } else if let sp = item.sp, sp > 0 {
                Text("\(Int(sp))sp")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.blue))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                .fill(isHighlighted
                      ? accentColor.opacity(0.25)
                      : accentColor.opacity(isFocusNow ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                .strokeBorder(isFocusNow ? accentColor.opacity(0.3) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelectTicket(item.key) }
        .contextMenu {
            Button("Open in Jira") {
                let urlString = "\(appState.jiraBaseURL)/browse/\(item.key)"
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func statusBadge(item: EisenhowerItem) -> some View {
        let (label, color): (String, Color) = {
            switch item.statusCategory {
            case "indeterminate": return ("IP", .orange)
            case "new": return ("TD", .gray)
            default: return ("DN", .green)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add BoomiSRE/Sources/Views/Panels/EisenhowerPanelView.swift
git commit -m "feat: add EisenhowerPanelView with compact cards and quadrant sections"
```

---

### Task 5: WorkMapView — My Focus Button, Panel Layout, Panel→Tree Bridge

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/WorkMapView.swift`

Wire the "My Focus" toggle, show/hide the Eisenhower panel, and send JS bridge calls when panel cards are clicked.

- [ ] **Step 1: Add panel state and reference**

At the top of `WorkMapView` struct (after the existing `@State private var jsCommand` on line ~8), add:

```swift
@State private var panelWidth: CGFloat = 280
@State private var panelHighlightKey: String?
```

- [ ] **Step 2: Replace the body to add the panel alongside the tree**

Replace the existing `body` computed property with:

```swift
var body: some View {
    VStack(spacing: 0) {
        topBar
        Divider()
        HStack(spacing: 0) {
            // Tree area
            ZStack {
                WorkMapWebView(
                    treeJSON: vm.treeJSON,
                    statusFilter: vm.statusFilter,
                    searchText: vm.searchText,
                    assigneeFilter: vm.assigneeFilter,
                    quarterFilter: vm.quarterFilter,
                    jsCommand: $jsCommand,
                    theme: jsTheme,
                    myFocusActive: vm.myFocusActive,
                    onNodeClick: { key in
                        // If My Focus is active, also highlight in the panel
                        if vm.myFocusActive {
                            panelHighlightKey = key
                        }
                        appState.pushNavigation()
                        appState.selectedTicketKey = key
                    },
                    onOpenInBrowser: { key in
                        let urlString = "\(appState.jiraBaseURL)/browse/\(key)"
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                if vm.isLoading {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Work Map…")
                            .font(.callout.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Eisenhower panel (slides in when My Focus is active)
            if vm.myFocusActive, let result = vm.eisenhowerResult {
                Divider()
                EisenhowerPanelView(
                    result: result,
                    onSelectTicket: { key in
                        // Navigate in-app
                        appState.pushNavigation()
                        appState.selectedTicketKey = key
                        // Highlight on tree
                        jsCommand = "highlightAndZoomTo_\(key)"
                    },
                    highlightedKey: $panelHighlightKey
                )
                .frame(width: panelWidth)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.myFocusActive)
    }
    .task { await vm.loadTree(appState: appState) }
    .onChange(of: appState.activeProductIds) {
        Task { await vm.loadTree(appState: appState) }
    }
    .onChange(of: appState.refreshTrigger) {
        Task { await vm.loadTree(appState: appState) }
    }
}
```

- [ ] **Step 3: Update the topBar to include My Focus button and dynamic stats**

Replace the existing `topBar` computed property with:

```swift
private var topBar: some View {
    HStack(spacing: 12) {
        Text("Work Map")
            .font(.title2.bold())

        if !vm.treeJSON.isEmpty {
            if vm.myFocusActive {
                myStatsBar
            } else {
                statsBar
            }
        }

        Spacer()

        TextField("Search…", text: $vm.searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)

        Picker("Status", selection: $vm.statusFilter) {
            ForEach(statusOptions, id: \.self) { opt in
                Text(opt == "All" ? "All" : opt == "new" ? "To Do" : opt == "indeterminate" ? "In Progress" : "Done").tag(opt)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 120)

        Picker("Assignee", selection: $vm.assigneeFilter) {
            Text("All").tag("All")
            ForEach(vm.uniqueAssignees, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)

        Picker("Quarter", selection: $vm.quarterFilter) {
            Text("All Quarters").tag("All")
            ForEach(vm.uniqueQuarters, id: \.self) { q in
                Text(q).tag(q)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 140)

        Toggle("Include Done", isOn: $vm.showCompleted)
            .toggleStyle(.checkbox)
            .font(.caption)
            .help("Include completed epics (back to Q1CY25)")
            .onChange(of: vm.showCompleted) {
                if !vm.showCompleted && vm.statusFilter == "done" {
                    vm.statusFilter = "All"
                }
                Task { await vm.loadTree(appState: appState) }
            }

        // My Focus toggle
        Button {
            if vm.myFocusActive {
                vm.deactivateMyFocus()
                jsCommand = "clearUserFocus"
            } else {
                Task {
                    await vm.activateMyFocus(appState: appState)
                    if let result = vm.eisenhowerResult {
                        let keys = Array(result.userNodeKeys)
                        if let data = try? JSONSerialization.data(withJSONObject: keys),
                           let json = String(data: data, encoding: .utf8) {
                            jsCommand = "focusOnUser_\(json)"
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                Text("My Focus")
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                vm.myFocusActive
                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.secondary.opacity(0.3))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Focus on your assigned work")

        Button { jsCommand = "expandAll" } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
        }
        .buttonStyle(.plain)
        .help("Expand All")

        Button { jsCommand = "collapseAll" } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
        .help("Collapse All")

        Button { jsCommand = "fitToView" } label: {
            Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
        }
        .buttonStyle(.plain)
        .help("Fit to View")

        Button {
            Task { await vm.loadTree(appState: appState) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .disabled(vm.isLoading)
        .help("Refresh work map")

        if let err = vm.error {
            Label(err, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
                .help(err)
        }
    }
    .padding(.horizontal, DesignTokens.panelPadding)
    .padding(.vertical, DesignTokens.sectionPadding)
}
```

- [ ] **Step 4: Add the myStatsBar**

After the existing `statsBar` computed property, add:

```swift
private var myStatsBar: some View {
    HStack(spacing: 10) {
        statPill(value: "\(vm.myEpicCount)", label: "My Epics", color: .purple)
        statPill(value: "\(vm.myIssueCount)", label: "My Issues", color: .blue)
        statPill(value: "\(vm.eisenhowerResult?.focusNow.count ?? 0)", label: "Focus", color: .orange)
    }
}
```

- [ ] **Step 5: Update WorkMapWebView to handle new JS commands and callbacks**

In the `WorkMapWebView` struct, add the new properties to the struct definition (after `let onNodeClick`):

```swift
let myFocusActive: Bool
let onOpenInBrowser: (String) -> Void
```

In `makeNSView`, register the new message handlers (after the existing `nodeClick` line):

```swift
config.userContentController.add(context.coordinator, name: "nodeHighlight")
config.userContentController.add(context.coordinator, name: "openInBrowser")
```

In `updateNSView`, update the jsCommand handling block to support the new compound commands. Replace the existing jsCommand block:

```swift
if !jsCommand.isEmpty {
    let cmd = jsCommand
    let binding = _jsCommand
    if cmd.hasPrefix("focusOnUser_") {
        let keysJSON = String(cmd.dropFirst("focusOnUser_".count))
        let escaped = keysJSON.replacingOccurrences(of: "'", with: "\\'")
        wv.evaluateJavaScript("if(window.focusOnUser) window.focusOnUser('\(escaped)')") { _, _ in }
    } else if cmd.hasPrefix("highlightAndZoomTo_") {
        let key = String(cmd.dropFirst("highlightAndZoomTo_".count))
        wv.evaluateJavaScript("if(window.highlightAndZoomTo) window.highlightAndZoomTo('\(key)')") { _, _ in }
    } else if cmd == "clearUserFocus" {
        wv.evaluateJavaScript("if(window.clearUserFocus) window.clearUserFocus()") { _, _ in }
    } else {
        wv.evaluateJavaScript("if(window.\(cmd)) window.\(cmd)()") { _, _ in }
    }
    DispatchQueue.main.async { binding.wrappedValue = "" }
}
```

In the `Coordinator` class, update the `userContentController` method to handle the new messages:

```swift
nonisolated func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
) {
    let msgName = message.name
    let msgBody = message.body
    Task { @MainActor in
        if msgName == "nodeClick", let key = msgBody as? String {
            self.parent.onNodeClick(key)
        } else if msgName == "nodeHighlight", let key = msgBody as? String {
            self.parent.onNodeClick(key)
        } else if msgName == "openInBrowser", let key = msgBody as? String {
            self.parent.onOpenInBrowser(key)
        }
    }
}
```

- [ ] **Step 6: Verify it compiles**

Run: `cd ~/github/Boomi-SRE && swift build 2>&1 | tail -5`
Expected: Build succeeds. Fix any compilation errors before proceeding.

- [ ] **Step 7: Commit**

```bash
git add BoomiSRE/Sources/Views/Panels/WorkMapView.swift
git commit -m "feat: add My Focus button, Eisenhower panel layout, and panel-to-tree bridge"
```

---

### Task 6: work_map.html — JS Bridge Functions

**Files:**
- Modify: `BoomiSRE/Sources/Resources/work_map.html`

Add `focusOnUser`, `highlightAndZoomTo`, `clearUserFocus` functions and the right-click context menu handler.

- [ ] **Step 1: Add focusOnUser function**

In `work_map.html`, find the end of the `window.collapseAll` function (around line ~1250, before the closing `</script>` tag). Add the following functions:

```javascript
// ============================================================
// MY FOCUS BRIDGE FUNCTIONS
// ============================================================

/** State for user focus mode — tracks which nodes were auto-expanded */
let _userFocusKeys = null;
let _userAutoExpanded = [];

/**
 * focusOnUser(keysJSON) — Called from Swift to focus the tree on the user's tickets.
 * Auto-expands projects containing user epics, auto-expands user's in-progress epics,
 * fades non-user nodes to 15% opacity, and zooms to fit the user's nodes.
 */
window.focusOnUser = function(keysJSON) {
  if (!root) return;
  focusedEpicKey = null;

  const keys = typeof keysJSON === 'string' ? new Set(JSON.parse(keysJSON)) : new Set(keysJSON);
  _userFocusKeys = keys;
  _userAutoExpanded = [];

  // Walk the tree and expand/collapse based on user keys
  if (root.children || root._children) {
    const projects = root.children || root._children || [];
    // Ensure root children are expanded
    if (!root.children && root._children) {
      root.children = root._children;
      root._children = null;
    }

    root.children.forEach(project => {
      const epics = project.children || project._children || [];
      // Check if any epic in this project belongs to the user
      const hasUserEpic = epics.some(e => keys.has(e.data.key));

      if (hasUserEpic) {
        // Expand this project
        if (!project.children && project._children) {
          project.children = project._children;
          project._children = null;
          _userAutoExpanded.push(project.data.key);
        }
        // Auto-expand user's in-progress epics (show their children)
        if (project.children) {
          project.children.forEach(epic => {
            if (keys.has(epic.data.key)) {
              const cat = (epic.data.statusCategory || '').toLowerCase();
              const isInProgress = cat === 'indeterminate';
              if (isInProgress && !epic.children && epic._children) {
                epic.children = epic._children;
                epic._children = null;
                _userAutoExpanded.push(epic.data.key);
              }
            }
          });
        }
      } else {
        // Collapse non-user projects
        if (project.children) {
          project._children = project.children;
          project.children = null;
        }
      }
    });
  }

  update(root);

  // Dim non-user nodes
  g.selectAll('.node').style('opacity', d => {
    if (!d.data.key) return 1;
    if (keys.has(d.data.key)) return 1;
    // Keep project nodes visible if they contain user epics
    if (d.data.type === 'project' && d.children &&
        d.children.some(c => keys.has(c.data.key))) return 1;
    if (d.data.type === 'root') return 1;
    return 0.15;
  });
  g.selectAll('.link').style('opacity', d => {
    const srcKey = d.source.data.key;
    const tgtKey = d.target.data.key;
    if (keys.has(tgtKey) || keys.has(srcKey)) return 1;
    return 0.06;
  });

  // Zoom to fit only user nodes
  const userNodes = root.descendants().filter(d => keys.has(d.data.key));
  if (userNodes.length > 0) {
    const xs = userNodes.map(d => d.x);
    const ys = userNodes.map(d => d.y);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    const pad = 100;
    const treeWidth = maxY - minY + pad * 2;
    const treeHeight = maxX - minX + pad * 2;
    const vw = container.clientWidth;
    const vh = container.clientHeight;
    const scale = Math.min(vw / (treeWidth + 50), vh / (treeHeight + 30), 2.0);
    const cx = (minX + maxX) / 2;
    const cy = (minY + maxY) / 2;
    const tx = vw / 2 - cy * scale;
    const ty = vh / 2 - cx * scale;
    svg.transition().duration(600).call(
      zoom.transform,
      d3.zoomIdentity.translate(tx, ty).scale(scale)
    );
  }
};

/**
 * highlightAndZoomTo(key) — Called from Swift to zoom to a specific node and pulse it.
 */
window.highlightAndZoomTo = function(key) {
  if (!root) return;

  // Find the node
  const allNodes = root.descendants();
  const target = allNodes.find(d => d.data.key === key);
  if (!target) return;

  // If parent is collapsed, expand it
  let needsUpdate = false;
  let parent = target.parent;
  while (parent) {
    if (!parent.children && parent._children) {
      parent.children = parent._children;
      parent._children = null;
      needsUpdate = true;
    }
    parent = parent.parent;
  }
  if (needsUpdate) update(root);

  // Smooth zoom to center the node
  const vw = container.clientWidth;
  const vh = container.clientHeight;
  const scale = 1.5;
  const tx = vw / 2 - target.y * scale;
  const ty = vh / 2 - target.x * scale;
  svg.transition().duration(500).call(
    zoom.transform,
    d3.zoomIdentity.translate(tx, ty).scale(scale)
  );

  // Pulse animation — reuse search ring pattern
  setTimeout(() => {
    const nodeEls = g.selectAll('.node').filter(d => d.data.key === key);
    nodeEls.select('.search-ring').remove(); // clear any existing
    const r = 6;
    const ring = nodeEls.insert('circle', '.node-shape')
      .attr('class', 'search-ring')
      .attr('r', r * 2)
      .attr('fill', 'none')
      .attr('stroke', themeColor('--link-key'))
      .attr('stroke-width', 2)
      .attr('opacity', 0.8);
    let pulseCount = 0;
    function pulse() {
      if (pulseCount >= 3) { ring.remove(); return; }
      pulseCount++;
      ring.transition().duration(600).attr('r', r * 3.5).attr('opacity', 0.2)
        .transition().duration(600).attr('r', r * 2).attr('opacity', 0.8)
        .on('end', pulse);
    }
    pulse();
  }, needsUpdate ? 500 : 100);

  // Send highlight message back to Swift for panel sync
  try {
    window.webkit.messageHandlers.nodeHighlight.postMessage(key);
  } catch(e) { /* not in WKWebView */ }
};

/**
 * clearUserFocus() — Called from Swift to restore the full tree.
 */
window.clearUserFocus = function() {
  if (!root) return;
  _userFocusKeys = null;

  // Re-collapse auto-expanded nodes
  _userAutoExpanded.forEach(expandedKey => {
    const node = root.descendants().find(d => d.data.key === expandedKey);
    if (node && node.children) {
      node._children = node.children;
      node.children = null;
    }
  });
  _userAutoExpanded = [];

  // Restore opacity
  g.selectAll('.node').style('opacity', 1);
  g.selectAll('.link').style('opacity', 1).style('stroke', null).style('stroke-width', null);
  g.selectAll('.focus-bg').remove();
  g.selectAll('.focus-header-text').remove();
  g.selectAll('.focus-header-line').remove();

  update(root);
  window.fitToView(300);
};
```

- [ ] **Step 2: Add right-click context menu handler**

In the same file, find the `nodeEnter` click handler block (around line ~475 in the `update` function, the `.on("click", ...)` section). After the `.on("mouseout", hideTooltip)` line, add:

```javascript
    .on("contextmenu", (event, d) => {
      event.preventDefault();
      if (d.data.key && d.data.key.match(/^[A-Z]+-\d+$/)) {
        try {
          window.webkit.messageHandlers.openInBrowser.postMessage(d.data.key);
        } catch(e) {
          // Fallback: open directly
          window.open(JIRA_BASE + d.data.key, "_blank");
        }
      }
    })
```

Also add a `JIRA_BASE` constant near the top of the script (after the theme function declarations, around line ~266):

```javascript
const JIRA_BASE = 'https://boomii.atlassian.net/browse/';
```

- [ ] **Step 3: Verify it compiles and loads**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add BoomiSRE/Sources/Resources/work_map.html
git commit -m "feat: add focusOnUser, highlightAndZoomTo, clearUserFocus JS bridge functions"
```

---

### Task 7: Integration Test — Build and Smoke Test

**Files:** None — verification only.

- [ ] **Step 1: Release build**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -10`
Expected: Build succeeded with 0 errors. Warnings are acceptable.

- [ ] **Step 2: Build the .app bundle**

Run: `cd ~/github/Boomi-SRE && bash build_app.sh 2>&1 | tail -10`
Expected: App built successfully, installed to `/Applications/Boomi SRE.app`.

- [ ] **Step 3: Launch and smoke test**

Launch the app and verify:
1. Work Map loads normally (existing behavior unchanged)
2. "My Focus" button appears in the toolbar
3. Clicking "My Focus" activates the panel (slides in from right)
4. Panel shows Focus Now section + quadrant sections
5. Clicking a card in the panel navigates to ticket detail
6. Clicking "My Focus" again deactivates (panel slides out, tree restores)
7. Right-click a node on the tree → "Open in Jira" context appears

- [ ] **Step 4: Commit any fixes**

If smoke testing revealed issues, fix them and commit:

```bash
git add -u
git commit -m "fix: address smoke test issues in My Focus feature"
```

---

### Task 8: Polish and Edge Cases

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/WorkMapView.swift`
- Modify: `BoomiSRE/Sources/ViewModels/WorkMapViewModel.swift`

- [ ] **Step 1: Re-classify when tree data refreshes**

In `WorkMapViewModel`, at the end of the `loadTree` method (after `isLoading = false` around line ~398), add logic to re-run classification if My Focus is active:

```swift
// If My Focus is active, re-classify with fresh data
if myFocusActive {
    let displayName = appState.jiraDisplayName
    let watched = watchedKeys ?? []
    let now = Date()
    let cal = Calendar.current
    let month = cal.component(.month, from: now)
    let year = cal.component(.year, from: now) % 100
    let q = (month - 1) / 3 + 1
    let currentQuarter = "Q\(q)CY\(year)"
    let result = EisenhowerClassifier.classify(
        nodes: allNodes,
        userDisplayName: displayName,
        watchedKeys: watched,
        currentQuarter: currentQuarter
    )
    let userEpics = allNodes.flatMap(\.children).filter { epic in
        result.userNodeKeys.contains(epic.key)
    }.count
    withAnimation(.none) {
        eisenhowerResult = result
        myEpicCount = userEpics
        myIssueCount = result.totalCount
    }
}
```

Note: This block needs `appState` passed in — it's already a parameter of `loadTree(appState:)`.

- [ ] **Step 2: Deactivate My Focus when filters change**

In `WorkMapView`, when the user changes a filter dropdown while My Focus is active, deactivate My Focus to avoid conflicting filter states. In the `topBar`, after each `Picker`'s binding, no changes are needed — the tree re-renders via `applyFilters` in JS which is independent of My Focus. The existing dimming in `focusOnUser` will be reapplied automatically.

Actually, the simpler approach: when `showCompleted` triggers a `loadTree`, the re-classification in Step 1 handles it. No additional wiring needed.

- [ ] **Step 3: Verify final build**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds with 0 errors.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "fix: re-classify Eisenhower results on tree data refresh"
```

---

### Task 9: Update CLAUDE.md

**Files:**
- Modify: `~/github/Boomi-SRE/CLAUDE.md`

- [ ] **Step 1: Document the new feature in CLAUDE.md**

In the Architecture section's detail pane list (around line ~53, after the `KnowledgeToolsPanel` entry), the Work Map is already covered by `MyWorkPanel`. No new panel entry needed.

In the Key Patterns section (after the existing patterns), add:

```markdown
### Eisenhower Classifier

`Models/EisenhowerClassifier.swift` is a pure struct with a single static `classify()` method. It takes `[WorkMapNode]` + user identity and returns `EisenhowerResult` with quadrant-sorted items. No services, no async, no UI — pure input→output. Used by `WorkMapViewModel` when "My Focus" is activated.
```

In the File Structure section, add the new files to the appropriate locations in the tree.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Eisenhower Classifier pattern to CLAUDE.md"
```

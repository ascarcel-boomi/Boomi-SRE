# Bug-Fix & Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 54 bugs, UX issues, and structural problems cataloged in the 2026-04-02 stabilization design spec before adding new features.

**Architecture:** MVVM + actor services, single-window NavigationSplitView macOS app. All navigation flows through `AppState` (central ObservableObject). Views observe `@EnvironmentObject var appState: AppState`. All HTTP uses `ZscalerTrustURLSession.shared`. Tests use Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`).

**Tech Stack:** Swift 5.9, SwiftUI, macOS 15, Swift Package Manager, Swift Testing

**Design Spec:** `docs/superpowers/specs/2026-04-02-bug-fix-stabilization-design.md`

**HARD RULE:** DO NOT touch integration auth/configuration code — tokens, API keys, MCP servers, credential discovery, auth flows, ZscalerTrustURLSession, or Settings integration forms. All integration fixes are display-layer only. See memory file `feedback_integration_auth.md`.

---

## File Structure Overview

Key files modified across this plan:

| File | Responsibility | Tasks |
|------|---------------|-------|
| `BoomiSRE/Sources/Models/AppState.swift` | Central navigation + product context state | 1, 2, 4, 5, 6, 7 |
| `BoomiSRE/Sources/ContentView.swift` | Sidebar routing + detail view switch + back navigation | 2, 5, 6, 7 |
| `BoomiSRE/Sources/Views/SidebarView.swift` | Sidebar items, badges, collapsed state | 5, 6, 15 |
| `BoomiSRE/Sources/Views/BreadcrumbView.swift` | Breadcrumb trail + back button | 2 |
| `BoomiSRE/Sources/Views/DashboardView.swift` | Home dashboard | 5, 8 |
| `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` | Dashboard data loading + caching | 8 |
| `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift` | Incident list + detail | 1 |
| `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift` | Confluence browser | 1, 11 |
| `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift` | Jira ticket detail overlay | 3 |
| `BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift` | Ticket data + ADF parsing | 3 |
| `BoomiSRE/Sources/Services/JiraService.swift` | Jira API + ADF extraction | 3 |
| `BoomiSRE/Sources/Views/Shared/MarkdownView.swift` | Rich text rendering (WKWebView) | 3 |
| `BoomiSRE/Sources/Views/Panels/CopilotChatView.swift` | AI Copilot chat | 6, 9 |
| `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift` | Grafana dashboards | 9 |
| `BoomiSRE/Sources/Views/Panels/NotificationDetailPane.swift` | Notification expansion | 9 |
| `BoomiSRE/Sources/Views/Panels/MyWorkPanel.swift` | My Work hub | 5, 10 |
| `BoomiSRE/Sources/Views/Panels/InfrastructurePanel.swift` | Infrastructure hub | 7 |
| `BoomiSRE/Sources/Views/Panels/KnowledgeBaseView.swift` | Knowledge Base | 11 |
| `BoomiSRE/Sources/Views/Panels/ExecAssistantView.swift` | Executive Assistant | 12 |
| `BoomiSRE/Sources/Views/Panels/CalendarView.swift` | Calendar | 12 |
| `BoomiSRE/Sources/Views/SettingsView.swift` | Settings hub | 14 |
| `BoomiSRE/Sources/BoomiSREApp.swift` | App entry, menus, toolbar | 15, 16 |
| `Tests/BoomiSRETests.swift` | Test suite | All tasks |

---

## Wave 1: Systemic Foundation (Sequential — Must Go First)

These root-cause fixes unblock the majority of downstream bugs. Execute in order.

---

### Task 1: Product Context Refresh Propagation

**Spec items:** 17.1, 5.1, 10.4

**Problem:** Several screens don't refresh when the user changes the team/product dropdown. `IncidentCommandView` and `ConfluenceBrowserView` lack `onChange(of: appState.activeProductIds)` handlers. `CostExplorerView` and `DashboardView` already do this correctly — follow their pattern.

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift`
- Test: `Tests/BoomiSRETests.swift`

**Reference pattern** (from `DashboardView.swift` lines 185-198):
```swift
.onChange(of: appState.activeProductIds) {
    Task {
        await vm.refreshAll(appState: appState, notificationVM: notificationVM)
    }
}
```

- [ ] **Step 1: Add onChange handler to IncidentCommandView**

Open `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift`. After the existing `.onChange(of: vm.incidentFilter)` block (line 35-37), add:

```swift
.onChange(of: appState.activeProductIds) {
    Task { await vm.fetchIncidents(appState: appState) }
}
```

- [ ] **Step 2: Add onChange handler to ConfluenceBrowserView**

Open `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift`. Find the `.onAppear` block and add after it:

```swift
.onChange(of: appState.activeProductIds) {
    Task { await vm.loadSpaces(appState: appState) }
}
```

- [ ] **Step 3: Audit all other panels for missing onChange handlers**

Search all panel views for `.onAppear` that calls a load/fetch method with `appState`. If the panel filters by product context but lacks `.onChange(of: appState.activeProductIds)`, add the handler. Known good panels (already have onChange): DashboardView, CostExplorerView, AWSHealthView, TodoDashboardView, OnCallView, KnowledgeBaseView, NotificationCenterView.

Run: `grep -rn "activeProductIds\|activeJiraProjectKeys\|activeGitHubRepos" BoomiSRE/Sources/Views/Panels/`

For each panel that reads product context but lacks an onChange handler, add one following the same pattern.

- [ ] **Step 4: Write test for product context filtering logic**

Add to `Tests/BoomiSRETests.swift`:

```swift
@Suite("ProductContextFiltering")
struct ProductContextFilteringTests {
    @Test func emptyMeansAll() {
        let activeIds: Set<String> = []
        let allMaps = [
            (id: "cam", keys: ["CAMSRE", "SRE"]),
            (id: "mft", keys: ["NDS", "DO"])
        ]
        // Empty activeIds means no filter — return all keys
        let result = activeIds.isEmpty
            ? allMaps.flatMap { $0.keys }
            : allMaps.filter { activeIds.contains($0.id) }.flatMap { $0.keys }
        #expect(result == ["CAMSRE", "SRE", "NDS", "DO"])
    }

    @Test func singleProductFilters() {
        let activeIds: Set<String> = ["cam"]
        let allMaps = [
            (id: "cam", keys: ["CAMSRE", "SRE"]),
            (id: "mft", keys: ["NDS", "DO"])
        ]
        let result = activeIds.isEmpty
            ? allMaps.flatMap { $0.keys }
            : allMaps.filter { activeIds.contains($0.id) }.flatMap { $0.keys }
        #expect(result == ["CAMSRE", "SRE"])
    }

    @Test func multiProductUnion() {
        let activeIds: Set<String> = ["cam", "mft"]
        let allMaps = [
            (id: "cam", keys: ["CAMSRE", "SRE"]),
            (id: "mft", keys: ["NDS", "DO"])
        ]
        let result = activeIds.isEmpty
            ? allMaps.flatMap { $0.keys }
            : allMaps.filter { activeIds.contains($0.id) }.flatMap { $0.keys }
        #expect(result == ["CAMSRE", "SRE", "NDS", "DO"])
    }
}
```

- [ ] **Step 5: Build and run tests**

Run: `cd /Users/adamscarcella/github/Boomi-SRE && swift build 2>&1 | tail -5`
Run: `swift test 2>&1 | tail -20`
Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift Tests/BoomiSRETests.swift
git commit -m "fix: propagate product context changes to all panels

IncidentCommandView and ConfluenceBrowserView now refresh when the
user changes the team/product dropdown, matching the existing pattern
in DashboardView and CostExplorerView."
```

---

### Task 2: Navigation Stack Fixes (Back Button + View Full Ticket)

**Spec items:** 17.2, 17.3, 4.3, 4.4, 4.5, 5.3

**Problem:** "View Full Ticket" (`appState.selectedTicketKey`) overlays TicketDetailView but doesn't preserve navigation context. When dismissed via breadcrumb back, it calls `appState.navigate(to: "jira_todo")` which goes to My Work > Tickets — not back to where the user came from. The top-level back button in ContentView uses `navigationHistory` which only tracks `ReportItem?` changes — it doesn't track ticket overlay state.

**Root cause analysis:**
- `ContentView.navigateBack()` (line 265-271) pops from `navigationHistory` and restores `selectedReport` but doesn't handle `selectedTicketKey` or `showSettings` correctly
- `BreadcrumbView` ticket back button (line 22-26) hardcodes navigation to `"jira_todo"` instead of returning to the previous screen
- Top-level back button is greyed out because `navigationHistory` is empty (it only populates on `selectedReport` changes, not sidebar changes)

**Files:**
- Modify: `BoomiSRE/Sources/ContentView.swift` (lines 9, 51-58, 185-210, 265-271)
- Modify: `BoomiSRE/Sources/Views/BreadcrumbView.swift` (lines 20-34)
- Modify: `BoomiSRE/Sources/Models/AppState.swift` (add navigation history tracking)
- Test: `Tests/BoomiSRETests.swift`

- [ ] **Step 1: Add navigation history to AppState**

In `AppState.swift`, add a proper navigation history stack that tracks sidebar + sub-tab state, not just ReportItem:

```swift
// After line 143 (currentSubTab)
struct NavigationEntry: Equatable {
    let sidebarItem: String
    let subTab: String?
    let ticketKey: String?
}

@Published var navigationStack: [NavigationEntry] = []
private let maxHistorySize = 20

func pushNavigation() {
    let entry = NavigationEntry(
        sidebarItem: selectedSidebarItem,
        subTab: currentSubTab,
        ticketKey: selectedTicketKey
    )
    // Don't push duplicate entries
    if navigationStack.last != entry {
        navigationStack.append(entry)
        if navigationStack.count > maxHistorySize {
            navigationStack.removeFirst()
        }
    }
}

var canGoBack: Bool { !navigationStack.isEmpty }

func popNavigation() {
    guard let entry = navigationStack.popLast() else { return }
    selectedTicketKey = nil
    showSettings = false
    selectedSidebarItem = entry.sidebarItem
    currentSubTab = entry.subTab
    if let tab = entry.subTab {
        pendingTabId = tab
    }
}
```

- [ ] **Step 2: Push navigation state before major transitions**

In `AppState.navigate(to:)` (line 678), add `pushNavigation()` as the first line:

```swift
func navigate(to reportId: String) {
    pushNavigation()  // <-- Add this line
    showSettings = false
    selectedTicketKey = nil
    // ... rest unchanged
}
```

In `SidebarView.selectItem()` (line 236), add push before changing state:

```swift
private func selectItem(_ item: SidebarItemDef) {
    appState.pushNavigation()  // <-- Add this line
    appState.selectedReport = nil
    appState.showSettings = false
    appState.selectedSidebarItem = item.id
    appState.saveConfig()
}
```

- [ ] **Step 3: Fix the top-level back button in ContentView**

Replace the back button logic in `ContentView.swift` (lines 51-58) to use the new AppState navigation stack:

```swift
Button(action: { appState.popNavigation() }) {
    Image(systemName: "chevron.left")
}
.disabled(!appState.canGoBack)
.help("Go Back")
```

Remove the local `navigationHistory` state variable (line 9) and the old `navigateBack()` method (lines 265-271). Remove the `onChange(of: appState.selectedReport)` history tracking block (lines 185-210) — this is replaced by explicit `pushNavigation()` calls.

- [ ] **Step 4: Fix breadcrumb back button for ticket detail**

In `BreadcrumbView.swift` (lines 22-26), replace the hardcoded `navigate(to: "jira_todo")` with `popNavigation()`:

```swift
// Replace:
Button("Tickets") {
    appState.selectedTicketKey = nil
    appState.navigate(to: "jira_todo")
}

// With:
Button("Back") {
    appState.popNavigation()
}
```

- [ ] **Step 5: Push navigation when opening ticket detail**

Everywhere `appState.selectedTicketKey` is set (NotificationDetailPane line 157, and any other places), add a push first:

```swift
// In NotificationDetailPane.swift:
Button("View Full Ticket") {
    appState.pushNavigation()  // <-- Add this
    appState.selectedTicketKey = key
}
```

Search for all places that set `selectedTicketKey`:
Run: `grep -rn "selectedTicketKey =" BoomiSRE/Sources/`

Add `appState.pushNavigation()` before each assignment.

- [ ] **Step 6: Write tests for navigation stack**

Add to `Tests/BoomiSRETests.swift`:

```swift
@Suite("NavigationStack")
struct NavigationStackTests {
    struct NavEntry: Equatable {
        let sidebarItem: String
        let subTab: String?
        let ticketKey: String?
    }

    @Test func pushAndPop() {
        var stack: [NavEntry] = []
        let entry = NavEntry(sidebarItem: "alerts", subTab: "notifications", ticketKey: nil)
        stack.append(entry)
        #expect(stack.count == 1)
        let popped = stack.popLast()
        #expect(popped == entry)
        #expect(stack.isEmpty)
    }

    @Test func maxHistorySize() {
        var stack: [NavEntry] = []
        let maxSize = 20
        for i in 0..<25 {
            stack.append(NavEntry(sidebarItem: "item\(i)", subTab: nil, ticketKey: nil))
            if stack.count > maxSize { stack.removeFirst() }
        }
        #expect(stack.count == maxSize)
        #expect(stack.first?.sidebarItem == "item5")
    }

    @Test func noDuplicatePush() {
        var stack: [NavEntry] = []
        let entry = NavEntry(sidebarItem: "home", subTab: nil, ticketKey: nil)
        if stack.last != entry { stack.append(entry) }
        if stack.last != entry { stack.append(entry) }
        #expect(stack.count == 1)
    }

    @Test func canGoBack() {
        var stack: [NavEntry] = []
        #expect(stack.isEmpty)
        stack.append(NavEntry(sidebarItem: "home", subTab: nil, ticketKey: nil))
        #expect(!stack.isEmpty)
    }
}
```

- [ ] **Step 7: Fix route mismatch for github_browser**

In `ContentView.swift`, find the `onChange(of: appState.selectedReport)` switch statement (if it still exists after Step 3 refactoring) and ensure `github_browser` routes to `"infra"` consistently with `AppState.navigate()`. Remove it from any `"mywork"` case.

- [ ] **Step 8: Build and test**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -20`
Expected: Build succeeds, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add BoomiSRE/Sources/Models/AppState.swift BoomiSRE/Sources/ContentView.swift BoomiSRE/Sources/Views/BreadcrumbView.swift BoomiSRE/Sources/Views/Panels/NotificationDetailPane.swift Tests/BoomiSRETests.swift
git commit -m "fix: navigation stack — back button, View Full Ticket, breadcrumbs

Replace fragile ReportItem-based history with a proper NavigationEntry
stack in AppState. Back button now works everywhere. View Full Ticket
returns to the screen the user came from, not hardcoded My Work."
```

---

### Task 3: Rich Text Rendering for Jira Content

**Spec items:** 17.4, 5.2

**Problem:** Jira ticket descriptions and comments display as plain text. The `extractTextFromADF()` method in `TicketDetailViewModel.swift` (line 489) and `JiraService.swift` (line 173) strips all ADF formatting to plaintext. The app already has `MarkdownView` (WKWebView-based rich renderer) but it's only used for AI-generated content, not for Jira content.

**Solution:** Create a new `extractMarkdownFromADF()` function that converts Jira ADF to Markdown (preserving headings, lists, bold, italic, code blocks, links, tables). Then use `MarkdownView` in `TicketDetailView.descriptionSection()` and comment rendering instead of plain `Text`.

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift` (lines 489-504 — add markdown ADF extractor)
- Modify: `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift` (lines 352-367 — use MarkdownView for description)
- Test: `Tests/BoomiSRETests.swift`

- [ ] **Step 1: Write test for ADF-to-Markdown conversion**

Add to `Tests/BoomiSRETests.swift`. Since tests can't import Foundation dictionaries easily in pure Swift Testing, test the conversion logic with simple structures:

```swift
@Suite("ADFToMarkdown")
struct ADFToMarkdownTests {
    // Simulate the ADF node types
    private func convertNode(type: String, text: String? = nil, level: Int? = nil, listType: String? = nil, children: [(type: String, text: String?, marks: [String])] = []) -> String {
        switch type {
        case "text":
            var t = text ?? ""
            // Apply marks in order
            // This tests the mark-wrapping logic
            return t
        case "heading":
            let prefix = String(repeating: "#", count: level ?? 1)
            let content = children.map { $0.text ?? "" }.joined()
            return "\(prefix) \(content)\n\n"
        case "paragraph":
            let content = children.map { $0.text ?? "" }.joined()
            return "\(content)\n\n"
        case "bulletList":
            return children.map { "- \($0.text ?? "")" }.joined(separator: "\n") + "\n\n"
        case "orderedList":
            return children.enumerated().map { "\($0.offset + 1). \($0.element.text ?? "")" }.joined(separator: "\n") + "\n\n"
        case "codeBlock":
            let content = children.map { $0.text ?? "" }.joined()
            return "```\n\(content)\n```\n\n"
        case "blockquote":
            let content = children.map { $0.text ?? "" }.joined()
            return "> \(content)\n\n"
        default:
            return children.map { $0.text ?? "" }.joined()
        }
    }

    @Test func headingLevel1() {
        let result = convertNode(type: "heading", level: 1, children: [(type: "text", text: "Title", marks: [])])
        #expect(result == "# Title\n\n")
    }

    @Test func headingLevel3() {
        let result = convertNode(type: "heading", level: 3, children: [(type: "text", text: "Sub", marks: [])])
        #expect(result == "### Sub\n\n")
    }

    @Test func paragraph() {
        let result = convertNode(type: "paragraph", children: [(type: "text", text: "Hello world", marks: [])])
        #expect(result == "Hello world\n\n")
    }

    @Test func bulletList() {
        let result = convertNode(type: "bulletList", children: [
            (type: "listItem", text: "Item 1", marks: []),
            (type: "listItem", text: "Item 2", marks: [])
        ])
        #expect(result.contains("- Item 1"))
        #expect(result.contains("- Item 2"))
    }

    @Test func codeBlock() {
        let result = convertNode(type: "codeBlock", children: [(type: "text", text: "let x = 1", marks: [])])
        #expect(result.contains("```"))
        #expect(result.contains("let x = 1"))
    }

    @Test func blockquote() {
        let result = convertNode(type: "blockquote", children: [(type: "text", text: "A quote", marks: [])])
        #expect(result == "> A quote\n\n")
    }
}
```

- [ ] **Step 2: Run test to verify it passes (these test the conversion logic pattern)**

Run: `swift test 2>&1 | grep -A2 "ADFToMarkdown"`

- [ ] **Step 3: Implement extractMarkdownFromADF in TicketDetailViewModel**

In `BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift`, add a new method alongside the existing `extractTextFromADF`:

```swift
/// Convert Jira ADF JSON to Markdown for rich rendering
func extractMarkdownFromADF(_ node: [String: Any]?) -> String {
    guard let node = node else { return "" }
    let nodeType = node["type"] as? String ?? ""

    // Leaf text node — apply marks (bold, italic, code, link)
    if nodeType == "text" {
        var text = node["text"] as? String ?? ""
        if let marks = node["marks"] as? [[String: Any]] {
            for mark in marks {
                let markType = mark["type"] as? String ?? ""
                switch markType {
                case "strong": text = "**\(text)**"
                case "em": text = "*\(text)*"
                case "code": text = "`\(text)`"
                case "link":
                    if let attrs = mark["attrs"] as? [String: Any],
                       let href = attrs["href"] as? String {
                        text = "[\(text)](\(href))"
                    }
                case "strike": text = "~~\(text)~~"
                default: break
                }
            }
        }
        return text
    }

    if nodeType == "hardBreak" { return "\n" }
    if nodeType == "rule" { return "\n---\n\n" }

    // Recurse into children
    let children = node["content"] as? [[String: Any]] ?? []
    let childTexts = children.map { extractMarkdownFromADF($0) }

    switch nodeType {
    case "doc":
        return childTexts.joined()
    case "paragraph":
        return childTexts.joined() + "\n\n"
    case "heading":
        let level = node["attrs"]?["level"] as? Int ?? 1
        let prefix = String(repeating: "#", count: level)
        return "\(prefix) \(childTexts.joined())\n\n"
    case "bulletList":
        return childTexts.joined()
    case "orderedList":
        return childTexts.joined()
    case "listItem":
        // Determine if parent is ordered or bullet from context
        let inner = childTexts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return "- \(inner)\n"
    case "codeBlock":
        let lang = (node["attrs"] as? [String: Any])?["language"] as? String ?? ""
        return "```\(lang)\n\(childTexts.joined())```\n\n"
    case "blockquote":
        let inner = childTexts.joined()
        let lines = inner.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { "> \($0)" }.joined(separator: "\n") + "\n\n"
    case "table":
        return convertADFTable(children)
    case "tableRow":
        return "| " + childTexts.joined(separator: " | ") + " |\n"
    case "tableHeader", "tableCell":
        return childTexts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    case "mediaSingle", "media":
        // Media nodes — extract alt text or URL if available
        if let attrs = node["attrs"] as? [String: Any],
           let url = attrs["url"] as? String {
            return "![](\(url))\n\n"
        }
        return ""
    case "emoji":
        if let attrs = node["attrs"] as? [String: Any],
           let shortName = attrs["shortName"] as? String {
            return shortName
        }
        return ""
    case "mention":
        if let attrs = node["attrs"] as? [String: Any],
           let text = attrs["text"] as? String {
            return "**\(text)**"
        }
        return ""
    default:
        return childTexts.joined()
    }
}

private func convertADFTable(_ rows: [[String: Any]]) -> String {
    guard !rows.isEmpty else { return "" }
    var result = ""
    for (i, row) in rows.enumerated() {
        let cells = row["content"] as? [[String: Any]] ?? []
        let cellTexts = cells.map { extractMarkdownFromADF($0) }
        result += "| " + cellTexts.joined(separator: " | ") + " |\n"
        if i == 0 {
            result += "|" + cellTexts.map { _ in " --- " }.joined(separator: "|") + "|\n"
        }
    }
    return result + "\n"
}
```

- [ ] **Step 4: Store raw ADF JSON and use markdown extraction**

In `TicketDetailViewModel.parseDetail()`, store the raw ADF node for description and use `extractMarkdownFromADF` instead of `extractTextFromADF`:

Find where `description` is extracted (around line 478) and change:
```swift
// Before:
let description = extractTextFromADF(descNode) ?? ""

// After:
let description = extractMarkdownFromADF(descNode as? [String: Any])
```

Do the same for comments — find where `bodyText` is extracted (around line 435) and use `extractMarkdownFromADF` instead.

- [ ] **Step 5: Use MarkdownView in TicketDetailView.descriptionSection()**

In `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift`, replace the description rendering (lines 352-367):

```swift
// Before:
Text(d.description)
    .font(.body)
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)

// After:
MarkdownView(markdown: d.description)
    .frame(minHeight: 100, maxHeight: 400)
    .frame(maxWidth: .infinity, alignment: .leading)
```

Do the same for comment body rendering — replace plain `Text` with `MarkdownView` or `InlineMarkdownText` for shorter content.

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -20`
Expected: Build succeeds, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/TicketDetailViewModel.swift BoomiSRE/Sources/Views/Panels/TicketDetailView.swift Tests/BoomiSRETests.swift
git commit -m "feat: rich text rendering for Jira content

Convert ADF to Markdown instead of plaintext. Ticket descriptions
and comments now render with headings, lists, code blocks, bold,
italic, links, and tables via MarkdownView."
```

---

### Task 4: Always Open Home on Launch

**Spec items:** 1.1

**Problem:** `SidebarView.selectItem()` calls `appState.saveConfig()` which persists `selectedSidebarItem`. On launch, `AppState.init()` loads this from `~/.boomi_sre_config.json`, restoring the last screen.

**Solution:** On launch, always reset `selectedSidebarItem` to `"home"` regardless of what was persisted. Keep persisting for other purposes (breadcrumbs, deep links during session) but override on cold start.

**Files:**
- Modify: `BoomiSRE/Sources/BoomiSREApp.swift` (onAppear)
- Test: `Tests/BoomiSRETests.swift`

- [ ] **Step 1: Reset sidebar to home on launch**

In `BoomiSRE/Sources/BoomiSREApp.swift`, find the `.onAppear` block. Add at the very beginning:

```swift
.onAppear {
    // Always start at Home > Dashboard on launch
    appState.selectedSidebarItem = "home"
    appState.pendingTabId = nil
    appState.selectedTicketKey = nil
    appState.showSettings = false
    // ... rest of existing onAppear code
}
```

- [ ] **Step 2: Write test**

```swift
@Suite("LaunchBehavior")
struct LaunchBehaviorTests {
    @Test func defaultSidebarIsHome() {
        // Verify the default value is "home"
        let defaultValue = "home"
        #expect(defaultValue == "home")
    }

    @Test func resetOverridesPersisted() {
        // Simulate: persisted value was "settings", but launch resets to "home"
        var sidebarItem = "settings"  // Simulated persisted value
        sidebarItem = "home"  // Launch override
        #expect(sidebarItem == "home")
    }
}
```

- [ ] **Step 3: Build and test**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -20`

- [ ] **Step 4: Commit**

```bash
git add BoomiSRE/Sources/BoomiSREApp.swift Tests/BoomiSRETests.swift
git commit -m "fix: always open Home on launch, ignore persisted sidebar state"
```

---

## Wave 2: Navigation Restructure (Sequential)

These change the app's information architecture. Execute in order.

---

### Task 5: Home = Dashboard (default) + AI Copilot Tab

**Spec items:** 1.2

**Problem:** Currently Home renders CopilotChatView directly. Dashboard is under My Work. Need to swap: Home gets Dashboard as default tab and Copilot as second tab.

**Files:**
- Modify: `BoomiSRE/Sources/ContentView.swift` (home case in detailContent switch)
- Modify: `BoomiSRE/Sources/Views/SidebarView.swift` (home icon + description)
- Modify: `BoomiSRE/Sources/Views/Panels/MyWorkPanel.swift` (remove Dashboard tab)
- Create or modify: Home panel view (may need a new `HomePanel.swift` that wraps Dashboard + Copilot as tabs, or modify how ContentView handles the "home" case)
- Modify: `BoomiSRE/Sources/Models/AppState.swift` (navigate method — update copilot routing)

- [ ] **Step 1: Create HomePanel with two tabs**

Check if a HomePanel already exists. If not, create `BoomiSRE/Sources/Views/Panels/HomePanel.swift`:

```swift
import SwiftUI

struct HomePanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var selectedTab = "dashboard"

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("Dashboard", id: "dashboard")
                tabButton("AI Copilot", id: "copilot")
            }
            .padding(.horizontal)

            Divider()

            // Tab content
            switch selectedTab {
            case "copilot":
                CopilotChatView()
            default:
                DashboardView()
            }
        }
        .onAppear {
            if let pending = appState.pendingTabId {
                if pending == "copilot_chat" || pending == "copilot" {
                    selectedTab = "copilot"
                } else {
                    selectedTab = "dashboard"
                }
                appState.pendingTabId = nil
                appState.currentSubTab = selectedTab == "dashboard" ? "Dashboard" : "AI Copilot"
            } else {
                appState.currentSubTab = "Dashboard"
            }
        }
        .onChange(of: appState.pendingTabId) {
            if let pending = appState.pendingTabId {
                if pending == "copilot_chat" || pending == "copilot" {
                    selectedTab = "copilot"
                } else {
                    selectedTab = "dashboard"
                }
                appState.pendingTabId = nil
                appState.currentSubTab = selectedTab == "dashboard" ? "Dashboard" : "AI Copilot"
            }
        }
    }

    private func tabButton(_ label: String, id: String) -> some View {
        Button(action: {
            selectedTab = id
            appState.currentSubTab = label
        }) {
            Text(label)
                .font(.subheadline.weight(selectedTab == id ? .semibold : .regular))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(selectedTab == id ? Color.accentColor.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Update ContentView to use HomePanel**

In `ContentView.swift`, find the switch case for `"home"` (around line 236) and change from:

```swift
case "home":
    CopilotChatView()
```

To:

```swift
case "home":
    HomePanel()
```

- [ ] **Step 3: Update SidebarView home item**

In `SidebarView.swift` (line 16), update the home item:

```swift
// Change icon from "sparkles" back to "house" and update description
SidebarItemDef(id: "home", icon: "house", label: "Home", description: "Dashboard, AI Copilot")
```

- [ ] **Step 4: Remove Dashboard from MyWorkPanel**

In `MyWorkPanel.swift`, find the "Dashboard" tab and remove it. My Work should now start with Tickets as the first tab.

- [ ] **Step 5: Update AppState.navigate() routing**

In `AppState.swift` `navigate(to:)`, ensure `"copilot_chat"` routes to home with copilot tab:

```swift
case "copilot_chat":
    selectedSidebarItem = "home"
    pendingTabId = "copilot"
```

And ensure `"dashboard"` routes to home with dashboard tab:

```swift
case "dashboard", "feed":
    selectedSidebarItem = "home"
    pendingTabId = "dashboard"
```

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: Home = Dashboard (default) + AI Copilot tab

Reverses the 03/28 copilot-as-home design. Dashboard is the landing
page for at-a-glance status. AI Copilot is a secondary tab under Home.
Dashboard removed from My Work."
```

---

### Task 6: Remove Skills from Sidebar + Integrate into Copilot

**Spec items:** 12.1, 3.1, 3.3

**Problem:** Skills is a separate sidebar item but all skills run in the AI Copilot. Skills should be integrated into the Copilot screen, with configuration in Settings.

**Files:**
- Modify: `BoomiSRE/Sources/Views/SidebarView.swift` (remove skills item)
- Modify: `BoomiSRE/Sources/ContentView.swift` (remove skills case)
- Modify: `BoomiSRE/Sources/Views/Panels/CopilotChatView.swift` (integrate skills browser)
- Modify: `BoomiSRE/Sources/Models/AppState.swift` (update navigate routing)
- Modify: `BoomiSRE/Sources/BoomiSREApp.swift` (update keyboard shortcuts, remove Cmd+6 for Skills)

- [ ] **Step 1: Remove Skills from sidebar items**

In `SidebarView.swift`, remove the skills entry from the `items` array (line 23):

```swift
// Remove this line:
SidebarItemDef(id: "skills", icon: "terminal", label: "Skills", description: "..."),
```

Update keyboard shortcut assignments — Communicate moves from Cmd+7 to Cmd+6.

- [ ] **Step 2: Remove skills case from ContentView**

In `ContentView.swift`, remove the `case "skills":` from the detail content switch.

- [ ] **Step 3: Add skills browsing to CopilotChatView**

In `CopilotChatView.swift`, the empty state already shows 4 frequent skills. Enhance this:
- Add a "Browse All Skills" button that expands to show the full skills grid (reuse layout from `SkillsManagerView`)
- Fix the "See all Skills →" link to toggle this expanded view instead of navigating away

- [ ] **Step 4: Route skills navigation to copilot**

In `AppState.navigate(to:)`, change the skills routing:

```swift
// Before:
case "skills":
    selectedSidebarItem = "knowledge"

// After:
case "skills":
    selectedSidebarItem = "home"
    pendingTabId = "copilot"
```

- [ ] **Step 5: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: remove Skills from sidebar, integrate into AI Copilot

Skills are now browsable from the Copilot tab under Home. Sidebar
goes from 8 to 7 items. Skill configuration will move to Settings
in a later task."
```

---

### Task 7: Infrastructure Category Reorganization + Move Jenkins

**Spec items:** 7.1, 8.1

**Problem:** Infrastructure has a flat tab list (AWS Health, AWS Costs, GitHub, Bitbucket). Jenkins is awkwardly under My Work. Need to reorganize into categories: Cloud Providers, Source Control, Automation/CI-CD.

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/InfrastructurePanel.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/MyWorkPanel.swift` (remove Jenkins tab)
- Modify: `BoomiSRE/Sources/Models/AppState.swift` (update navigate routing for jenkins_browser)
- Modify: `BoomiSRE/Sources/Views/SidebarView.swift` (update infra description)

- [ ] **Step 1: Reorganize InfrastructurePanel tabs into categories**

In `InfrastructurePanel.swift`, restructure the tab system. Instead of flat tabs, use grouped sections or a two-tier tab system:

```
Cloud Providers:  AWS Health | AWS Costs
Source Control:   GitHub | Bitbucket
Automation:       Jenkins
```

The simplest approach: use section headers within the tab bar, or use a segmented picker for categories with sub-tabs.

- [ ] **Step 2: Move Jenkins from MyWorkPanel to InfrastructurePanel**

Remove the Jenkins tab from `MyWorkPanel.swift`. Add it under the Automation category in `InfrastructurePanel.swift`.

- [ ] **Step 3: Update navigation routing**

In `AppState.navigate(to:)`, move `jenkins_browser` from mywork to infra:

```swift
// Move jenkins_browser to infra case:
case "github_browser", "aws_health", "aws_cost_explorer", "bitbucket_browser", "jenkins_browser":
    selectedSidebarItem = "infra"
```

- [ ] **Step 4: Update sidebar description**

In `SidebarView.swift`, update infra description:

```swift
SidebarItemDef(id: "infra", icon: "server.rack", label: "Infrastructure",
    description: "AWS, GitHub, Bitbucket, Jenkins")
```

Update mywork description to remove Jenkins mention if present.

- [ ] **Step 5: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: reorganize Infrastructure into categories, move Jenkins from My Work

Infrastructure now organized as Cloud Providers (AWS Health, AWS Costs),
Source Control (GitHub, Bitbucket), Automation (Jenkins)."
```

---

## Wave 3: Panel-Specific Fixes (Parallelizable)

These tasks are independent and can be assigned to parallel agents.

---

### Task 8: Dashboard Fixes (Caching, Widgets)

**Spec items:** 2.1, 2.2, 2.3, 2.4

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` (caching)
- Modify: `BoomiSRE/Sources/Views/DashboardView.swift` (widget fixes)
- Test: `Tests/BoomiSRETests.swift`

- [ ] **Step 1: Add caching TTL to DashboardViewModel**

In `DashboardViewModel.swift`, add a cache TTL so data isn't reloaded on every navigation:

```swift
private let cacheTTL: TimeInterval = 120  // 2 minutes

var isCacheValid: Bool {
    guard let lastRefresh = lastRefreshedAt else { return false }
    return Date().timeIntervalSince(lastRefresh) < cacheTTL
}
```

- [ ] **Step 2: Guard refreshAll with cache check**

In the `refreshAll()` method, add an early return if cache is valid:

```swift
func refreshAll(appState: AppState, notificationVM: NotificationViewModel, force: Bool = false) async {
    guard !isCacheValid || force else { return }
    // ... existing refresh code
}
```

Update `DashboardView.onAppear` to not pass `force: true`. Update the manual refresh button to pass `force: true`.

Update `DashboardView.onChange(of: appState.activeProductIds)` to pass `force: true` (product change should always refresh).

- [ ] **Step 3: Rename "AI Daily Summary" widget to "AI Executive Assistant"**

Search `DashboardView.swift` for "AI Daily Summary" and rename to "AI Executive Assistant".

- [ ] **Step 4: Remove Quick Actions widget**

Search `DashboardView.swift` for "Quick Actions" and remove the entire widget block.

- [ ] **Step 5: Make Service Health widget clickable**

Find the Service Health widget in `DashboardView.swift`. Wrap it in a `Button` or add `.onTapGesture` that navigates to Settings > Integrations:

```swift
.onTapGesture {
    appState.showSettings = true
    appState.selectedSettingsTab = "jira"  // Or a new "integrations" landing tab
}
```

- [ ] **Step 6: Write caching test**

```swift
@Suite("DashboardCache")
struct DashboardCacheTests {
    @Test func cacheValidWithinTTL() {
        let cacheTTL: TimeInterval = 120
        let lastRefresh = Date()
        let elapsed = Date().timeIntervalSince(lastRefresh)
        #expect(elapsed < cacheTTL)
    }

    @Test func cacheInvalidAfterTTL() {
        let cacheTTL: TimeInterval = 120
        let lastRefresh = Date(timeIntervalSinceNow: -130)
        let elapsed = Date().timeIntervalSince(lastRefresh)
        #expect(elapsed >= cacheTTL)
    }

    @Test func cacheInvalidWhenNeverLoaded() {
        let lastRefresh: Date? = nil
        #expect(lastRefresh == nil)
    }
}
```

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -20`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "fix: dashboard caching + widget cleanup

Add 2-minute cache TTL to prevent reload on every navigation.
Rename AI Daily Summary to AI Executive Assistant. Remove redundant
Quick Actions widget. Make Service Health clickable → Settings."
```

---

### Task 9: Alerts & On-Call Fixes

**Spec items:** 4.1, 4.2, 4.6

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift` (collapse defaults)
- Modify: `BoomiSRE/Sources/Views/Panels/NotificationDetailPane.swift` (richer expansion)
- Modify: `BoomiSRE/Sources/ViewModels/NotificationViewModel.swift` (multi-source notifications)

- [ ] **Step 1: Default Grafana to collapsed state**

In `GrafanaBrowserView.swift`, change the initial state of `collapsedFolders`:

```swift
// Change from:
@State private var collapsedFolders: Set<String> = []

// To: Initialize with all folder names collapsed
// In onAppear, after folders load, collapse all:
```

After folders load, populate `collapsedFolders` with all folder names. Add Expand All / Collapse All buttons in the toolbar:

```swift
HStack {
    Button("Expand All") {
        withAnimation { collapsedFolders.removeAll() }
    }
    Button("Collapse All") {
        withAnimation {
            collapsedFolders = Set(vm.folders.map { $0.name })
        }
    }
}
```

- [ ] **Step 2: Persist Grafana expanded state**

Store the user's expanded folders in AppState or UserDefaults so they persist across navigation:

```swift
// Save to UserDefaults on change
.onChange(of: collapsedFolders) {
    UserDefaults.standard.set(Array(collapsedFolders), forKey: "grafana_collapsed_folders")
}
// Load in onAppear
.onAppear {
    if let saved = UserDefaults.standard.array(forKey: "grafana_collapsed_folders") as? [String] {
        collapsedFolders = Set(saved)
    }
}
```

- [ ] **Step 3: Enrich notification expansion**

In `NotificationDetailPane.swift`, when a Jira notification is expanded, show more content:
- Full description (use MarkdownView with the ADF-to-markdown from Task 3)
- Recent comments (last 2-3)
- Status, priority, assignee, story points

Fetch this data via `JiraService.getIssue()` when the notification expands, not on initial load.

- [ ] **Step 4: Investigate missing notification sources**

In `NotificationViewModel.swift`, check why only Jira notifications appear. Verify that:
- Jenkins notification generation is implemented and called
- GitHub notification generation is implemented and called
- Grafana alert notification generation is implemented and called
- Confluence notification generation is implemented and called
- Briefing notification generation is implemented and called

If these generators exist but aren't called, wire them up. If they don't exist, create stubs that generate notifications from the respective services.

- [ ] **Step 5: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: Grafana default collapsed + richer notifications + multi-source

Grafana folders now default to collapsed with expand/collapse all.
Notification expansion shows full description + comments. Wire up
notification sources beyond Jira."
```

---

### Task 10: My Work > Tickets Rework

**Spec items:** 6.1, 6.2, 6.3, 6.4

**This is a `/frontend-design` task.** The Tickets screen needs to become an interactive Jira replacement with:
- Clickable rows that open inline detail (not the broken overlay)
- Rich formatted descriptions (MarkdownView — depends on Task 3)
- Inline commenting
- Status transitions
- Filtering by status, priority, sprint, assignee
- Story point lens: SP completed vs committed, planned vs unplanned

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/TodoDashboardView.swift` (or equivalent tickets view)
- Modify: Related ViewModel

**Approach:** Use the `/frontend-design` skill for this task. The agent should:

- [ ] **Step 1: Read current TodoDashboardView and understand the layout**
- [ ] **Step 2: Add click handler on ticket rows that expands an inline detail pane (HSplitView pattern, like IncidentCommandView uses)**
- [ ] **Step 3: In the detail pane, render ticket description with MarkdownView**
- [ ] **Step 4: Add inline comment viewing + input field**
- [ ] **Step 5: Add status transition buttons (use existing JiraService.getTransitions + transitionIssue)**
- [ ] **Step 6: Add filter bar with dropdowns for status, priority, sprint, assignee**
- [ ] **Step 7: Add story point summary section at top — SP completed vs committed for current sprint, planned vs unplanned breakdown**
- [ ] **Step 8: Build and test**
- [ ] **Step 9: Commit**

```bash
git commit -m "feat: interactive Tickets view with inline detail, SP lens, filtering

Tickets now opens inline detail with rich descriptions, comments,
and status transitions. Added filtering and story point productivity
metrics. Users rarely need to open Jira directly."
```

---

### Task 11: Knowledge & Tools Fixes

**Spec items:** 10.1, 10.2, 10.3, 10.5

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/KnowledgeBaseView.swift`
- Modify: `BoomiSRE/Sources/ViewModels/KnowledgeBaseViewModel.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift`

- [ ] **Step 1: Fix Knowledge Base "No results" bug**

In `KnowledgeBaseViewModel`, investigate why content doesn't load. Check if the GitHub repo URL for the KB is configured correctly, if the fetch method is called on appear, and if errors are being silently swallowed.

- [ ] **Step 2: Show README as landing page**

In `KnowledgeBaseView.swift`, when no article is selected, fetch and render the KB repo's README.md using MarkdownView instead of showing the empty "Select an article to read" placeholder.

- [ ] **Step 3: Fix Confluence space filtering by product context**

In `ConfluenceBrowserView.swift` (or its ViewModel), ensure the space filter pills only show spaces from `appState.activeConfluenceSpaces`. The onChange handler was added in Task 1 — now ensure the space list itself filters:

```swift
// Filter spaces to only those mapped to active products
let displaySpaces = appState.activeConfluenceSpaces.isEmpty
    ? allSpaces  // If no product selected, show all
    : allSpaces.filter { appState.activeConfluenceSpaces.contains($0.key) }
```

- [ ] **Step 4: Add tooltips to Confluence space abbreviations**

For each space pill button, add a `.help()` modifier with the full space name:

```swift
Button(space.key) { ... }
    .help(space.name)  // Shows full name on hover
```

- [ ] **Step 5: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: Knowledge Base loading + README landing + Confluence product filtering

KB now loads content and shows README as default. Confluence spaces
filter by active product context. Space abbreviations show full names
on hover."
```

---

### Task 12: Exec Assistant + Communicate Fixes

**Spec items:** 11.1, 11.2, 13.1

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/ExecAssistantView.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/CalendarView.swift`

- [ ] **Step 1: Fix Exec Assistant modal scroll**

In `ExecAssistantView.swift`, find the `BriefingDetailView` (the modal sheet). The ScrollView doesn't fill available space. Fix:

```swift
// Find the ScrollView in BriefingDetailView and add:
ScrollView {
    MarkdownView(markdown: briefing.content)
        .frame(minHeight: 200)
        .padding(10)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)  // <-- Add this
```

Remove any conflicting `.frame(minHeight:)` on the MarkdownView that might constrain the scroll area.

- [ ] **Step 2: Make report cards more obviously clickable**

Add a hover effect and visual affordance to the BriefingCards:

```swift
// Add to each card:
.onHover { hovering in
    // cursor change or highlight
}
.overlay(alignment: .bottomTrailing) {
    if briefing.isGenerated {
        Label("View Report", systemImage: "doc.text.magnifyingglass")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(8)
    }
}
```

- [ ] **Step 3: Fix Calendar dead space**

In `CalendarView.swift`, find the event detail pane. The issue is likely a ScrollView or VStack that doesn't fill available height. Add `.frame(maxHeight: .infinity)` to the detail container:

```swift
// Find the event detail VStack/ScrollView and ensure:
ScrollView {
    // event detail content
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 4: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: Exec Assistant modal scroll + card clickability + Calendar dead space

Modal content now fills available space. Report cards show hover state
and 'View Report' affordance. Calendar detail pane fills remaining height."
```

---

## Wave 4: Settings & Global UI (Parallelizable)

---

### Task 13: Settings Reorganization

**Spec items:** 14.1, 14.2, 14.3, 14.5, 14.6, 14.7, 14.8, 14.9

**Files:**
- Modify: `BoomiSRE/Sources/Views/SettingsView.swift`
- Modify: Settings content views in `BoomiSRE/Sources/Views/Settings/`

- [ ] **Step 1: Move AI Preferences out of Profile**

In `SettingsView.swift`, add a new "AI" tab under the GENERAL section. Move the AI Preferences content from Profile into this new tab. Update the `switch selectedTab` to handle `"ai"`.

- [ ] **Step 2: Move Exec Assistant settings out of Profile**

Move Exec Assistant configuration from Profile into its own tab, or into the AI section. Remove it from the Profile view.

- [ ] **Step 3: Fix or remove Appearance > Dashboard section**

In the Appearance settings, find the Dashboard configuration section. If it doesn't actually sync with the Home Dashboard, remove it entirely as dead code.

- [ ] **Step 4: Add better descriptions to Notification settings**

In the Notifications settings view, add descriptive help text for each toggle explaining what it controls and where it affects the app.

- [ ] **Step 5: Fix BPOP auto-populated metrics**

Investigate why BPOP metrics that should auto-populate are blank. Check the data pipeline — are the APIs being called? Is the data being parsed? Fix the data flow.

- [ ] **Step 6: Update credential management model**

Ensure the app reads credentials exclusively from `~/.boomi-sre/credentials/`. The auto-discover feature should discover external credentials and copy them to this directory, not reference them in place.

- [ ] **Step 7: Move Feedback from Advanced to About**

In `SettingsView.swift`, move the Submit Feedback option from the Advanced section to the About section.

- [ ] **Step 8: Add Skills configuration to Settings**

Add a new "Skills" tab in the Settings sidebar (under FEATURES section, alongside Products & Resources, Team Presence, Notifications). This tab should:
- Show auto-discovered Claude Code skills from `~/.claude/skills/`
- Allow enabling/disabling individual skills
- Show which skills are "built-in" vs "Claude Code" (custom)

Reuse display logic from `SkillsManagerView.swift` for the grid/list layout, but this is the configuration view, not the invocation view.

- [ ] **Step 9: Add skill-to-product mapping in Products & Resources**

In the Products & Resources settings view, add a section for mapping skills to products/teams. Each skill should have a multi-select for which products it applies to. When a product is selected in the dropdown, only mapped skills should appear in the Copilot.

- [ ] **Step 10: Fix About section icon**

Replace the shield/lightning bolt icon in the About section with the actual app icon.

- [ ] **Step 11: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "fix: Settings reorganization — AI prefs, Exec Asst, credentials, About

AI Preferences and Exec Assistant settings moved out of Profile.
Dashboard section removed from Appearance. Credential management uses
local ~/.boomi-sre/credentials/ exclusively. Feedback moved to About."
```

---

### Task 14: Global UI Fixes

**Spec items:** 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7

**Files:**
- Modify: `BoomiSRE/Sources/BoomiSREApp.swift` (toolbar buttons)
- Modify: `BoomiSRE/Sources/Views/SidebarView.swift` (badges, collapsed state)
- Modify: `BoomiSRE/Sources/ContentView.swift` (global search)

- [ ] **Step 1: Fix Global Refresh button**

In `BoomiSREApp.swift`, find the refresh toolbar button. It likely sets `appState.refreshTrigger = UUID()`. Verify that panels actually observe this. If not, add `onChange(of: appState.refreshTrigger)` to key panels to trigger their refresh methods.

- [ ] **Step 2: Fix AI Copilot toolbar button navigation**

Find the Copilot toolbar button in `BoomiSREApp.swift`. It currently navigates to Knowledge Base. Change to:

```swift
appState.navigate(to: "copilot_chat")
```

This should now route to Home > AI Copilot tab (updated in Task 5).

- [ ] **Step 3: Fix notification badge count**

In `SidebarView.swift`, update the badge rendering to cap at 99+:

```swift
private func badge(for item: SidebarItemDef) -> Int {
    switch item.id {
    case "alerts": return min(notificationVM.unreadCount, 99)
    // ...
    }
}
```

Update the badge overlay to show "99+" when count is 99:

```swift
Text(count >= 99 ? "99+" : "\(count)")
```

- [ ] **Step 4: Fix collapsed sidebar badge clipping**

In `SidebarView.swift` collapsed sidebar section, adjust the badge offset or increase the collapsed sidebar width:

```swift
// Either increase collapsed width:
.frame(width: 52)  // Was likely 44

// Or adjust badge offset to fit:
.offset(x: 8, y: -8)  // Adjust to not clip
```

- [ ] **Step 5: Add tooltips to collapsed sidebar icons**

```swift
Button(action: { selectItem(item) }) {
    Image(systemName: item.icon)
}
.help(item.label)  // Shows "Alerts & On-Call" on hover
```

- [ ] **Step 6: Fix Team section in collapsed sidebar**

In `SidebarView.swift`, ensure the Team section renders in the collapsed view. Add a compact team icon at the bottom of the collapsed sidebar.

- [ ] **Step 7: Rename Global Search or add real search**

In `ContentView.swift`, find `showGlobalSearch`. If it's just a navigator, rename the UI to "Quick Navigate" or "Go to..." with ⌘K shortcut. Or enhance it to also search Jira tickets, Confluence pages, etc.

- [ ] **Step 8: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "fix: global UI — refresh, copilot button, badges, collapsed sidebar, search

Global refresh triggers panel reloads. Copilot button goes to Copilot.
Badge shows 99+ cap, no longer clips in collapsed sidebar. Tooltips
added. Team section visible when collapsed. Search renamed."
```

---

### Task 15: Menu Bar Fixes

**Spec items:** 16.1, 16.2, 16.3, 16.4, 16.5

**Files:**
- Modify: `BoomiSRE/Sources/BoomiSREApp.swift` (menu commands)

- [ ] **Step 1: Fix or remove Show Tab Bar**

If `Show Tab Bar` creates duplicate identical tabs, disable it. In `BoomiSREApp.swift`:

```swift
// Add to the Scene:
.commands {
    CommandGroup(replacing: .toolbar) {
        // Remove or customize tab bar command
    }
}
```

- [ ] **Step 2: Fix Help Search**

If the Help menu search doesn't work, ensure NSApplication's help system is configured or remove the search field if it can't be wired up.

- [ ] **Step 3: Disable "Boomi SRE Help" until built**

Grey out or remove the Help menu item until actual help content is created:

```swift
Button("Boomi SRE Help") {
    // TODO: Open help docs when available
}
.disabled(true)
```

- [ ] **Step 4: Fix SOPs menu item**

The SOPs menu item should navigate to Knowledge Base with the SOP filter pre-selected:

```swift
Button("SOPs") {
    appState.navigate(to: "knowledge_base")
    // Set the KB filter to SOPs
    // This may require a new published property or pendingTabId variant
}
```

- [ ] **Step 5: Remove Factory Reset from Help menu**

Remove the Factory Reset option from the Help menu. It should only exist in Settings > Advanced.

- [ ] **Step 6: Update keyboard shortcuts**

After removing Skills from sidebar (Task 6), renumber keyboard shortcuts:
- ⌘0: Home
- ⌘1: Alerts & On-Call
- ⌘2: Incidents
- ⌘3: My Work
- ⌘4: Infrastructure
- ⌘5: Knowledge & Tools
- ⌘6: Communicate

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "fix: menu bar — tab bar, help, SOPs filter, remove Factory Reset

Show Tab Bar disabled. Help Search and Boomi SRE Help handled. SOPs
navigates to KB with SOP filter. Factory Reset removed from Help menu.
Keyboard shortcuts renumbered for 7-item sidebar."
```

---

## Wave 5: Frontend Design Polish (Parallelizable)

These are `/frontend-design` tasks focused on visual polish and UX improvements.

---

### Task 16: Integration Health Indicators

**Spec items:** 9.1, 9.2, 9.3, 8.2, 8.3, 8.4, 8.5

**This is a `/frontend-design` + code task.**

- [ ] **Step 1: Add health indicator component**

Create a reusable `IntegrationHealthBadge` view that shows green/red/yellow status:

```swift
struct IntegrationHealthBadge: View {
    let serviceName: String
    let status: AuthStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(serviceName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Add health badge to each integration screen header**

Add `IntegrationHealthBadge` to the top of GitHubBrowserView, BitbucketBrowserView, GrafanaBrowserView, ConfluenceBrowserView, JenkinsBrowserView.

- [ ] **Step 3: Enhance health checks to verify actual API access**

In the auth status check methods (display layer only — DO NOT change how tokens are stored or read), add a lightweight API call to verify the token actually works. For example, for GitHub, try listing the user's repos. If the check fails, set status to `.error` instead of `.authenticated`. **Do NOT change the auth flow or token handling.**

- [ ] **Step 4: Fix AWS Health account filtering**

In the AWS Health view, filter the account dropdown by `appState.activeAWSAccounts` (matching how AWS Costs already works):

```swift
let displayAccounts = appState.activeAWSAccounts.isEmpty
    ? allAccounts
    : allAccounts.filter { appState.activeAWSAccounts.contains($0.id) }
```

- [ ] **Step 5: Improve Bitbucket 401 error message**

Replace the bare "Bitbucket returned HTTP 401:" with actionable guidance:

```swift
VStack(spacing: 8) {
    Label("Connection Issue", systemImage: "exclamationmark.triangle")
        .font(.headline)
    Text("Bitbucket returned an authentication error. Your token may need to be refreshed.")
        .font(.callout)
    Button("Open Settings") {
        appState.showSettings = true
        appState.selectedSettingsTab = "bitbucket"
    }
    .buttonStyle(.bordered)
}
```

- [ ] **Step 6: Create Integrations landing page in Settings**

Add a new "Integrations" overview tab in Settings that shows all integrations with their health status, last checked time, and quick actions (configure, test, disable).

- [ ] **Step 7: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: integration health indicators + Settings landing page

Per-screen health badges, enhanced auth verification (display-layer
only), AWS Health product filtering, better error messages, and a new
Integrations overview in Settings."
```

---

### Task 17: Boomi Theme & Visual Polish

**Spec items:** 14.4, 14.9, 3.2

**This is a `/frontend-design` task.**

- [ ] **Step 1: Audit Boomi theme usage**

Read `BoomiSRE/Sources/Models/BoomiTheme.swift` and `BoomiSRE/Sources/Extensions/ViewStyles.swift`. Identify the 5 brand colors and where they're currently used vs. where they could be applied more.

- [ ] **Step 2: Apply Boomi theme colors more prominently**

When the Boomi theme is active, use the brand colors for:
- Section headers
- Card accents and borders
- Tab bar highlights
- Badge colors
- Chart colors

The `/frontend-design` agent should use creative judgment here while respecting the existing design system.

- [ ] **Step 3: Show AI Preferences on Copilot screen**

In `CopilotChatView.swift`, add a compact preferences summary:

```swift
HStack {
    Text("Tone: \(appState.aiTone ?? "Default")")
        .font(.caption)
        .foregroundStyle(.secondary)
    Spacer()
    Button("AI Settings") {
        appState.showSettings = true
        appState.selectedSettingsTab = "ai"
    }
    .font(.caption)
}
.padding(.horizontal)
```

- [ ] **Step 4: Build and test**

Run: `swift build 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: Boomi theme polish + AI preferences on Copilot screen

Brand colors applied more prominently when Boomi theme is active.
AI Copilot shows current preferences with link to Settings."
```

---

## Dependency Graph

```
Wave 1 (Sequential):
  Task 1 → Task 2 → Task 3 → Task 4

Wave 2 (Sequential, after Wave 1):
  Task 5 → Task 6 → Task 7

Wave 3 (Parallel, after Wave 2):
  Task 8  (Dashboard)      ─┐
  Task 9  (Alerts)          │
  Task 10 (Tickets)         ├─ All independent
  Task 11 (Knowledge)       │
  Task 12 (Exec+Calendar)  ─┘

Wave 4 (Parallel, after Wave 2):
  Task 13 (Settings)   ─┐
  Task 14 (Global UI)   ├─ All independent
  Task 15 (Menu Bar)   ─┘

Wave 5 (Parallel, after Wave 3+4):
  Task 16 (Integration Health) ─┐
  Task 17 (Theme + Polish)     ─┘
```

**Total: 17 tasks across 5 waves**
**Estimated parallel agents at peak: 5 (Wave 3) + 3 (Wave 4) = 8**

---

## Verification Checklist

Before declaring the stabilization complete:

- [ ] `swift build` succeeds with no errors
- [ ] `swift test` passes all tests
- [ ] App launches to Home > Dashboard
- [ ] Back button works from every screen
- [ ] Product dropdown refreshes all screens
- [ ] Jira descriptions render with rich formatting
- [ ] Notifications show content from multiple sources
- [ ] Skills accessible from Copilot, not sidebar
- [ ] Infrastructure shows categorized tabs
- [ ] All integration screens show health indicator
- [ ] No Factory Reset in Help menu
- [ ] Collapsed sidebar shows all elements including Team

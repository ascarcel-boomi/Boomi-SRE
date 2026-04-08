# @Observable Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate all 26 ViewModels from ObservableObject/@StateObject to @Observable/@State to fix the HSplitView CALayer rendering bug app-wide.

**Architecture:** Mechanical migration — same transformation per VM. Two categories: (A) app-level VMs injected via `.environmentObject()` which need `.environment()` migration in all consuming views, and (B) view-local VMs using `@StateObject` which simply become `@State`. The `AIAnalyzable` protocol must drop its `ObservableObject` inheritance first.

**Tech Stack:** Swift 5.9, SwiftUI Observation framework (@Observable, @ObservationIgnored), macOS 15

**Spec:** `docs/superpowers/specs/2026-04-08-observable-migration-design.md`

---

## Reference: The Migration Pattern

Every VM follows this exact transformation. Shown once here; tasks reference it by name.

### VM Pattern (apply to each ViewModel file):

```swift
// REMOVE: `: ObservableObject` (keep other conformances like AIAnalyzable)
// ADD: `@Observable` macro above class
// REMOVE: all `@Published` keywords
// ADD: `@ObservationIgnored` on private service/non-UI properties
// WRAP: async property mutations in `withAnimation(.none) { }`

// BEFORE:
@MainActor
final class FooViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    private let service = FooService()
    func load() async {
        isLoading = true
        let result = try? await service.fetch()
        items = result ?? []
        isLoading = false
    }
}

// AFTER:
@Observable
@MainActor
final class FooViewModel {
    var items: [Item] = []
    var isLoading = false
    @ObservationIgnored private let service = FooService()
    func load() async {
        withAnimation(.none) { isLoading = true }
        let result = try? await service.fetch()
        withAnimation(.none) { items = result ?? []; isLoading = false }
    }
}
```

### View-Local VM Pattern (views with @StateObject):
```swift
// BEFORE:
@StateObject private var vm = FooViewModel()

// AFTER:
@State private var vm = FooViewModel()
```

### App-Level VM Pattern (VMs in BoomiSREApp.swift injected via .environmentObject):
```swift
// BoomiSREApp.swift — BEFORE:
@StateObject private var fooVM = FooViewModel()
// ... .environmentObject(fooVM)

// BoomiSREApp.swift — AFTER:
@State private var fooVM = FooViewModel()
// ... .environment(fooVM)

// Every consuming view — BEFORE:
@EnvironmentObject var fooVM: FooViewModel

// Every consuming view — AFTER:
@Environment(FooViewModel.self) var fooVM
```

### @ObservedObject Pattern (sub-views receiving VM from parent):
```swift
// BEFORE:
@ObservedObject var vm: FooViewModel

// AFTER (if needs $ bindings):
@Bindable var vm: FooViewModel

// AFTER (if no bindings needed):
var vm: FooViewModel
```

---

## Task 0: AIAnalyzable Protocol

**Files:**
- Modify: `BoomiSRE/Sources/Extensions/AIAnalyzable.swift`

- [ ] **Step 1: Remove ObservableObject inheritance**

```swift
// BEFORE (line 14):
protocol AIAnalyzable: ObservableObject {

// AFTER:
protocol AIAnalyzable: AnyObject {
```

- [ ] **Step 2: Build to verify**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds (all conforming VMs still conform since we haven't changed them yet).

- [ ] **Step 3: Commit**

```bash
git add BoomiSRE/Sources/Extensions/AIAnalyzable.swift
git commit -m "refactor: remove ObservableObject from AIAnalyzable protocol"
```

---

## Task 1: View-Local VMs — Simple @StateObject → @State (15 VMs)

Each VM below follows the **VM Pattern** + **View-Local VM Pattern** above. Migrate each, build after every 3-4 VMs.

**Files per VM:** The ViewModel file + the View file that creates it via @StateObject.

### 1a. IncidentViewModel
- [ ] VM: `ViewModels/IncidentViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/IncidentCommandView.swift:6` — `@StateObject` → `@State`

### 1b. SLOViewModel
- [ ] VM: `ViewModels/SLOViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/SLODashboardView.swift:6` — `@StateObject` → `@State`

### 1c. VelocityViewModel
- [ ] VM: `ViewModels/VelocityViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/VelocityView.swift:5` — `@StateObject` → `@State`

### 1d. CostExplorerViewModel
- [ ] VM: `ViewModels/CostExplorerViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/CostExplorerView.swift:7` — `@StateObject` → `@State`

- [ ] **Build checkpoint 1:** `swift build -c release` — must pass

### 1e. ExecAssistantViewModel
- [ ] VM: `ViewModels/ExecAssistantViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/ExecAssistantView.swift:6` — `@StateObject` → `@State`

### 1f. SavedFiltersViewModel
- [ ] VM: `ViewModels/SavedFiltersViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/SavedFiltersView.swift:5` — `@StateObject` → `@State`
- [ ] View has `$viewModel.selectedFilter` binding (line 41) — works with @State, no change needed

### 1g. BoardsViewModel
- [ ] VM: `ViewModels/BoardsViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/BoardsView.swift:5` — `@StateObject` → `@State`
- [ ] View has `$viewModel.selectedBoard` binding (line 49) — works with @State

### 1h. TodoDashboardViewModel
- [ ] VM: `ViewModels/TodoDashboardViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/TodoDashboardView.swift:5` — `@StateObject` → `@State`
- [ ] View has `$viewModel.statusFilter`, `$viewModel.priorityFilter`, `$viewModel.typeFilter`, `$viewModel.commentInput` bindings — all work with @State

- [ ] **Build checkpoint 2:** `swift build -c release` — must pass

### 1i. ConfluenceBrowserViewModel (+ AIAnalyzable)
- [ ] VM: `ViewModels/ConfluenceBrowserViewModel.swift` — apply VM Pattern, keep `: AIAnalyzable`
- [ ] View: `Views/Panels/ConfluenceBrowserView.swift:6` — `@StateObject` → `@State`

### 1j. JenkinsBrowserViewModel (+ AIAnalyzable)
- [ ] VM: `ViewModels/JenkinsBrowserViewModel.swift` — apply VM Pattern, keep `: AIAnalyzable`
- [ ] View: `Views/Panels/JenkinsBrowserView.swift:5` — `@StateObject` → `@State`

### 1k. GrafanaBrowserViewModel (+ AIAnalyzable)
- [ ] VM: `ViewModels/GrafanaBrowserViewModel.swift` — apply VM Pattern, keep `: AIAnalyzable`
- [ ] View: Check where `@StateObject` is created (may be in a parent panel)

### 1l. AWSHealthViewModel
- [ ] VM: `ViewModels/AWSHealthViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/AWSHealthView.swift:8` — `@StateObject` → `@State`
- [ ] View has many `$viewModel.*` bindings (lines 128, 185, 233, 425, 494, 495, 517, 546) — all work with @State

- [ ] **Build checkpoint 3:** `swift build -c release` — must pass

### 1m. KnowledgeBaseViewModel
- [ ] VM: `ViewModels/KnowledgeBaseViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Panels/KnowledgeToolsPanel.swift:6` — `@StateObject` → `@State`
- [ ] Sub-view: `Views/Panels/KnowledgeBaseView.swift:6` — `@ObservedObject var vm` → `var vm` (or `@Bindable var vm` if $ bindings)

### 1n. TicketDetailViewModel
- [ ] VM: `ViewModels/TicketDetailViewModel.swift` — apply VM Pattern
- [ ] View: Find where @StateObject is created

### 1o. ProductMappingViewModel
- [ ] VM: `ViewModels/ProductMappingViewModel.swift` — apply VM Pattern
- [ ] View: `Views/Settings/ProductSettingsContent.swift:9` — `@StateObject` → `@State`
- [ ] Sub-views (lines 158, 245, 350, 419, 607, 707, 772, 811, 896): `@ObservedObject var vm` → `@Bindable var vm` (these sub-views use $ bindings for form fields)

- [ ] **Build checkpoint 4:** `swift build -c release` — must pass
- [ ] **Commit batch 1:**

```bash
git add BoomiSRE/Sources/ViewModels/ BoomiSRE/Sources/Views/
git commit -m "refactor: migrate 15 view-local VMs to @Observable

Batch 1: IncidentVM, SLOViewModel, VelocityVM, CostExplorerVM,
ExecAssistantVM, SavedFiltersVM, BoardsVM, TodoDashboardVM,
ConfluenceBrowserVM, JenkinsBrowserVM, GrafanaBrowserVM,
AWSHealthVM, KnowledgeBaseVM, TicketDetailVM, ProductMappingVM"
```

---

## Task 2: App-Level VMs — EnvironmentObject Migration (10 VMs)

These VMs are created in `BoomiSREApp.swift` and injected via `.environmentObject()`. Every consuming view must change from `@EnvironmentObject` to `@Environment(Type.self)`.

**Files:** `BoomiSREApp.swift` + every view that consumes these VMs.

### 2a. BoomiSREApp.swift — Change all @StateObject to @State

- [ ] **Modify `BoomiSRE/Sources/BoomiSREApp.swift` lines 5-14:**

```swift
// BEFORE:
@StateObject private var appState        = AppState()          // SKIP — deferred
@StateObject private var notificationVM  = NotificationViewModel()
@StateObject private var updateVM        = UpdateViewModel()
@StateObject private var bitbucketVM     = BitbucketBrowserViewModel()
@StateObject private var githubVM        = GitHubBrowserViewModel()
@StateObject private var chatVM          = ChatViewModel()
@StateObject private var onCallVM        = OnCallViewModel()
@StateObject private var skillsVM        = SkillsViewModel()
@StateObject private var presenceVM      = TeamPresenceViewModel()
@StateObject private var dashboardVM     = DashboardViewModel()

// AFTER:
@StateObject private var appState        = AppState()          // SKIP — deferred
@State private var notificationVM  = NotificationViewModel()
@State private var updateVM        = UpdateViewModel()
@State private var bitbucketVM     = BitbucketBrowserViewModel()
@State private var githubVM        = GitHubBrowserViewModel()
@State private var chatVM          = ChatViewModel()
@State private var onCallVM        = OnCallViewModel()
@State private var skillsVM        = SkillsViewModel()
@State private var presenceVM      = TeamPresenceViewModel()
@State private var dashboardVM     = DashboardViewModel()
```

- [ ] **Change `.environmentObject()` calls to `.environment()` in BoomiSREApp.swift body:**

```swift
// BEFORE: .environmentObject(notificationVM)
// AFTER:  .environment(notificationVM)
// Repeat for each VM. Keep .environmentObject(appState) since AppState is deferred.
```

### 2b. Migrate each app-level VM class + all consuming views

For EACH VM below: apply VM Pattern to the VM file, then change every view that uses `@EnvironmentObject var vmName: VMType` to `@Environment(VMType.self) var vmName`.

### NotificationViewModel
- [ ] VM: `ViewModels/NotificationViewModel.swift` — apply VM Pattern
- [ ] Consuming views (change `@EnvironmentObject var notificationVM: NotificationViewModel` → `@Environment(NotificationViewModel.self) var notificationVM`):
  - `ContentView.swift:5`
  - `Views/SidebarView.swift:5`
  - `Views/DashboardView.swift:5`
  - `Views/SettingsView.swift:359`
  - `Views/OnboardingWizardView.swift:6`
  - `Views/Panels/NotificationCenterView.swift:5`
  - `Views/Panels/ExecAssistantView.swift:5`

### UpdateViewModel
- [ ] VM: `ViewModels/UpdateViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `ContentView.swift:6` → `@Environment(UpdateViewModel.self) var updateVM`
  - `Views/Shared/SharedComponents.swift:83` → `@ObservedObject var vm` → `var vm` or `@Bindable var vm`
  - `Views/Settings/AboutSettingsContent.swift:4` → `@Environment(UpdateViewModel.self) var updateVM`

### BitbucketBrowserViewModel (+ AIAnalyzable)
- [ ] VM: `ViewModels/BitbucketBrowserViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `Views/Panels/BitbucketBrowserView.swift:5` → `@Environment(BitbucketBrowserViewModel.self) var vm`

### GitHubBrowserViewModel (+ AIAnalyzable)
- [ ] VM: `ViewModels/GitHubBrowserViewModel.swift` — apply VM Pattern
- [ ] Consuming views: find all `@EnvironmentObject var githubVM` or `@EnvironmentObject var vm: GitHubBrowserViewModel`

### ChatViewModel
- [ ] VM: `ViewModels/ChatViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `Views/Panels/CopilotChatView.swift:5` → `@Environment(ChatViewModel.self) var viewModel`
  - `Views/Shared/AIBar.swift:5` → `@Environment(ChatViewModel.self) var chatVM`
  - `Views/Panels/SkillsManagerView.swift:8` → `@Environment(ChatViewModel.self) var chatVM`
  - `Views/Panels/SkillRunnerSheet.swift:7` → `@ObservedObject var chatVM` → `@Bindable var chatVM`
- [ ] Note: CopilotChatView has `$viewModel.inputText` binding (line 361) — `@Environment` doesn't provide `$`. Use `@Bindable var viewModel` wrapper:

```swift
@Environment(ChatViewModel.self) var viewModel
// In body:
@Bindable var viewModel = viewModel  // Local binding wrapper
```

### OnCallViewModel
- [ ] VM: `ViewModels/OnCallViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `Views/Panels/OnCallView.swift:5` → `@Environment(OnCallViewModel.self) var vm`
  - `Views/Panels/AlertsOnCallPanel.swift:7` → `@Environment(OnCallViewModel.self) var onCallVM`

### SkillsViewModel
- [ ] VM: `ViewModels/SkillsViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `Views/SettingsView.swift:553` → `@Environment(SkillsViewModel.self) var skillsVM`
  - `Views/Panels/SkillsManagerView.swift:7` → `@Environment(SkillsViewModel.self) var skillsVM`
  - `Views/Panels/CopilotChatView.swift:6` → `@Environment(SkillsViewModel.self) var skillsVM`
  - `Views/Panels/SkillEditorSheet.swift:5` → `@ObservedObject var skillsVM` → `@Bindable var skillsVM`
  - `Views/Panels/SkillRunnerSheet.swift:6` → `@ObservedObject var skillsVM` → `@Bindable var skillsVM`

### TeamPresenceViewModel
- [ ] VM: `ViewModels/TeamPresenceViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `ContentView.swift:7` → `@Environment(TeamPresenceViewModel.self) var presenceVM`
  - `Views/SidebarView.swift:6` → `@Environment(TeamPresenceViewModel.self) var presenceVM`
  - `Views/Shared/TeamPresencePopover.swift:5` → `@Environment(TeamPresenceViewModel.self) var presenceVM`
  - `Views/Settings/TeamPresenceSettingsContent.swift:5` → `@Environment(TeamPresenceViewModel.self) var presenceVM`

### DashboardViewModel
- [ ] VM: `ViewModels/DashboardViewModel.swift` — apply VM Pattern
- [ ] Consuming views:
  - `Views/DashboardView.swift:6` → `@Environment(DashboardViewModel.self) var vm`

- [ ] **Build checkpoint 5:** `swift build -c release` — must pass
- [ ] **Commit batch 2:**

```bash
git add BoomiSRE/Sources/
git commit -m "refactor: migrate 10 app-level VMs to @Observable

Batch 2: NotificationVM, UpdateVM, BitbucketBrowserVM, GitHubBrowserVM,
ChatVM, OnCallVM, SkillsVM, TeamPresenceVM, DashboardVM + BoomiSREApp.swift
injection changed from .environmentObject() to .environment()"
```

---

## Task 3: Cleanup

- [ ] **Remove `.id()` modifiers** on containers with VMs:
  - `Views/Panels/BPOPDashboardView.swift` — find and remove `.id()` on VM containers
  - `Views/Panels/ConfluenceBrowserView.swift` — same
  - `Views/SettingsView.swift` — same
  - `Views/Panels/CopilotChatView.swift` — same
  - `Views/Shared/AIBar.swift` — same

- [ ] **Fix MarkdownView scrollbar** in remaining views — replace non-self-sizing `MarkdownView(markdown:appTheme:)` with native `Text(LocalizedStringKey(desc))` where appropriate, or use self-sizing init with `contentHeight` binding.

- [ ] **Build and install:**

```bash
swift build -c release && bash build_app.sh
```

- [ ] **Commit cleanup:**

```bash
git add BoomiSRE/Sources/
git commit -m "fix: remove .id() on VM containers, fix MarkdownView scrollbars"
```

---

## Task 4: Final Verification

- [ ] **Full build:** `swift build -c release`
- [ ] **Install:** `bash build_app.sh`
- [ ] **Smoke test each HSplitView panel:**
  - Notifications: click Jira, Jenkins, GitHub notifications → detail loads without clicking away
  - Incidents: click incident → detail loads
  - My Work / Tickets: click ticket → detail loads
  - Infrastructure / Jenkins: click job → detail loads
  - Infrastructure / GitHub: click repo → detail loads
  - Infrastructure / Bitbucket: click repo → detail loads
  - Knowledge / Confluence: click page → detail loads
  - Communicate / Chat: send message → response renders
- [ ] **Grep for remaining legacy patterns:**

```bash
grep -r "ObservableObject\|@Published\|@StateObject\|@ObservedObject" BoomiSRE/Sources/ --include="*.swift" | grep -v "AppState\|// " | head -20
```

Expected: Only `AppState` references remain.

- [ ] **Push and release:**

```bash
git push && bash release.sh
```

---

## Execution Notes

- **Parallelization:** Task 1 VMs are independent — subagents can migrate 3-4 VMs in parallel.
- **Task 2 is sequential** — BoomiSREApp.swift changes affect all consuming views.
- **Build after every 3-4 VMs** — catch errors early, don't batch too many.
- **If a VM has complex binding patterns** (many `$vm.property`), use `@Bindable` wrapper in the view body.
- **AppState migration is explicitly deferred** — it's used in 100+ views and needs its own plan.

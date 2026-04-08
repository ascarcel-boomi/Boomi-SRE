# @Observable Migration — Design Spec

**Date:** 2026-04-08
**Status:** Ready for implementation
**Scope:** Migrate 24 ViewModels + AIAnalyzable protocol from ObservableObject to @Observable

## Problem

Every ViewModel in the Boomi SRE app (except `NotificationDetailViewModel`, migrated 2026-04-08) uses the legacy `ObservableObject`/`@Published`/`@StateObject` pattern. This causes a confirmed SwiftUI rendering bug where `NSHostingView` inside `NSSplitView` (HSplitView) fails to flush its CALayer after async property changes. Data loads but the view doesn't visually update until an external event (like clicking another window) forces a redraw.

15 of the app's HSplitView detail panes use the broken pattern. All are at risk.

The `AIAnalyzable` protocol inherits from `ObservableObject` — it must be refactored to a plain protocol so `@Observable` classes can conform.

## Goals

1. Eliminate the HSplitView rendering bug across the entire app
2. Improve performance via property-level observation granularity
3. Refactor `AIAnalyzable` protocol to remove `ObservableObject` dependency
4. Remove `.id()` modifiers on views containing @StateObject (5 views)
5. Fix MarkdownView scrollbar issues in remaining views

## Non-Goals

- Refactoring view layout or adding features
- Changing service actor patterns
- Migrating `AppState` (too large, shared everywhere — separate effort)
- Migrating `NotificationViewModel` (injected as `@EnvironmentObject` app-wide — separate effort with AppState)

## Migration Pattern

### ViewModel changes (per VM):

**Before:**
```swift
@MainActor
final class FooViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    private let service = FooService()

    func load() async {
        isLoading = true
        items = try? await service.fetch() ?? []
        isLoading = false
    }
}
```

**After:**
```swift
@Observable
@MainActor
final class FooViewModel {
    var items: [Item] = []
    var isLoading = false
    @ObservationIgnored private let service = FooService()

    func load() async {
        withAnimation(.none) { isLoading = true }
        let result = try? await service.fetch() ?? []
        withAnimation(.none) { items = result; isLoading = false }
    }
}
```

### AIAnalyzable protocol:

**Before:**
```swift
protocol AIAnalyzable: ObservableObject {
    var aiAnalysis: String? { get set }
    var isAnalyzing: Bool { get set }
    var aiError: String? { get set }
}
```

**After:**
```swift
protocol AIAnalyzable: AnyObject {
    var aiAnalysis: String? { get set }
    var isAnalyzing: Bool { get set }
    var aiError: String? { get set }
}
```

Conforming VMs: `BitbucketBrowserViewModel`, `ConfluenceBrowserViewModel`, `GrafanaBrowserViewModel`, `GitHubBrowserViewModel`, `JenkinsBrowserViewModel`.

### View changes (per view):

- `@StateObject` → `@State`
- `@ObservedObject` → plain property or `@Bindable` (if `$` bindings needed)
- Remove `.id()` modifiers on containers holding the VM
- Remove `.onReceive(viewModel.objectWillChange)` workarounds

## ViewModels to Migrate (24 total)

### Already done:
- [x] `NotificationDetailViewModel` — migrated 2026-04-08

### Batch 1 — HSplitView detail panes (highest risk, 15 VMs):
1. `IncidentViewModel` — IncidentCommandView
2. `ConfluenceBrowserViewModel` — ConfluenceBrowserView (+ AIAnalyzable, + .id() fix)
3. `GrafanaBrowserViewModel` — GrafanaBrowserView (+ AIAnalyzable)
4. `GitHubBrowserViewModel` — GitHubBrowserView (+ AIAnalyzable)
5. `BitbucketBrowserViewModel` — BitbucketBrowserView (+ AIAnalyzable, + .id() fix)
6. `JenkinsBrowserViewModel` — JenkinsBrowserView (+ AIAnalyzable)
7. `TodoDashboardViewModel` — TodoDashboardView
8. `ChatViewModel` — ChatView
9. `SavedFiltersViewModel` — SavedFiltersView
10. `BoardsViewModel` — BoardsView
11. `KnowledgeBaseViewModel` — KnowledgeBaseView
12. `TicketDetailViewModel` — TicketDetailView
13. `ExecAssistantViewModel` — ExecAssistantView
14. `CostExplorerViewModel` — CostExplorerView
15. `SLOViewModel` — SLODashboardView

### Batch 2 — Non-split-view VMs (lower risk, 9 VMs):
16. `DashboardViewModel` — DashboardView
17. `AWSHealthViewModel` — AWSResourceDetailView
18. `VelocityViewModel` — VelocityView
19. `UpdateViewModel` — AboutView
20. `OnCallViewModel` — OnCallView
21. `SkillsViewModel` — SkillsView
22. `TeamPresenceViewModel` — TeamPresencePopover
23. `ProductMappingViewModel` — ProductMappingView
24. `NotificationViewModel` — app-wide via @EnvironmentObject (needs special handling)

### Protocol fix:
- `AIAnalyzable` — change from `: ObservableObject` to `: AnyObject`

### View-only fixes:
- Remove `.id()` from: BPOPDashboardView, ConfluenceBrowserView, SettingsView, CopilotChatView, AIBar
- Fix MarkdownView scrollbar in remaining views (use self-sizing init or native Text)

## Migration Rules

1. **Add `@Observable` macro**, remove `: ObservableObject` (keep other conformances like `AIAnalyzable`)
2. **Remove all `@Published`** — plain `var` observed automatically
3. **Add `@ObservationIgnored`** to service instances, timers, and non-UI state
4. **Wrap async property mutations** in `withAnimation(.none) { }` — forces CATransaction commit
5. **In views**: `@StateObject` → `@State`
6. **In views**: `@ObservedObject` → plain property or `@Bindable` (if `$` bindings needed)
7. **Remove `.id()` modifiers** on containers holding the VM
8. **Remove workarounds**: `.onReceive(objectWillChange)`, renderKick, appearance bounce hacks
9. **Keep appearance bounce** in `.task(id:)` as safety net for HSplitView contexts
10. **Build after each VM** — verify no compilation errors

## Special Cases

### NotificationViewModel (#24)
Injected app-wide via `.environmentObject(notificationVM)`. Migration requires:
- Change to `@Observable`
- All views using `@EnvironmentObject var notificationVM` → `@Environment(NotificationViewModel.self) var notificationVM`
- `BoomiSREApp.swift` injection: `.environmentObject(notificationVM)` → `.environment(notificationVM)`
- High blast radius — do last, test thoroughly

### AIAnalyzable conformers (5 VMs)
Must migrate the protocol FIRST (Batch 0), then migrate the VMs. The protocol change from `: ObservableObject` to `: AnyObject` is a breaking change for any extension that uses `objectWillChange`.

### $viewModel.property bindings
VMs with two-way bindings (e.g., `$viewModel.searchText` in TextField) need `@Bindable`:
```swift
@Bindable var viewModel: FooViewModel  // for injected VMs
// or for @State-owned:
@State private var viewModel = FooViewModel()
// @State already provides $ binding syntax for @Observable
```

## Testing Strategy

After each batch:
- `swift build -c release` — must compile clean
- `bash build_app.sh` — install and smoke test
- Click through each migrated view's HSplitView: select items, verify detail loads without clicking another window
- Verify no regressions in views that weren't changed

## Execution Order

1. **Batch 0**: Migrate `AIAnalyzable` protocol (prerequisite)
2. **Batch 1**: HSplitView detail pane VMs (1-15) — build + test after each
3. **Batch 2**: Non-split VMs (16-23) — build + test after batch
4. **Batch 3**: `NotificationViewModel` (#24) — build + full regression test
5. **Cleanup**: Remove `.id()`, fix MarkdownView scrollbars

## Success Criteria

- All 24 VMs use `@Observable` (+ NotificationDetailViewModel = 25 total)
- `AIAnalyzable` no longer inherits `ObservableObject`
- Zero `@Published`, `@StateObject` remaining (except `AppState` — deferred)
- All HSplitView detail panes render async data without clicking another window
- No `.id()` on containers with @State VMs
- `swift build -c release` passes

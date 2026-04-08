# @Observable Migration — Design Spec

**Date:** 2026-04-08
**Status:** Draft
**Scope:** Migrate all 19 ViewModels from ObservableObject/@StateObject to @Observable/@State

## Problem

Every ViewModel in the Boomi SRE app uses the legacy `ObservableObject`/`@Published`/`@StateObject` pattern. This causes a confirmed SwiftUI rendering bug where `NSHostingView` inside `NSSplitView` (HSplitView) fails to flush its CALayer after async property changes. The result: data loads but the view doesn't visually update until an external event (like clicking another window) forces a redraw.

This was diagnosed and fixed for `NotificationDetailViewModel` over two sessions (2026-04-07 and 2026-04-08). The fix required:
1. `@Observable` macro replacing `ObservableObject`
2. `withAnimation(.none)` wrapping every async property mutation
3. Appearance bounce as safety net

15 of the app's HSplitView detail panes use the broken pattern. All are at risk of the same bug.

## Goals

1. Eliminate the HSplitView rendering bug across the entire app
2. Improve performance via property-level observation granularity
3. Fix URLSession.shared misuse (2 services)
4. Remove `.id()` modifiers on views containing @StateObject (5 views)
5. Fix MarkdownView scrollbar issues in remaining views

## Non-Goals

- Refactoring view layout or adding features
- Changing service actor patterns
- Migrating AppState (too large, shared everywhere — separate effort)

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

### View changes (per view):

**Before:**
```swift
@StateObject private var viewModel = FooViewModel()
```

**After:**
```swift
@State private var viewModel = FooViewModel()
```

Also:
- Remove `.id()` modifiers on views containing the VM
- Remove any `.onReceive(viewModel.objectWillChange)` workarounds

### Service fixes:

Replace `URLSession.shared` with `ZscalerTrustURLSession.shared` in:
- `GrafanaService.swift`
- `GoogleService.swift`

## ViewModels to Migrate (19 total)

### Batch 1 — HSplitView detail panes (highest risk, 15 VMs):
1. `IncidentViewModel` — IncidentCommandView HSplitView
2. `ConfluenceBrowserViewModel` — ConfluenceBrowserView HSplitView
3. `GrafanaBrowserViewModel` — GrafanaBrowserView HSplitView
4. `GitHubBrowserViewModel` — GitHubBrowserView HSplitView
5. `BitbucketBrowserViewModel` — BitbucketBrowserView HSplitView (+ .id() fix)
6. `JenkinsBrowserViewModel` — JenkinsBrowserView HSplitView
7. `TodoDashboardViewModel` — TodoDashboardView HSplitView
8. `ChatViewModel` — ChatView HSplitView
9. `SavedFiltersViewModel` — SavedFiltersView HSplitView
10. `BoardsViewModel` — BoardsView HSplitView
11. `KnowledgeBaseViewModel` — KnowledgeBaseView HSplitView
12. `TicketDetailViewModel` — TicketDetailView HSplitView
13. `ExecAssistantViewModel` — (check if HSplitView)
14. `CostExplorerViewModel` — CostExplorerView
15. `SLOViewModel` — SLODashboardView

### Batch 2 — Non-split-view VMs (lower risk, 4 VMs):
16. `DashboardViewModel` — DashboardView
17. `AWSHealthViewModel` — AWSResourceDetailView
18. `VelocityViewModel` — VelocityView
19. `UpdateViewModel` — AboutView

### Additional fixes:
- `OnCallViewModel` — check pattern
- `SkillsViewModel` — check pattern
- Remove `.id()` from: BPOPDashboardView, ConfluenceBrowserView, SettingsView, CopilotChatView, AIBar
- Fix MarkdownView scrollbar in remaining views

## Migration Rules

1. **Add `@Observable` macro**, remove `: ObservableObject`
2. **Remove all `@Published`** — plain `var` properties observed automatically
3. **Add `@ObservationIgnored`** to service instances and non-UI state
4. **Wrap async property mutations** in `withAnimation(.none) { }`
5. **In views**: change `@StateObject` to `@State`
6. **In views**: change `@ObservedObject` to plain property or `@Bindable` (if bindings needed)
7. **Remove `.id()` modifiers** on containers holding the VM
8. **Remove workarounds**: `.onReceive(objectWillChange)`, renderKick, appearance bounce hacks
9. **Keep appearance bounce** in `.task(id:)` as safety net for HSplitView contexts
10. **Build after each VM** — verify no compilation errors

## Testing Strategy

After each batch:
- `swift build -c release` — must compile clean
- `bash build_app.sh` — install and smoke test
- Click through each migrated view's HSplitView: select items, verify detail loads without clicking another window
- Verify no regressions in views that weren't changed

## Risk

- **Low**: The pattern is mechanical — same transformation for every VM
- **Medium**: Some VMs may have `$viewModel.property` bindings that need `@Bindable`
- **Medium**: VMs injected via `.environmentObject()` need `@Environment(Type.self)` migration
- **Mitigation**: Build after each VM, test incrementally

## Success Criteria

- All 19 VMs use `@Observable`
- Zero `ObservableObject`, `@Published`, `@StateObject` remaining in the codebase (except AppState — deferred)
- All HSplitView detail panes render async data without needing to click another window
- No URLSession.shared usage
- No `.id()` on containers with @State VMs
- `swift build -c release` passes

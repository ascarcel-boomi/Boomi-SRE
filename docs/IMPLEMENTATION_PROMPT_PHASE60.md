# Boomi SRE App — Phase 60: Fix Crash on JSM Ops Alerts Widget Click & Quality Audit

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/ContentView.swift` — main content routing (`detailContent` view builder, line ~166)
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — requires `@EnvironmentObject var vm: OnCallViewModel` (line 5)
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — `JSMOpsAlertsWidget` navigates to "oncall" via `WidgetCard(navigateTo: "oncall")`
- `BoomiSRE/Sources/BoomiSREApp.swift` — app lifecycle, check which `@StateObject` / `@EnvironmentObject` are created and passed

---

## CRASH: Missing EnvironmentObject When Navigating to On-Call

### Root Cause

The crash is `specialized EnvironmentObject.error()` — a SwiftUI view expects an `@EnvironmentObject` that was never injected.

**The specific crash path:**
1. User clicks the JSM Ops Alerts widget on the Home page
2. `WidgetCard` sets `appState.selectedReport = ReportCatalog.all.first { $0.id == "oncall" }`
3. `ContentView.detailContent` matches `case "oncall":` (line 182) and renders `OnCallView()` directly
4. `OnCallView` declares `@EnvironmentObject private var vm: OnCallViewModel` (line 5)
5. **But `OnCallViewModel` is NOT in the environment** — it's not created at the app level or passed through the view hierarchy at this point
6. SwiftUI crashes with `EXC_BREAKPOINT` / `EnvironmentObject.error()`

**Why it works from the sidebar but not from the widget:**
When the user navigates via the sidebar → "Alerts & On-Call", it goes through `AlertsOnCallPanel` which likely creates the `OnCallViewModel` as a `@StateObject`. But when navigating directly via `selectedReport` (from the widget click), `ContentView` renders `OnCallView()` raw without the ViewModel.

### Fix

**Option A (recommended): Create `OnCallViewModel` at the app level**, like we did for `BitbucketBrowserViewModel` and `GitHubBrowserViewModel`:

1. In `BoomiSREApp.swift`, add:
   ```swift
   @StateObject private var onCallVM = OnCallViewModel()
   ```

2. Pass it as an environment object:
   ```swift
   ContentView()
       .environmentObject(onCallVM)
       // ... other environment objects
   ```

3. In `OnCallView.swift`, change from `@StateObject` to `@EnvironmentObject`:
   ```swift
   // If it's currently @StateObject:
   // @StateObject private var vm = OnCallViewModel()
   // Change to:
   @EnvironmentObject private var vm: OnCallViewModel
   ```
   (It's already `@EnvironmentObject` based on what I see — but verify the VM is passed through.)

4. In `AlertsOnCallPanel` (or whatever wrapper view the sidebar uses), make sure it also uses `@EnvironmentObject` instead of creating its own `@StateObject`.

**Option B (quick fix): Wrap the direct navigation in ContentView with the environment:**

In `ContentView.detailContent`, line 182:
```swift
case "oncall":
    OnCallView()
        .environmentObject(OnCallViewModel())  // ← inject a new one
```

But this creates a new ViewModel every time, which is wasteful. Option A is better.

### Broader Audit: Check ALL Direct Navigation Cases

The same crash could happen for ANY view rendered in the `detailContent` switch (lines 177-217) that requires an `@EnvironmentObject` not in the parent chain. **Audit every view in the switch:**

| Line | Case | View | Potential Missing EnvironmentObject |
|------|------|------|-------------------------------------|
| 178 | notifications | NotificationCenterView | needs `notificationVM` — check |
| 180 | knowledge_base | KnowledgeBaseView | check |
| 182 | oncall | OnCallView | **CONFIRMED CRASH** — needs OnCallViewModel |
| 184 | incidents | IncidentCommandView | check |
| 186 | copilot_chat | CopilotChatView | needs `chatVM` — check |
| 188 | exec_assistant | ExecAssistantView | check |
| 190 | github_browser | GitHubBrowserView | needs `githubVM` — should be in environment |
| 192 | jenkins_browser | JenkinsBrowserView | check |
| 194 | grafana_browser | GrafanaBrowserView | check |
| 196 | confluence_browser | ConfluenceBrowserView | check |
| 198 | bitbucket_browser | BitbucketBrowserView | needs `bitbucketVM` — should be in environment |
| ... | ... | ... | ... |

**For each view:** check what `@EnvironmentObject` properties it declares. Verify that ALL of them are available in the view hierarchy when rendered from `detailContent`. If any are missing, either:
- Add them to the app-level environment (Option A)
- Or inject them inline (Option B)

### Also Check the Sidebar Panel Views

The sidebar uses combined panel views like `AlertsOnCallPanel`, `MyWorkPanel`, `InfrastructurePanel`, etc. (lines 223-233). These may create their own child ViewModels. Verify that when these panels render `OnCallView`, `GitHubBrowserView`, etc. as sub-tabs, the environment objects are properly passed through.

---

## Settings Navigation Issue

The user also reported: "I don't know where to find the settings to control the different Team mappings any longer."

The Products settings (where team mappings are configured) is under Settings → Products. Verify:
1. The Products tab is visible in the Settings left sidebar
2. Clicking it shows the product configuration with per-product team/project/repo pickers
3. The JSM Team Discovery within Products actually calls the API (fixed in Phase 53)

If the Products tab exists but is hard to find, consider adding a "Configure Teams" shortcut from the On-Call view and the Alerts view that navigates directly to Settings → Products.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Run `swift test` to verify tests pass.
4. **Test the crash manually:** build the app, click the JSM Ops Alerts widget on the Home page, verify it navigates to the On-Call view without crashing.
5. Commit with message: "Fix crash on JSM Ops Alerts widget click — missing OnCallViewModel EnvironmentObject"
6. `git push origin main`
7. `bash build_app.sh`
8. `bash release.sh`
9. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

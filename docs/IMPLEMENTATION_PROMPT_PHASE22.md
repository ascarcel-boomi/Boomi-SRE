# Boomi SRE App — Phase 22: Persist Browser View Models Across Navigation

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Panels/BitbucketBrowserView.swift` — has `@StateObject private var vm = BitbucketBrowserViewModel()`
- `BoomiSRE/Sources/ViewModels/BitbucketBrowserViewModel.swift` — has repo cache and `lastFetched`
- `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift` — has `@StateObject private var vm = GitHubBrowserViewModel()`
- `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` — has repo cache
- `BoomiSRE/Sources/Views/ContentView.swift` — detail pane routing that recreates views on navigation
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app lifecycle, existing `@StateObject` instances

---

## Problem

The Bitbucket repo list (2,121 repos in the `boomii` workspace) reloads from the API every time the user clicks on Bitbucket in the sidebar, taking ~30 seconds. The caching logic in `.onAppear` is correct (checks `lastFetched` staleness) but doesn't help because the view model is destroyed and recreated every time.

**Root cause:** `BitbucketBrowserView` declares `@StateObject private var vm = BitbucketBrowserViewModel()`. SwiftUI's `NavigationSplitView` detail pane destroys and recreates the detail view every time the user navigates to a different section and back. When the view is destroyed, its `@StateObject` is destroyed too — along with all 2,121 cached repos. When the user navigates back to Bitbucket, a brand new empty view model is created and the 30-second fetch starts over.

The same problem affects `GitHubBrowserView` with Mashery-Boomi org repos.

---

## Implementation

### Phase 22A: Move BitbucketBrowserViewModel to App Lifecycle

1. In `BoomiSREApp.swift`, create the view model at the app level alongside existing `@StateObject` instances:
   ```swift
   @StateObject private var bitbucketVM = BitbucketBrowserViewModel()
   ```

2. Pass it down as an `@EnvironmentObject`:
   ```swift
   ContentView()
       .environmentObject(appState)
       .environmentObject(notificationVM)
       .environmentObject(updateVM)
       .environmentObject(bitbucketVM)    // ← add this
   ```

3. In `BitbucketBrowserView.swift`, replace:
   ```swift
   @StateObject private var vm = BitbucketBrowserViewModel()
   ```
   with:
   ```swift
   @EnvironmentObject var vm: BitbucketBrowserViewModel
   ```

4. The `.onAppear` staleness check and refresh button continue to work as before — the only difference is the view model now survives navigation.

### Phase 22B: Move GitHubBrowserViewModel to App Lifecycle

Apply the same fix:

1. In `BoomiSREApp.swift`:
   ```swift
   @StateObject private var githubVM = GitHubBrowserViewModel()
   ```

2. Pass as `@EnvironmentObject` through `ContentView`.

3. In `GitHubBrowserView.swift`, replace `@StateObject` with `@EnvironmentObject`.

### Phase 22C: Verify and Build

- Run `swift build` to verify both changes compile.
- Verify no other files reference these view models as `@StateObject` that would need updating.
- Commit with message: "Persist Bitbucket and GitHub view models across navigation to prevent repo reloading".

---

## Note

All `IMPLEMENTATION_PROMPT_PHASE*.md` files belong in the `docs/` directory. Do not create them in the repo root.

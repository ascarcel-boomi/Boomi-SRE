# Round 2: Notifications + Bitbucket Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor notifications to HSplitView with richer rows, and add Bitbucket repo preloading with disk cache.

**Architecture:** Notification layout changes from inline-expansion VStack to persistent HSplitView (matching Tickets/Bitbucket pattern). Notification rows add type-specific context lines from existing metadata. Bitbucket preloads product-mapped repos at launch, caches to disk, and lazy-loads the rest on tab visit.

**Tech Stack:** SwiftUI, HSplitView, Codable (for BBRepo caching), FileManager

**Spec:** `docs/superpowers/specs/2026-04-06-round2-notifications-bitbucket-design.md`

**Key rules:**
- Read `CLAUDE.md` at repo root before any work
- DO NOT touch integration auth/configuration code
- Use `ViewStyles.swift` design tokens for any UI additions
- MarkdownView (WKWebView) handles its own scrolling — NEVER wrap in ScrollView

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Views/Panels/NotificationCenterView.swift` | Major refactor | HSplitView layout + richer rows |
| `Views/Panels/NotificationDetailPane.swift` | Modify | Remove inline styling, use .task(id:) |
| `ViewModels/BitbucketBrowserViewModel.swift` | Modify | Add disk cache + preload method |
| `Models/BitbucketModels.swift` | Modify | Add Codable to BBRepo |
| `BoomiSREApp.swift` | Modify | Add Bitbucket preload to launch sequence |

All paths relative to `BoomiSRE/Sources/`.

---

### Task 1: Refactor NotificationCenterView to HSplitView

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/NotificationCenterView.swift`

This is the biggest task. The current body (line 185) is a single `VStack`. We need to wrap it in `HSplitView`.

- [ ] **Step 1: Replace expandedNotification with selectedNotification**

Change line 8 from:
```swift
    @State private var expandedNotification: UUID?
```
to:
```swift
    @State private var selectedNotification: SRENotification?
```

- [ ] **Step 2: Refactor body to HSplitView**

Replace the `body` (lines 185-216) with:

```swift
    var body: some View {
        HSplitView {
            // Left pane: notification list
            VStack(spacing: 0) {
                headerBar
                Divider()
                summaryBar
                filterChips
                Divider()

                // Poll error warnings
                if !notificationVM.pollErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Some services failed to poll", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold()).foregroundStyle(.orange)
                        ForEach(notificationVM.pollErrors.sorted(by: { $0.key < $1.key }), id: \.key) { service, error in
                            Text("\(service): \(error)")
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                }

                projectFilterHint
                if filteredNotifications.isEmpty && notificationVM.archivedNotifications.isEmpty {
                    emptyState
                } else {
                    mainList
                }
            }
            .frame(minWidth: 320, idealWidth: 400, maxWidth: 500)
            .splitGrip()

            // Right pane: detail or placeholder
            if let notification = selectedNotification {
                NotificationDetailPane(notification: notification)
                    .id(notification.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bell")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a notification to view details")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Step 3: Update notificationRow to use selection instead of expansion**

Replace the `notificationRow` function (lines 464-522). Key changes:
- Remove `isExpanded` logic and chevron
- Change button action from toggling `expandedNotification` to setting `selectedNotification`
- Highlight selected row with accent background
- Remove inline `NotificationDetailPane` injection

```swift
    private func notificationRow(_ n: SRENotification) -> some View {
        let isSelected = selectedNotification?.id == n.id
        return Button {
            notificationVM.markRead(n)
            selectedNotification = isSelected ? nil : n
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(n.isRead ? Color.clear : n.type.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                Image(systemName: n.type.icon)
                    .font(.title3)
                    .foregroundStyle(n.type.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(n.title)
                            .font(.callout.bold())
                            .foregroundStyle(n.isRead ? .secondary : .primary)
                        Spacer()
                        Text(n.relativeTime)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    // Context line from metadata
                    if let context = contextLine(for: n) {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(n.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(n.type.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(n.type.color.opacity(0.12))
                        .foregroundStyle(n.type.color)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : (n.isRead ? Color.clear : n.type.color.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 4: Add contextLine helper**

Add this function to NotificationCenterView (after the notification row):

```swift
    private func contextLine(for n: SRENotification) -> String? {
        let m = n.metadata
        switch n.type {
        case .jiraAssigned:
            let status = m["status"] ?? ""
            return status.isEmpty ? nil : "Status: \(status)"
        case .jiraStatusChange:
            guard let old = m["oldStatus"], let new = m["newStatus"] else { return nil }
            return "\(old) → \(new)"
        case .jiraNewComment:
            return m["commenter"].map { "Comment by \($0)" }
        case .jiraMentioned:
            return m["commenter"].map { "by \($0)" }
        case .jenkinsBuildFailed:
            guard let job = m["jobName"], let build = m["buildNumber"] else { return nil }
            return "\(job) #\(build)"
        case .jenkinsBuildRecovered:
            guard let job = m["jobName"], let build = m["buildNumber"] else { return nil }
            return "\(job) #\(build) ✓"
        case .grafanaAlertFiring:
            return m["alertTitle"]
        case .grafanaAlertResolved:
            return m["alertTitle"].map { "\($0) ✓" }
        case .githubPRReview:
            let author = m["authorLogin"] ?? ""
            let repo = m["repo"] ?? ""
            if author.isEmpty && repo.isEmpty { return nil }
            return "by \(author) in \(repo)"
        case .githubPRMerged:
            return nil // title already has branch info
        case .githubWorkflowFailed:
            return m["repo"]
        case .confluencePageUpdated:
            let author = m["authorName"] ?? ""
            let space = m["spaceKey"] ?? ""
            if author.isEmpty { return nil }
            return "by \(author) in \(space)"
        case .briefingGenerated:
            return nil // body is already descriptive
        case .awsCostAnomaly:
            return m["accountName"]
        case .appUpdate:
            return m["version"]
        }
    }
```

- [ ] **Step 5: Update any remaining references to expandedNotification**

Search the file for `expandedNotification` and update any remaining references. The archived row section and any other code that references it should be updated or removed.

- [ ] **Step 6: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Views/Panels/NotificationCenterView.swift
git commit -m "feat: refactor notifications to HSplitView with contextual rows

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Update NotificationDetailPane for Persistent Pane

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/NotificationDetailPane.swift`

- [ ] **Step 1: Remove inline-expansion styling**

The current view has inline-expansion-specific styling (lines 21-31):
- Rounded rectangle background with accent border
- Horizontal padding of 16
- `.transition(.move(edge: .top).combined(with: .opacity))`

Replace the body wrapper to be a simple full-pane layout:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isLoading {
                    loadingView
                } else if let err = viewModel.loadError {
                    errorView(err)
                } else {
                    detailContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .task(id: notification.id) {
            await viewModel.loadDetail(for: notification, appState: appState)
        }
    }
```

Key changes:
- Remove `RoundedRectangle` border overlay (not needed in a persistent pane)
- Remove `.transition(.move(edge: .top))` (no expansion animation)
- Change `.task { ... }` to `.task(id: notification.id) { ... }` so it re-fires on selection change
- Wrap in `ScrollView` for long content
- Fill the pane with `maxWidth/maxHeight: .infinity`

- [ ] **Step 2: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Views/Panels/NotificationDetailPane.swift
git commit -m "feat: update NotificationDetailPane for persistent HSplitView pane

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Add Codable Conformance to BBRepo

**Files:**
- Modify: `BoomiSRE/Sources/Models/BitbucketModels.swift`

- [ ] **Step 1: Add Codable to BBRepo**

Change line 3 from:
```swift
struct BBRepo: Identifiable, Hashable, Sendable {
```
to:
```swift
struct BBRepo: Identifiable, Hashable, Sendable, Codable {
```

Since all properties are `String` and `Bool`, auto-synthesis should work. If there are computed properties or properties without Codable types, add explicit `CodingKeys`.

- [ ] **Step 2: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

If Codable auto-synthesis fails (due to a property type), add explicit `CodingKeys` enum and `init(from:)`/`encode(to:)`.

- [ ] **Step 3: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Models/BitbucketModels.swift
git commit -m "feat: add Codable conformance to BBRepo for disk caching

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Add Bitbucket Disk Cache and Preloading

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/BitbucketBrowserViewModel.swift`

- [ ] **Step 1: Add cache structures and properties**

Add after the existing `lastFetched` property (line 27):

```swift
    /// Disk cache for Bitbucket repos.
    private struct RepoCache: Codable {
        let repos: [BBRepo]
        let timestamp: Date
        let isMappedOnly: Bool
    }

    private static let cacheFile = NSHomeDirectory() + "/.boomi_sre_bitbucket_cache.json"
    private static let cacheTTL: TimeInterval = 3600 // 1 hour
```

- [ ] **Step 2: Add loadFromCache method**

Add after the cache properties:

```swift
    /// Load repos from disk cache if valid. Returns true if cache was loaded.
    func loadFromCache() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.cacheFile)),
              let cache = try? JSONDecoder().decode(RepoCache.self, from: data),
              Date().timeIntervalSince(cache.timestamp) < Self.cacheTTL else {
            return false
        }
        repos = cache.repos
        lastFetched = cache.timestamp
        return true
    }

    /// Save current repos to disk cache.
    private func saveCache(isMappedOnly: Bool) {
        let cache = RepoCache(repos: repos, timestamp: Date(), isMappedOnly: isMappedOnly)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: URL(fileURLWithPath: Self.cacheFile))
        }
    }

    /// Whether the current cache only contains product-mapped repos.
    var isCacheMappedOnly: Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.cacheFile)),
              let cache = try? JSONDecoder().decode(RepoCache.self, from: data) else { return true }
        return cache.isMappedOnly
    }
```

- [ ] **Step 3: Add preloadMappedRepos method**

```swift
    /// Preload only product-mapped repos at app launch. Fast (2-3 API pages).
    func preloadMappedRepos(appState: AppState) async {
        guard !appState.bitbucketAPIToken.isEmpty else { return }
        // Don't preload if we already have a full cache
        if loadFromCache() && !isCacheMappedOnly { return }
        // If cache already loaded mapped repos, skip
        if !repos.isEmpty { return }

        let email = appState.bitbucketAuthUser
        let token = appState.bitbucketAPIToken
        let workspace = appState.bitbucketWorkspace
        let activeBBRepos = appState.activeBitbucketRepos
        guard !activeBBRepos.isEmpty else { return }

        do {
            let fetched = try await service.listWorkspaceRepos(
                workspace: workspace, email: email, apiToken: token,
                filterRepos: Set(activeBBRepos)
            )
            repos = fetched
            lastFetched = Date()
            saveCache(isMappedOnly: true)
        } catch {
            // Preload failure is silent — user will see error on tab visit
        }
    }
```

- [ ] **Step 4: Modify loadRepos to save full cache**

In the existing `loadRepos` method (line 67), add `saveCache(isMappedOnly: false)` after `lastFetched = Date()` on line 86:

```swift
            repos = fetched
            lastFetched = Date()
            saveCache(isMappedOnly: false)
```

- [ ] **Step 5: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/ViewModels/BitbucketBrowserViewModel.swift
git commit -m "feat: add Bitbucket disk cache and preload for mapped repos

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Add Bitbucket Preload to App Launch

**Files:**
- Modify: `BoomiSRE/Sources/BoomiSREApp.swift`

- [ ] **Step 1: Add preload call to launch sequence**

In the `.onAppear` task block (after line 57 `notificationVM.startPolling`), add:

```swift
                        // Preload Bitbucket mapped repos in background
                        await bitbucketVM.preloadMappedRepos(appState: appState)
```

- [ ] **Step 2: Add cache load on init**

In the same `.onAppear` block (before the Task, around line 42-45), add an immediate cache load:

```swift
                    // Load Bitbucket repos from disk cache for instant display
                    _ = bitbucketVM.loadFromCache()
```

- [ ] **Step 3: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/BoomiSREApp.swift
git commit -m "feat: preload Bitbucket repos at app launch from disk cache

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Update BitbucketBrowserView Stale Check

**Files:**
- Modify: `BoomiSRE/Sources/Views/Panels/BitbucketBrowserView.swift`

- [ ] **Step 1: Update onAppear logic**

The current stale check (lines 26-28) triggers `loadRepos` if `lastFetched` is nil or >300s. Update it to:
- If repos are empty and no cache: load from API
- If cache is mapped-only and all teams selected: background-fetch full list
- If cache is stale (>1hr): background refresh

Find the `onAppear` block and update:

```swift
        .onAppear {
            if vm.repos.isEmpty {
                // Try cache first, then API
                if !vm.loadFromCache() {
                    Task { await vm.loadRepos(appState: appState) }
                }
            } else if let last = vm.lastFetched, Date().timeIntervalSince(last) > 3600 {
                // Stale cache — background refresh
                Task { await vm.loadRepos(appState: appState) }
            } else if vm.isCacheMappedOnly && appState.activeProductIds.isEmpty {
                // Have mapped repos but user wants all — background fetch full list
                Task { await vm.loadRepos(appState: appState) }
            }
        }
```

- [ ] **Step 2: Build and verify**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/github/Boomi-SRE
git add BoomiSRE/Sources/Views/Panels/BitbucketBrowserView.swift
git commit -m "feat: update Bitbucket stale check for cache-first loading

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: End-to-End Verification

- [ ] **Step 1: Full release build**

Run: `cd ~/github/Boomi-SRE && swift build -c release 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 2: Build app and launch**

Run: `cd ~/github/Boomi-SRE && bash build_app.sh 2>&1 | tail -5 && open -a 'Boomi SRE'`

- [ ] **Step 3: Verify notifications HSplitView**

- Navigate to Alerts & On-Call → Notifications
- Confirm list on left, placeholder on right
- Click a notification → detail appears on right
- Click another → detail switches
- All filter chips work in left pane

- [ ] **Step 4: Verify Bitbucket preloading**

- Quit and relaunch app
- Navigate to Infrastructure → Bitbucket
- Repos should appear instantly (from cache/preload)
- Verify mapped repos are present

# Round 2: Notification HSplitView + Richer Rows + Bitbucket Preloading

**Date:** 2026-04-06
**Status:** Approved
**Scope:** Notification layout overhaul, contextual notification rows, Bitbucket hybrid preloading

## Problem Statement

1. **Notification layout** — Notifications use cramped inline expansion. The detail pane appears below the tapped row, squeezing content. Every other browser in the app (Tickets, Bitbucket, Jenkins) uses HSplitView with list left + detail right. Notifications should follow the same pattern.

2. **Notification rows lack context** — Rows show generic info like "Assigned: SRE-29667" without saying WHO, or "Jenkins Failed" without saying which job. Users can't triage notifications without expanding each one.

3. **Bitbucket slow first load** — First visit to the Bitbucket tab fetches all ~2167 repos via paginated API calls. Product-mapped repos should appear instantly.

## Requirements

### Notifications
1. NotificationCenterView must use HSplitView (list left, detail right)
2. Detail pane must be persistent (placeholder when nothing selected)
3. Detail pane must refresh when selection changes (not recreate ViewModel)
4. Left pane must retain all existing filter chips, grouping, summary bar
5. Notification rows must show a type-specific context line from existing metadata
6. No new API calls for row enrichment — use existing `metadata` dictionary
7. Inline expansion must be removed (no chevron, no slide-down animation)

### Bitbucket
8. Product-mapped repos must be preloaded at app launch in the background
9. Preloaded repos must be cached to disk (`~/.boomi_sre_bitbucket_cache.json`)
10. Bitbucket tab must show cached repos instantly on visit
11. Full repo list must lazy-load in background when cache is mapped-only and "All Teams" is selected
12. Cache TTL: 1 hour. Stale cache triggers background refresh.

## Design

### A. Notification HSplitView Layout

**Files:** `Views/Panels/NotificationCenterView.swift`, `Views/Panels/NotificationDetailPane.swift`

Replace the single-column `VStack` layout with `HSplitView`:

- **Left pane** (minWidth: 320, idealWidth: 400, maxWidth: 500):
  - Header bar (title, unread badge, refresh, menu)
  - Summary bar (active/unread/priority/archived chips)
  - Filter chips (horizontal scroll)
  - Notification list with selection (`selectedNotification: SRENotification?`)
  - All existing filter/grouping logic unchanged

- **Right pane** (fills remaining space):
  - `NotificationDetailPane` when a notification is selected
  - Placeholder ("Select a notification to view details") when nothing selected

**Selection model:**
- Replace `@State var expandedNotification: UUID?` with `@State var selectedNotification: SRENotification?`
- Rows highlight on selection (accent color background) instead of expanding
- Remove inline `NotificationDetailPane` injection from rows
- Remove chevron and `.transition(.move(edge: .top))` animation

**NotificationDetailPane changes:**
- Use `.task(id: notification.id)` to refresh on selection change
- Remove close/collapse button (persistent pane)
- All type-specific detail sub-views (Jira, Grafana, GitHub, Jenkins, Confluence, Briefing, AWS, App) move as-is

### B. Richer Notification Rows

**Files:** `Views/Panels/NotificationCenterView.swift`

Add a **context line** between title and body in each notification row. Content pulled from existing `notification.metadata` keys:

| Type | Context line | Metadata keys used |
|---|---|---|
| jiraAssigned | "→ {assignee} · {status}" | `assignee`, `status` |
| jiraStatusChange | "{oldStatus} → {newStatus}" | `oldStatus`, `newStatus` |
| jiraNewComment | "Comment by {author}" | `commentAuthor` |
| jiraMentioned | "by {author} on {key}" | `mentionedBy`, `issueKey` |
| jenkinsBuildFailed | "{jobName} #{buildNumber}" | `jobName`, `buildNumber` |
| jenkinsBuildRecovered | "{jobName} #{buildNumber} ✓" | `jobName`, `buildNumber` |
| grafanaAlertFiring | "{alertName}" | `alertName` |
| grafanaAlertResolved | "{alertName} ✓" | `alertName` |
| githubPRReview | "by {author} in {repo}" | `author`, `repo` |
| githubPRMerged | "{targetBranch} ← {sourceBranch}" | `targetBranch`, `sourceBranch` |
| githubWorkflowFailed | "{repo} · {workflow}" | `repo`, `workflowName` |
| confluencePageUpdated | "by {author} in {space}" | `author`, `spaceKey` |
| briefingGenerated | Body text (already shown) | — |
| awsCostAnomaly | "{account} · +{increase}%" | `accountName`, `increasePercent` |
| appUpdate | "{version}" | `version` |

If metadata keys are missing, context line is omitted (graceful degradation). No new API calls.

Row layout becomes:
```
[dot] [icon]  Title                          [type badge] [timestamp]
              Context line (secondary color)
              Body (up to 2 lines, tertiary)
```

### C. Bitbucket Hybrid Preloading

**Files:** `ViewModels/BitbucketBrowserViewModel.swift`, `BoomiSREApp.swift`

**Disk cache:** `~/.boomi_sre_bitbucket_cache.json`
```json
{
  "repos": [...],
  "timestamp": "2026-04-06T12:00:00Z",
  "isMappedOnly": true
}
```

**BitbucketBrowserViewModel changes:**
- `loadFromCache()` — on init, read cache file. If exists and not expired (1hr TTL), set `repos` immediately.
- `preloadMappedRepos(appState:)` — fetch only product-mapped repos (uses `filterRepos` for early-exit), save to cache with `isMappedOnly: true`. Called at app launch.
- `loadRepos()` — existing method. After fetch, save to cache with `isMappedOnly: false`.
- On tab visit: if cache exists → show instantly. If stale or `isMappedOnly` and All Teams selected → background refresh.

**BoomiSREApp launch sequence:**
- After auth checks, if Bitbucket configured: `Task { await bitbucketVM.preloadMappedRepos(appState: appState) }`
- Non-blocking, runs in background.

**User experience:**
1. App launch → mapped repos preloaded (2-3 API pages, <2s)
2. Bitbucket tab visit → cached repos appear instantly
3. "All Teams" + mapped-only cache → background fetch fills in remaining repos
4. Within 1hr → fully cached, no API calls

## Dependencies

- `NotificationDetailPane` — already exists, minimal changes
- `SRENotification.metadata` — already populated by NotificationViewModel polling
- `BitbucketService.listWorkspaceRepos` — already supports `filterRepos` for early-exit
- `DiscoveryCache` pattern — reference for disk caching approach

## Out of Scope

- Jenkins console output in notification detail (Jenkins browser shows no jobs — separate bug)
- Briefings "View Full Briefing" showing content instead of KB navigation
- Purpose-built detail views per notification type (current type-specific views are sufficient)
- Notification priority filter redesign
- IC velocity metrics

## Known Issue: Jenkins Not Loading Jobs

Jenkins settings show "Connected: OK" but the browser shows "No jobs found". This needs separate investigation — likely an API endpoint or auth scope issue. Filed as a deferred item.

## Test Plan

1. **HSplitView:** Notification list on left, detail on right. Clicking a notification shows its detail. Clicking another switches detail. Placeholder shows when nothing selected.
2. **Filter persistence:** All filter chips, grouping, summary bar work as before in the left pane.
3. **Context lines:** Each notification type shows appropriate context from metadata. Missing metadata gracefully omits the line.
4. **Deep links:** Detail pane links ("Open in Jira", "Open in Jenkins", etc.) navigate to the exact item.
5. **Bitbucket preload:** Launch app, wait 5s, visit Bitbucket tab — repos appear instantly without loading spinner.
6. **Bitbucket cache:** Quit and relaunch — Bitbucket tab loads from cache within 1hr.
7. **Bitbucket background fetch:** Select "All Teams" with mapped-only cache — remaining repos load in background.
8. **Build:** `swift build -c release` succeeds.

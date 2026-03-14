# Boomi SRE App — Phase 23: GitHub Browser — Full Org Support, Metrics & Actions

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2).

**Read these files first:**
- `BoomiSRE/Sources/Services/GitHubService.swift` — current API client (has `listOrgRepos`, `listUserRepos`, `listUserOrgs`, `listPRs`, `getPRFiles`, `getWorkflowRuns`, `listBranches`, `listCommits`, `createIssue` — but NO action methods like merge/approve/close)
- `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` — has `loadRepos(token:org:)` with org error surfacing, `loadPRs`, `loadBranches`, `loadCommits`, AI analysis
- `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift` — 3-pane browser with org error banner, repo list, PR/Branch/Commit tabs
- `BoomiSRE/Sources/Models/AppState.swift` — `githubToken`, `githubOrg` (single string, defaults to "Mashery-Boomi"), `favoriteGitHubRepos`
- `BoomiSRE/Sources/Views/SettingsView.swift` — GitHub settings tab (look for how org is configured)

**Key constraints:**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

**Corporate context:**
- Primary GitHub org: `Mashery-Boomi` at `https://github.com/Mashery-Boomi`
- User's personal account: `ascarcel-boomi`
- The org likely requires SSO authorization on the GitHub token

---

## Problem

The GitHub browser only shows personal repos. The `Mashery-Boomi` org repos don't appear. Phase 21D implemented org error surfacing, but the user may not be seeing the error clearly, and the underlying issue (token SSO authorization) needs a better UX flow. Additionally, the user wants full repo metrics, intelligence, and the ability to take actions (merge, approve, comment, etc.) directly from the app.

---

## Implementation Plan

Work through these phases in order. Run `swift build` after each. Commit after each.

### Phase 23A: Fix Org Repo Loading — Multi-Org with Auto-Discovery

**Problems to fix:**

1. `appState.githubOrg` is a single string. Replace with `@Published var githubOrgs: [String]` (array, persisted). Default: `["Mashery-Boomi"]`. Keep backward compatibility — if the old `githubOrg` string exists in config, migrate it to the array on load.

2. `loadRepos()` currently takes a single `org` string. Change it to iterate over ALL orgs in `appState.githubOrgs`:
   ```swift
   func loadRepos(token: String, orgs: [String]) async {
       // For each org, fetch repos. Collect all errors per org.
       for org in orgs {
           do {
               let orgResult = try await githubService.listOrgRepos(org: org, token: token)
               // append to allOrgRepos with org name tag
           } catch {
               orgErrors[org] = error.localizedDescription
           }
       }
       // Also fetch personal repos
       // Merge and deduplicate
   }
   ```

3. **Auto-discover orgs on first load:** If `githubOrgs` is empty or on user request, call `GitHubService.listUserOrgs(token:)` (already exists) and populate the list. Add a "Discover My Orgs" button in the GitHub settings tab.

4. **SSO authorization detection:** When an org fetch returns 403, show a specific actionable message:
   ```
   ⚠️ Cannot access Mashery-Boomi: Your token needs SSO authorization.

   1. Go to github.com/settings/tokens
   2. Find your token ("Boomi SRE App")
   3. Click "Configure SSO" → Authorize "Mashery-Boomi"
   4. Come back and click Refresh

   [Open GitHub Token Settings]  [Refresh]
   ```
   Make this a prominent card, not a tiny banner. This is the #1 reason org repos don't show.

5. **In Settings → GitHub tab:**
   - Show the list of configured orgs with add/remove
   - "Discover Orgs" button that calls `listUserOrgs()` and shows checkboxes for each
   - Show which orgs have SSO authorized vs. not (attempt a test fetch of 1 repo per org)

6. **Separate org and personal repos in the sidebar list:**
   - Section headers: "Mashery-Boomi (142 repos)" / "Personal (12 repos)"
   - Each section collapsible
   - Org sections show a status indicator (green checkmark if loaded, orange warning if failed)

### Phase 23B: Repo Overview & Health Metrics

**Goal:** When a repo is selected, show an overview tab with metrics before drilling into PRs.

1. **Add a "Repo Overview" as the default tab** (tab 0), shifting PRs to tab 1, Branches to 2, Commits to 3.

2. **Repo Overview tab shows:**
   - **Header card:** Repo name, description, visibility (public/private badge), language badge, default branch, star/fork/open issue counts
   - **Last activity:** Last commit date + author + message (from first item in commits)
   - **Health indicators** (color-coded cards in a row):
     - CI Status: last workflow run result (green/red/yellow)
     - Open PRs: count (green if <5, yellow 5-15, red >15)
     - Open Issues: count
     - Last Commit: relative time (green if <7d, yellow 7-30d, red >30d)
   - **README preview:** Fetch first 3000 chars of README.md via `GET /repos/{owner}/{repo}/readme` (returns base64 content, decode it). Render as markdown using `Text(AttributedString(markdown:))`.
   - **Topics/tags** as pill badges
   - **License** name
   - **"Open on GitHub" button**

3. **Fetch repo detail:** Add `getRepoDetail(owner:repo:token:)` to `GitHubService`:
   ```swift
   // GET /repos/{owner}/{repo}
   // Returns: description, stargazers_count, forks_count, open_issues_count,
   //          language, license, topics, default_branch, pushed_at, size
   ```

4. **Fetch README:** Add `getReadme(owner:repo:token:)` to `GitHubService`:
   ```swift
   // GET /repos/{owner}/{repo}/readme
   // Returns base64-encoded content, decode to String
   ```

### Phase 23C: PR Actions — Merge, Approve, Comment, Close

**Goal:** Let users take actions on PRs directly from the app.

1. **Add these methods to `GitHubService`:**

   ```swift
   /// Merge a pull request
   func mergePR(owner: String, repo: String, number: Int, method: String, token: String) async throws -> String
   // PUT /repos/{owner}/{repo}/pulls/{number}/merge
   // Body: {"merge_method": "merge"|"squash"|"rebase"}
   // Returns merge commit SHA

   /// Approve a pull request
   func approvePR(owner: String, repo: String, number: Int, token: String) async throws
   // POST /repos/{owner}/{repo}/pulls/{number}/reviews
   // Body: {"event": "APPROVE"}

   /// Request changes on a pull request
   func requestChanges(owner: String, repo: String, number: Int, body: String, token: String) async throws
   // POST /repos/{owner}/{repo}/pulls/{number}/reviews
   // Body: {"event": "REQUEST_CHANGES", "body": "..."}

   /// Close a pull request
   func closePR(owner: String, repo: String, number: Int, token: String) async throws
   // PATCH /repos/{owner}/{repo}/pulls/{number}
   // Body: {"state": "closed"}

   /// Post a comment on a PR (or issue)
   func postComment(owner: String, repo: String, number: Int, body: String, token: String) async throws
   // POST /repos/{owner}/{repo}/issues/{number}/comments
   // Body: {"body": "..."}

   /// Trigger a workflow dispatch
   func triggerWorkflow(owner: String, repo: String, workflowId: Int, ref: String, token: String) async throws
   // POST /repos/{owner}/{repo}/actions/workflows/{workflowId}/dispatches
   // Body: {"ref": "main"}
   ```

2. **Add action buttons to the PR detail pane in `GitHubBrowserView`:**
   - **"Approve" button** (green, `.borderedProminent`) — shows confirmation dialog, then calls `approvePR()`
   - **"Request Changes" button** (orange) — shows a sheet with a text field for the review comment, then calls `requestChanges()`
   - **"Merge" button** (blue, `.borderedProminent`) — shows confirmation dialog with merge method picker:
     - "Create a merge commit" / "Squash and merge" / "Rebase and merge"
     - Only enabled if the PR `mergeable` field is true (add `mergeable` to GitHubPR model — fetch from PR detail endpoint)
   - **"Close" button** (red, destructive) — shows confirmation: "Close this PR without merging?"
   - **"Comment" button** — shows a sheet with a text area, posts the comment

   All action buttons should:
   - Show a confirmation alert before executing (especially merge and close)
   - Show a success banner ("PR #123 merged successfully") or error message inline
   - Refresh the PR list after the action completes
   - Be disabled if the user doesn't have write access (detect from 403 response)

3. **Add a "Post Comment" text field** at the bottom of the PR detail pane (always visible when a PR is selected):
   ```
   [Comment text field                          ] [Post Comment]
   ```

4. **Workflow actions:**
   - In the workflow runs section, add a "Re-run" or "Trigger" button next to each workflow
   - Shows the workflow name and lets the user pick a branch (default: repo's default branch)
   - Confirmation: "Trigger workflow '{name}' on branch '{ref}'?"

### Phase 23D: PR State Filter & Richer PR Display

1. **PR state filter** is already implemented (`prStateFilter`). Verify it works and shows correctly:
   - Segmented control: "Open" | "Closed" | "Merged" | "All"
   - Counts next to each: "Open (3)" / "Merged (47)"
   - Note: GitHub API uses `state=open`, `state=closed` (merged PRs are a subset of closed). To show "Merged" separately, filter closed PRs by `merged_at != null`.

2. **Richer PR rows:**
   - Review status badge: "Approved" (green), "Changes Requested" (red), "Review Required" (yellow)
   - To get review status: add `reviewDecision` to the PR model. This requires the GraphQL API or fetching reviews via `GET /repos/{owner}/{repo}/pulls/{number}/reviews`. For the list view, fetch reviews for the first 10 PRs lazily.
   - CI status badge: show the latest check run status (success/failure/pending) from `GET /repos/{owner}/{repo}/commits/{sha}/check-runs` where sha = PR head SHA. Cache this.
   - Labels as colored pills
   - Assignees as avatar initials

3. **PR detail enhancements:**
   - Show full description (rendered markdown)
   - Show all reviewers and their review status
   - Show all labels
   - Show linked issues (if referenced in PR body like "Fixes #123")
   - Show merge status: "This PR can be merged" (green) or "Merge conflicts" (red) — from `mergeable` field

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.**
- **Rate limits:** GitHub API has rate limits (5,000/hour for authenticated). Don't fetch everything eagerly — load tabs on demand. The overview + README can be fetched when a repo is first selected (cache it).
- **Error handling:** Surface specific errors. If a 403 occurs on an action, show: "You don't have write access to this repo."
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Commit after each phase** (23A, 23B, 23C, 23D) with a descriptive commit message.

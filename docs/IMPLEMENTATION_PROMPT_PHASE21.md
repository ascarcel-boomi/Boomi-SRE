# Boomi SRE App — Phase 21: Bitbucket & GitHub Bug Fixes + Full Browser Parity

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Services/BitbucketService.swift` — ONLY has `checkAuth()`, no repo/PR methods
- `BoomiSRE/Sources/Services/GitHubService.swift` — full API client (repos, PRs, files, workflow runs, issues)
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — file-based secrets store (`~/.boomi_sre_secrets.json`)
- `BoomiSRE/Sources/Services/CredentialDiscovery.swift` — auto-discovery for `BITBUCKET_API_TOKEN`, `GITHUB_TOKEN`
- `BoomiSRE/Sources/Models/AppState.swift` — `bitbucketAPIToken` (KeychainHelper-backed), `githubToken`, `githubOrg` (defaults to "Mashery-Boomi"), `favoriteGitHubRepos`
- `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` — `orgName = "Mashery-Boomi"` (local, not from AppState), `loadRepos()`, `loadPRs()`, AI analysis
- `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift` — 3-pane browser (repos → PRs → detail)
- `BoomiSRE/Sources/Views/SidebarView.swift` — Bitbucket is a status-only `authButton`, not a browser
- `BoomiSRE/Sources/Models/ReportItem.swift` — ReportCatalog has no Bitbucket entry
- `BoomiSRE/Sources/Views/ContentView.swift` — routing (no Bitbucket case)
- `BoomiSRE/Sources/Views/SettingsView.swift` — BitbucketSettingsContent (workspace hardcoded to "boomii")

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

**External context:**
- Corporate Bitbucket workspace: `boomii` at `bitbucket.org/boomii/`
- Corporate GitHub org: `Mashery-Boomi` at `github.com/Mashery-Boomi`
- User's personal GitHub: `ascarcel-boomi`

**IMPORTANT — Bitbucket auth change (September 2025):**
Bitbucket app passwords are deprecated and can no longer be created. Bitbucket now uses **scoped API tokens** created at `id.atlassian.com/manage-profile/security/api-tokens`. All existing app passwords will be disabled June 9, 2026.
- **Bitbucket API tokens are SEPARATE from Jira/Confluence API tokens.** They are created at the same Atlassian account portal, but you select "Bitbucket" as the target application and configure Bitbucket-specific scopes (Repositories, Pull Requests, Pipelines, Workspaces, etc.).
- **You CANNOT reuse a Jira/Confluence token for Bitbucket** — they are different tokens with different scope systems.
- Auth method: Basic auth with `email:bitbucketApiToken` (same HTTP Basic method as Jira, but a different token value)
- Required scopes for read-only: `read:repository:bitbucket`, `read:pullrequest:bitbucket`, `read:pipeline:bitbucket`, `read:workspace:bitbucket`, `read:project:bitbucket`
- Required scopes for actions (merge, comment, trigger): add `write:pullrequest:bitbucket`, `write:pipeline:bitbucket`, `write:repository:bitbucket`
- The token is shown only once at creation — it cannot be retrieved later
- Docs: `https://support.atlassian.com/bitbucket-cloud/docs/api-tokens/`

This means the Bitbucket token persistence bug is NOT related to sharing a Jira token — it's a genuinely separate credential that must be stored and managed independently. Do NOT add a "Use Jira Token" button.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 21A: Fix Bitbucket Token Persistence Bug

**Problem:** The Bitbucket API token doesn't persist. The user has to re-paste it frequently. All other service tokens persist fine.

**Root cause investigation:**

The Bitbucket token IS stored via `KeychainHelper` (key: `"bitbucket-api-token"`) in `~/.boomi_sre_secrets.json`, same as every other service. So the storage mechanism itself is fine.

Potential causes to investigate and fix:

1. **The `checkAuth()` in `checkAllServices()` may be failing silently and resetting the status to `.notConfigured` or `.error` even though the token is saved.** Check the auth check flow in `AppState.checkAllServices()`:
   - If `bitbucketAPIToken.isEmpty` is checked BEFORE the token is loaded from KeychainHelper, it would fail.
   - Fix: ensure KeychainHelper is loaded before the auth check runs. Since `bitbucketAPIToken` is a computed property backed by `KeychainHelper.load()`, it should always read from disk — verify this.

2. **The Bitbucket auth check uses `email` from `appState.jiraEmail`.** If Jira email is empty at check time (e.g., Jira auth hasn't completed yet), the Bitbucket check would fail or produce a bad Basic auth header. Fix: add a guard that checks both token AND email are non-empty before attempting auth.

3. **The `checkAuth()` uses `workspace: "boomii"` hardcoded.** If the workspace name is wrong or the token doesn't have access to that workspace, auth fails. Fix: make the workspace configurable (see Phase 21C).

4. **The `addBasicAuth()` extension may not be available in `BitbucketService.swift`.** The `addBasicAuth` method was defined as a `private extension URLRequest` in `ConfluenceService.swift`. If it's not accessible from `BitbucketService`, the auth header won't be set. Fix: move `addBasicAuth` to a shared location (e.g., a `URLRequest+Auth.swift` extension file) or duplicate it in BitbucketService.

**Specific fixes:**

1. **Verify `addBasicAuth` is accessible** from `BitbucketService`. If it's defined as a `private extension` in another file, it won't be visible. Either move it to a shared extension or add it to BitbucketService.

2. **Add logging/error detail** to the Bitbucket auth check. When it fails, surface the actual HTTP status code and error body in the auth status (`.error("401: Bad credentials")` not just `.error("The operation couldn't be completed")`).

3. **In Settings → Bitbucket tab**, when the user pastes a token and clicks "Test Connection", verify the token is actually saved to KeychainHelper BEFORE calling checkAuth. Print/display the key being used.

4. **Add a Bitbucket token validation** on app startup: after `checkAllServices()`, if Bitbucket status is `.error` but the token is non-empty, log the specific error. This will help debug the persistence issue.

---

### Phase 21B: Build Full Bitbucket Service — API Parity with GitHub

**Goal:** Expand `BitbucketService` from auth-only to a full API client matching GitHub's capabilities.

**Add these methods to `BitbucketService`:**

```swift
actor BitbucketService {
    private let baseURL = "https://api.bitbucket.org/2.0"

    // Auth
    func checkAuth(email: String, apiToken: String, workspace: String) async throws -> String

    // Repositories
    func listWorkspaceRepos(workspace: String, email: String, apiToken: String) async throws -> [BBRepo]
    // GET /2.0/repositories/{workspace}?pagelen=100&sort=-updated_on
    // Paginate with ?page=N

    // Pull Requests
    func listPRs(workspace: String, repoSlug: String, state: String = "OPEN", email: String, apiToken: String) async throws -> [BBPR]
    // GET /2.0/repositories/{workspace}/{repo_slug}/pullrequests?state={state}&pagelen=50

    func getPRDiff(workspace: String, repoSlug: String, prId: Int, email: String, apiToken: String) async throws -> String
    // GET /2.0/repositories/{workspace}/{repo_slug}/pullrequests/{id}/diff

    func getPRComments(workspace: String, repoSlug: String, prId: Int, email: String, apiToken: String) async throws -> [BBComment]
    // GET /2.0/repositories/{workspace}/{repo_slug}/pullrequests/{id}/comments

    // Branches
    func listBranches(workspace: String, repoSlug: String, email: String, apiToken: String) async throws -> [BBBranch]
    // GET /2.0/repositories/{workspace}/{repo_slug}/refs/branches?pagelen=50

    // Pipelines (Bitbucket's CI/CD)
    func listPipelines(workspace: String, repoSlug: String, email: String, apiToken: String) async throws -> [BBPipeline]
    // GET /2.0/repositories/{workspace}/{repo_slug}/pipelines?pagelen=20&sort=-created_on

    // Commits
    func listCommits(workspace: String, repoSlug: String, email: String, apiToken: String, limit: Int = 20) async throws -> [BBCommit]
    // GET /2.0/repositories/{workspace}/{repo_slug}/commits?pagelen={limit}

    // Repository details
    func getRepo(workspace: String, repoSlug: String, email: String, apiToken: String) async throws -> BBRepoDetail
    // GET /2.0/repositories/{workspace}/{repo_slug}
}
```

**Models (create `BoomiSRE/Sources/Models/BitbucketModels.swift`):**

```swift
struct BBRepo: Identifiable, Hashable, Sendable {
    let id: String               // uuid
    let name: String             // repo-slug
    let fullName: String         // "workspace/repo-slug"
    let description: String
    let isPrivate: Bool
    let language: String         // "python", "swift", etc.
    let mainBranch: String       // "main", "master"
    let updatedOn: String        // ISO date
    let size: Int                // bytes
    let htmlURL: String          // link to bitbucket.org
}

struct BBPR: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let description: String
    let state: String            // "OPEN", "MERGED", "DECLINED", "SUPERSEDED"
    let authorDisplayName: String
    let authorNickname: String
    let sourceBranch: String
    let destinationBranch: String
    let createdOn: String
    let updatedOn: String
    let commentCount: Int
    let taskCount: Int
    let htmlURL: String
}

struct BBBranch: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let target: String           // latest commit hash (short)
    let behindMainBy: Int?       // commits behind main (if available)
}

struct BBPipeline: Identifiable, Sendable {
    let id: String               // uuid
    let buildNumber: Int
    let state: String            // "COMPLETED", "RUNNING", "PENDING", "FAILED"
    let result: String?          // "SUCCESSFUL", "FAILED", "STOPPED"
    let triggerName: String      // "push", "pull_request", "manual"
    let targetBranch: String
    let createdOn: String
    let completedOn: String?
    let durationSeconds: Int?
    let htmlURL: String
}

struct BBCommit: Identifiable, Sendable {
    var id: String { hash }
    let hash: String             // full sha
    let shortHash: String        // first 7 chars
    let message: String
    let authorName: String
    let date: String
}

struct BBComment: Identifiable, Sendable {
    let id: Int
    let authorDisplayName: String
    let content: String          // rendered HTML → strip to text
    let createdOn: String
    let updatedOn: String
}
```

**Bitbucket API pagination note:** Bitbucket uses `pagelen` (page size) and `page` (page number). The response has `next` URL for the next page and `size` for total count. Parse `values` array from the response.

---

### Phase 21C: Bitbucket Browser View

**Goal:** Create a full Bitbucket browser matching the GitHub browser's functionality.

**Create `BoomiSRE/Sources/ViewModels/BitbucketBrowserViewModel.swift`:**

```swift
@MainActor
final class BitbucketBrowserViewModel: ObservableObject {
    @Published var repos: [BBRepo] = []
    @Published var selectedRepo: BBRepo?
    @Published var prs: [BBPR] = []
    @Published var selectedPR: BBPR?
    @Published var prDiff: String?
    @Published var branches: [BBBranch] = []
    @Published var pipelines: [BBPipeline] = []
    @Published var commits: [BBCommit] = []
    @Published var searchText: String = ""

    @Published var isLoadingRepos = false
    @Published var isLoadingPRs = false
    @Published var isLoadingDetail = false
    @Published var error: String?

    // Filters
    @Published var prStateFilter: String = "OPEN"   // OPEN, MERGED, DECLINED

    // AI
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?

    // Workspaces
    @Published var workspaces: [String] = []        // discovered workspaces
    @Published var selectedWorkspace: String = "boomii"

    func loadRepos(appState: AppState) async { ... }
    func loadPRs(repo: BBRepo, appState: AppState) async { ... }
    func loadPRDetail(pr: BBPR, appState: AppState) async { ... }
    func loadBranches(repo: BBRepo, appState: AppState) async { ... }
    func loadPipelines(repo: BBRepo, appState: AppState) async { ... }
    func loadCommits(repo: BBRepo, appState: AppState) async { ... }

    // AI
    func summarizePR(appState: AppState) async { ... }
    func reviewPR(appState: AppState) async { ... }
}
```

**Create `BoomiSRE/Sources/Views/Panels/BitbucketBrowserView.swift`:**

3-pane layout matching GitHub:
- **Left pane:** Repo list
  - Workspace picker at top (dropdown, defaults to "boomii")
  - Search field
  - Repo rows: name, description (1 line), language badge, private/public icon, last updated
  - Sort by: updated (default), name, size
- **Middle pane:** Repo detail + PR list
  - Repo header: name, full name, description, language, size, default branch, link to Bitbucket
  - Tabs: "Pull Requests" | "Branches" | "Pipelines" | "Commits"
  - PR tab: filter by state (OPEN/MERGED/DECLINED), list with title, author, branches, date, comment count
  - Branches tab: list of branches with latest commit hash
  - Pipelines tab: recent pipeline runs with state/result badges, duration, trigger
  - Commits tab: recent commits with hash, message, author, date
- **Right pane:** PR detail (when a PR is selected)
  - Title, author, source→destination branches, description
  - Diff view (monospaced, syntax-highlighted if possible, or at least raw diff text)
  - AI buttons: "Summarize PR", "SRE Review" (same pattern as GitHub)
  - Comments list
  - "Open in Bitbucket" link

**Register in sidebar and routing:**
- Replace the status-only `authButton` in SidebarView with a proper `NavigationLink` to the browser (same as GitHub/Jenkins/etc.)
- Add to `ReportCatalog`:
  ```swift
  ReportItem(id: "bitbucket_browser", title: "Bitbucket",
             description: "Browse repos, PRs, branches, and pipelines with AI review",
             section: .services, scriptName: "", csvKeys: [], chartType: .table, icon: "arrow.triangle.branch")
  ```
- Add routing in `ContentView.swift`: `case "bitbucket_browser": BitbucketBrowserView()`

**Workspace configuration in Settings:**
- Replace hardcoded "boomii" with a configurable list:
  - Add `@Published var bitbucketWorkspaces: [String] = ["boomii"]` to AppState (persisted)
  - In Bitbucket Settings tab: list of workspaces with add/remove
  - "Discover Workspaces" button that calls `GET /2.0/workspaces` (if the token has workspace read scope) and lists all accessible workspaces
  - Default: `["boomii"]`

---

### Phase 21D: Fix GitHub Org Repos Not Loading

**Problem:** The GitHub browser only shows personal repos. The corporate `Mashery-Boomi` org repos don't appear.

**Root cause:** In `GitHubBrowserViewModel.swift`, `orgName` is a local property defaulting to `"Mashery-Boomi"`. But `loadRepos()` calls `listOrgRepos(org: orgName)` which can fail with 403/404 if:
1. The token doesn't have the `read:org` scope
2. The token hasn't been SSO-authorized for the org
3. The org name is wrong

The error is silently caught and the org repos are just empty.

**Fixes:**

1. **Surface the org error:** When `listOrgRepos()` fails, don't silently swallow the error. Store it and show it in the UI:
   ```swift
   var orgError: String?
   // In loadRepos():
   do {
       orgRepos = try await githubService.listOrgRepos(org: orgName, token: token)
   } catch {
       orgError = "Could not load \(orgName) repos: \(error.localizedDescription)"
   }
   ```
   Show a banner in the repo list: "Could not load Mashery-Boomi repos: 403 Forbidden. Your token may need SSO authorization — click here to fix." The "click here" should open `https://github.com/settings/tokens` in the browser.

2. **Use `appState.githubOrg`** instead of the local `orgName` property. Remove the local `orgName` and read from AppState. This way the user can change it in Settings.

3. **Support multiple orgs:** Replace `githubOrg: String` in AppState with `githubOrgs: [String]` (array). Default: `["Mashery-Boomi"]`. The user can add more orgs in Settings. `loadRepos()` fetches from ALL configured orgs + personal.

4. **Auto-discover orgs:** Add a method to GitHubService:
   ```swift
   func listUserOrgs(token: String) async throws -> [String]
   // GET /user/orgs → returns [{login: "Mashery-Boomi"}, ...]
   ```
   Call this in Settings and let the user toggle which orgs to show.

5. **Separate personal from org repos in the UI:** Show sections: "Personal", "Mashery-Boomi", etc. Each with a count badge. This makes it clear what's coming from where and helps the user see if an org fetch failed.

---

### Phase 21E: GitHub Repo Metrics & Intelligence

**Problem:** GitHub browser only shows open PRs and CI runs. The user wants metrics and deeper intel on repos.

**Add these features to the GitHub browser:**

1. **Repo Overview tab** (new default tab when a repo is selected, before PRs):
   - Description, language, default branch, visibility
   - Star count, fork count, open issues count, size
   - Last commit date + author
   - License
   - Topics/tags
   - "Open on GitHub" link
   - README preview (fetch first 2000 chars of README.md via Contents API)

2. **PR state filter:** Currently only shows open PRs. Add a state picker: "Open" | "Merged" | "Closed" | "All". Use the `state` parameter on `listPRs()`.

3. **Branch list tab:**
   - `GET /repos/{owner}/{repo}/branches?per_page=100`
   - Show branch name, last commit, protection status
   - Highlight the default branch

4. **Commit history tab:**
   - `GET /repos/{owner}/{repo}/commits?per_page=30`
   - Show: short hash, message (1 line), author, date
   - Click to open on GitHub

5. **Actions/Workflows tab** (enhance existing):
   - Currently shows last 15 runs. Expand to show:
     - Workflow name grouping (multiple workflows per repo)
     - Success rate (% of last 10 runs that succeeded)
     - Average duration
     - Currently running workflows with live status

6. **Repo health metrics card** at the top of the repo detail:
   - Open PRs count | Open Issues count | Last commit (relative time) | CI Status (last run)
   - Color-coded: green if CI passing + recent commits, yellow if stale (>30 days), red if CI failing

7. **Actions the user can take:**
   - **Merge a PR** (if user has permission): `PUT /repos/{owner}/{repo}/pulls/{number}/merge`
     - Show a confirmation dialog with merge method picker: "Merge commit" | "Squash and merge" | "Rebase and merge"
     - Only enabled if PR is mergeable (check `mergeable` field from PR detail)
   - **Approve a PR:** `POST /repos/{owner}/{repo}/pulls/{number}/reviews` with `event: "APPROVE"`
   - **Request changes:** Same endpoint with `event: "REQUEST_CHANGES"` + comment body
   - **Close a PR:** `PATCH /repos/{owner}/{repo}/pulls/{number}` with `state: "closed"`
   - **Create a branch:** `POST /repos/{owner}/{repo}/git/refs` with ref name + sha
   - **Trigger a workflow run:** `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`
   - **Post a PR comment:** `POST /repos/{owner}/{repo}/pulls/{number}/comments` or `POST /repos/{owner}/{repo}/issues/{number}/comments`

   All actions should:
   - Show a confirmation dialog before executing
   - Require the user to confirm destructive actions (merge, close)
   - Show success/failure feedback inline
   - Refresh the relevant data after action completes

---

### Phase 21F: Bitbucket Actions

**Goal:** Mirror the GitHub action capabilities for Bitbucket.

**Actions the user can take in Bitbucket:**
- **Approve a PR:** `POST /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/approve`
- **Unapprove:** `DELETE /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/approve`
- **Decline a PR:** `POST /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/decline`
- **Merge a PR:** `POST /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/merge` with merge strategy
- **Post a PR comment:** `POST /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/comments`
- **Trigger a pipeline:** `POST /2.0/repositories/{workspace}/{repo}/pipelines` with target branch

Same UX pattern as GitHub: confirmation dialogs, inline feedback, auto-refresh after action.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** The existing GitHub browser, AI analysis, and all other services must continue to work.
- **API rate limits:** Both GitHub and Bitbucket have rate limits. Don't fetch everything eagerly — load tabs on demand (lazy loading). Cache aggressively.
- **Error handling:** All API calls should surface specific error messages, not generic failures. Show HTTP status codes and response bodies in error states.
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Commit after each phase** (21A, 21B, 21C, 21D, 21E, 21F) with a descriptive commit message.

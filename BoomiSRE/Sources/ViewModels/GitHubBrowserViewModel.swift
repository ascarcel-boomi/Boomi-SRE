import Foundation
import SwiftUI

@MainActor
final class GitHubBrowserViewModel: ObservableObject, AIAnalyzable {
    @Published var repos: [GitHubRepo] = []
    @Published var orgRepos: [GitHubRepo] = []
    @Published var personalRepos: [GitHubRepo] = []
    @Published var repoFilter: String = ""
    @Published var selectedRepo: GitHubRepo?
    @Published var prs: [GitHubPR] = []
    @Published var selectedPR: GitHubPR?
    @Published var prFiles: [GitHubPRFile] = []
    @Published var workflowRuns: [GitHubWorkflowRun] = []
    @Published var isLoadingRepos = false
    @Published var isLoadingPRs = false
    @Published var isLoadingFiles = false
    @Published var error: String?
    @Published var orgError: String?           // legacy single-org error
    @Published var orgErrors: [String: String] = [:]   // org -> error message
    @Published var orgName: String = "Mashery-Boomi"
    @Published var includePersonal = true
    @Published var discoveredOrgs: [String] = []
    @Published var isDiscoveringOrgs = false
    @Published var repoTab: Int = 0   // 0=Overview, 1=PRs, 2=Branches, 3=Commits
    @Published var repoDetail: GitHubService.RepoDetail?
    @Published var readme: String = ""
    @Published var isLoadingOverview = false
    @Published var prStateFilter: String = "open"
    @Published var branches: [GitHubBranch] = []
    @Published var commits: [GitHubCommit] = []
    // Actions
    @Published var actionResult: String?
    @Published var showMergeDialog = false
    @Published var mergeMethod: String = "merge"
    @Published var commentText: String = ""
    @Published var requestChangesText: String = ""
    @Published var showRequestChangesSheet = false
    @Published var showCommentSheet = false
    // AI
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?

    private let githubService = GitHubService()
    private let claudeService = ClaudeService()
    var depthHint: String = ""

    var filteredRepos: [GitHubRepo] {
        if repoFilter.isEmpty { return repos }
        return repos.filter { $0.name.localizedCaseInsensitiveContains(repoFilter) || $0.fullName.localizedCaseInsensitiveContains(repoFilter) }
    }

    /// Filtered PRs for display — "merged" is a virtual filter over closed PRs
    var displayedPRs: [GitHubPR] {
        switch prStateFilter {
        case "merged":  return prs.filter { $0.mergedAt != nil }
        case "open":    return prs.filter { $0.state == "open" }
        case "closed":  return prs.filter { $0.state == "closed" && $0.mergedAt == nil }
        default:        return prs
        }
    }

    /// API state to fetch for a given filter
    var apiStateForFilter: String {
        switch prStateFilter {
        case "merged": return "closed"   // merged is subset of closed
        case "all":    return "all"
        default:       return prStateFilter
        }
    }

    func loadRepos(token: String, org: String) async {
        await loadRepos(token: token, orgs: org.isEmpty ? [] : [org])
    }

    func loadRepos(token: String, orgs: [String]) async {
        guard !token.isEmpty else { error = "GitHub token not configured."; return }
        isLoadingRepos = true; error = nil; orgError = nil; orgErrors = [:]; orgRepos = []; personalRepos = []

        // Fetch all orgs concurrently
        var allOrgRepos: [GitHubRepo] = []
        await withTaskGroup(of: (String, [GitHubRepo], String?).self) { group in
            for org in orgs where !org.isEmpty {
                group.addTask {
                    do {
                        let repos = try await self.githubService.listOrgRepos(org: org, token: token)
                        return (org, repos, nil)
                    } catch {
                        let msg = error.localizedDescription.contains("403")
                            ? "Token needs SSO authorization for \(org). Go to github.com/settings/tokens → Configure SSO → Authorize \(org)."
                            : error.localizedDescription
                        return (org, [], msg)
                    }
                }
            }
            for await (org, repos, err) in group {
                if let err { orgErrors[org] = err; orgError = err }
                allOrgRepos.append(contentsOf: repos)
            }
        }

        async let personalTask: [GitHubRepo] = {
            do { return try await githubService.listUserRepos(token: token) }
            catch { return [] }
        }()
        let personal = await personalTask

        orgRepos = allOrgRepos.sorted { $0.name < $1.name }
        let orgFullNames = Set(allOrgRepos.map(\.fullName))
        personalRepos = personal.filter { !orgFullNames.contains($0.fullName) }.sorted { $0.name < $1.name }
        repos = (allOrgRepos + personalRepos).sorted { $0.openIssuesCount > $1.openIssuesCount }
        isLoadingRepos = false
    }

    /// Load repos and apply active product filter.
    func loadRepos(appState: AppState) async {
        await loadRepos(token: appState.githubToken, orgs: appState.githubOrgs)
        let activeRepos = appState.activeGitHubRepos
        if !activeRepos.isEmpty {
            repos         = repos.filter         { activeRepos.contains($0.fullName) }
            orgRepos      = orgRepos.filter      { activeRepos.contains($0.fullName) }
            personalRepos = personalRepos.filter { activeRepos.contains($0.fullName) }
        }
    }

    func discoverOrgs(token: String) async {
        guard !token.isEmpty else { return }
        isDiscoveringOrgs = true
        discoveredOrgs = (try? await githubService.listUserOrgs(token: token)) ?? []
        isDiscoveringOrgs = false
    }

    func loadOverview(repo: GitHubRepo, token: String) async {
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        isLoadingOverview = true; repoDetail = nil; readme = ""
        do {
            repoDetail = try await githubService.getRepoDetail(owner: parts[0], repo: parts[1], token: token)
        } catch {
            self.error = "Repo detail: \(error.localizedDescription)"
        }
        readme = (try? await githubService.getReadme(owner: parts[0], repo: parts[1], token: token)) ?? ""
        isLoadingOverview = false
    }

    // MARK: - PR Actions

    func executeMerge(token: String) async {
        guard let repo = selectedRepo, let pr = selectedPR else { return }
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        do {
            let sha = try await githubService.mergePR(owner: parts[0], repo: parts[1], number: pr.number, method: mergeMethod, token: token)
            actionResult = "PR #\(pr.number) merged (sha: \(String(sha.prefix(7))))"
            await loadPRs(repo: repo, token: token)
        } catch { actionResult = "Merge failed: \(error.localizedDescription)" }
    }

    func executeApprove(token: String) async {
        guard let repo = selectedRepo, let pr = selectedPR else { return }
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        do {
            try await githubService.approvePR(owner: parts[0], repo: parts[1], number: pr.number, token: token)
            actionResult = "PR #\(pr.number) approved"
        } catch { actionResult = "Approve failed: \(error.localizedDescription)" }
    }

    func executeRequestChanges(token: String) async {
        guard let repo = selectedRepo, let pr = selectedPR else { return }
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        do {
            try await githubService.requestChanges(owner: parts[0], repo: parts[1], number: pr.number, body: requestChangesText, token: token)
            actionResult = "Changes requested on PR #\(pr.number)"
            requestChangesText = ""
        } catch { actionResult = "Failed: \(error.localizedDescription)" }
    }

    func executeClose(token: String) async {
        guard let repo = selectedRepo, let pr = selectedPR else { return }
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        do {
            try await githubService.closePR(owner: parts[0], repo: parts[1], number: pr.number, token: token)
            actionResult = "PR #\(pr.number) closed"
            await loadPRs(repo: repo, token: token)
        } catch { actionResult = "Close failed: \(error.localizedDescription)" }
    }

    func executeComment(token: String) async {
        guard let repo = selectedRepo, let pr = selectedPR else { return }
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        do {
            try await githubService.postComment(owner: parts[0], repo: parts[1], number: pr.number, body: commentText, token: token)
            actionResult = "Comment posted on PR #\(pr.number)"
            commentText = ""
        } catch { actionResult = "Comment failed: \(error.localizedDescription)" }
    }

    func loadPRs(repo: GitHubRepo, token: String) async {
        selectedRepo = repo; prs = []; prFiles = []; selectedPR = nil; aiAnalysis = nil
        isLoadingPRs = true
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { isLoadingPRs = false; return }
        do {
            async let prTask = githubService.listPRs(owner: parts[0], repo: parts[1], state: apiStateForFilter, token: token)
            async let runTask = githubService.getWorkflowRuns(owner: parts[0], repo: parts[1], token: token)
            prs = try await prTask
            workflowRuns = (try? await runTask) ?? []
        } catch { self.error = error.localizedDescription }
        isLoadingPRs = false
    }

    func loadBranches(repo: GitHubRepo, token: String) async {
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        branches = (try? await githubService.listBranches(owner: parts[0], repo: parts[1], token: token)) ?? []
    }

    func loadCommits(repo: GitHubRepo, token: String) async {
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return }
        commits = (try? await githubService.listCommits(owner: parts[0], repo: parts[1], token: token)) ?? []
    }

    func loadPRFiles(pr: GitHubPR, token: String) async {
        guard let repo = selectedRepo else { return }
        selectedPR = pr; prFiles = []; aiAnalysis = nil
        isLoadingFiles = true
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { isLoadingFiles = false; return }
        do {
            prFiles = try await githubService.getPRFiles(owner: parts[0], repo: parts[1], number: pr.number, token: token)
        } catch { self.error = error.localizedDescription }
        isLoadingFiles = false
    }

    // MARK: - AI

    func summarizePR() async {
        guard let pr = selectedPR else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        let filesContext = prFiles.isEmpty ? "" :
            "\n\nCHANGED FILES (\(prFiles.count)):\n" + prFiles.map { f in
                "  \(f.status.uppercased()): \(f.filename) (+\(f.additions) -\(f.deletions))"
            }.joined(separator: "\n")
        let patchContext = prFiles.compactMap { f -> String? in
            guard let patch = f.patch, !patch.isEmpty else { return nil }
            return "File: \(f.filename)\n\(String(patch.prefix(600)))"
        }.prefix(5).joined(separator: "\n\n---\n\n")

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Summarize this pull request concisely for an SRE engineer.

            PR #\(pr.number): \(pr.title)
            Author: @\(pr.authorLogin) | Branch: \(pr.headBranch) → \(pr.baseBranch)
            Created: \(pr.createdAt) | Draft: \(pr.isDraft)

            DESCRIPTION:
            \(pr.body.isEmpty ? "(No description)" : pr.body.prefix(2000))
            \(filesContext)
            \(patchContext.isEmpty ? "" : "\n\nSAMPLE DIFF:\n" + patchContext)

            Provide:
            1. **What it does** — 2–3 sentences
            2. **Key changes** — bullet list of the most important modifications
            3. **Potential risks** — reliability, performance, or security concerns
            4. **Suggested reviewers** — based on the files changed
            """)],
            systemPrompt: "You are an SRE engineer reviewing a GitHub pull request. Be specific about file paths and changes." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 1024
        )
        if self.aiError == nil { ProductivityTracker.shared.log(.aiPRSummary, detail: "PR #\(pr.number)", source: "GitHub") }
    }

    func reviewPR() async {
        guard let pr = selectedPR else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        let patchContext = prFiles.compactMap { f -> String? in
            guard let patch = f.patch else { return nil }
            return "### \(f.filename) (\(f.status))\n```diff\n\(patch.prefix(800))\n```"
        }.prefix(6).joined(separator: "\n\n")

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Do an SRE-focused code review of this pull request.

            PR #\(pr.number): \(pr.title)
            Branch: \(pr.headBranch) → \(pr.baseBranch)
            Description: \(pr.body.prefix(1000))

            DIFF:
            \(patchContext.isEmpty ? "(No diff available — files may be binary or too large)" : patchContext)

            Review focusing on SRE concerns:
            1. **Reliability** — error handling, retries, timeouts, graceful degradation
            2. **Performance** — N+1 queries, unbounded loops, memory leaks, connection pooling
            3. **Security** — credentials, SQL injection, input validation, permissions
            4. **Observability** — logging, metrics, tracing, alerting
            5. **Operability** — deployment safety, rollback, feature flags, config changes
            6. **Overall Recommendation** — Approve / Request Changes / Comment (with reason)

            Be specific: reference exact file names and line content from the diff.
            """)],
            systemPrompt: "You are a senior SRE reviewing code for production safety. Be specific and actionable." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 2048
        )
        if self.aiError == nil { ProductivityTracker.shared.log(.aiPRReview, detail: "PR #\(pr.number)", source: "GitHub") }
    }
}

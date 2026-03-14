import Foundation
import SwiftUI

@MainActor
final class GitHubBrowserViewModel: ObservableObject {
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
    @Published var orgName: String = "Mashery-Boomi"
    @Published var includePersonal = true
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

    func loadRepos(token: String, org: String) async {
        guard !token.isEmpty else { error = "GitHub token not configured."; return }
        isLoadingRepos = true; error = nil; orgRepos = []; personalRepos = []

        // Fetch org and personal repos in parallel, handling org failure gracefully
        async let orgTask: [GitHubRepo] = {
            if org.isEmpty { return [] }
            do {
                return try await githubService.listOrgRepos(org: org, token: token)
            } catch {
                return []  // gracefully ignore org errors (403/404)
            }
        }()
        async let personalTask: [GitHubRepo] = {
            do { return try await githubService.listUserRepos(token: token) }
            catch { return [] }
        }()

        let (orgResult, personal) = await (orgTask, personalTask)
        orgRepos = orgResult.sorted { $0.name < $1.name }
        // Personal: exclude repos already in org
        let orgFullNames = Set(orgResult.map(\.fullName))
        personalRepos = personal.filter { !orgFullNames.contains($0.fullName) }.sorted { $0.name < $1.name }
        repos = (orgResult + personalRepos).sorted { $0.openIssuesCount > $1.openIssuesCount }
        isLoadingRepos = false
    }

    func loadPRs(repo: GitHubRepo, token: String) async {
        selectedRepo = repo; prs = []; prFiles = []; selectedPR = nil; aiAnalysis = nil
        isLoadingPRs = true
        let parts = repo.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { isLoadingPRs = false; return }
        do {
            async let prTask = githubService.listPRs(owner: parts[0], repo: parts[1], token: token)
            async let runTask = githubService.getWorkflowRuns(owner: parts[0], repo: parts[1], token: token)
            prs = try await prTask
            workflowRuns = (try? await runTask) ?? []
        } catch { self.error = error.localizedDescription }
        isLoadingPRs = false
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
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiAnalysis = nil
        let filesContext = prFiles.isEmpty ? "" :
            "\n\nCHANGED FILES (\(prFiles.count)):\n" + prFiles.map { f in
                "  \(f.status.uppercased()): \(f.filename) (+\(f.additions) -\(f.deletions))"
            }.joined(separator: "\n")
        let patchContext = prFiles.compactMap { f -> String? in
            guard let patch = f.patch, !patch.isEmpty else { return nil }
            return "File: \(f.filename)\n\(String(patch.prefix(600)))"
        }.prefix(5).joined(separator: "\n\n---\n\n")

        do {
            aiAnalysis = try await claudeService.chat(
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
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
    }

    func reviewPR() async {
        guard let pr = selectedPR else { return }
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiAnalysis = nil
        let patchContext = prFiles.compactMap { f -> String? in
            guard let patch = f.patch else { return nil }
            return "### \(f.filename) (\(f.status))\n```diff\n\(patch.prefix(800))\n```"
        }.prefix(6).joined(separator: "\n\n")

        do {
            aiAnalysis = try await claudeService.chat(
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
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
    }
}

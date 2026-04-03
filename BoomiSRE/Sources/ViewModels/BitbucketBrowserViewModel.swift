import Foundation
import SwiftUI

@MainActor
final class BitbucketBrowserViewModel: ObservableObject, AIAnalyzable {
    @Published var repos: [BBRepo] = []
    @Published var selectedRepo: BBRepo?
    @Published var prs: [BBPR] = []
    @Published var selectedPR: BBPR?
    @Published var prDiff: String = ""
    @Published var prComments: [BBComment] = []
    @Published var branches: [BBBranch] = []
    @Published var pipelines: [BBPipeline] = []
    @Published var commits: [BBCommit] = []
    @Published var searchText: String = ""
    @Published var repoTab: Int = 0   // 0=PRs, 1=Branches, 2=Pipelines, 3=Commits
    @Published var prStateFilter: String = "OPEN"
    @Published var isLoadingRepos = false
    @Published var isLoadingPRs = false
    @Published var isLoadingDetail = false
    @Published var error: String?
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?
    @Published var actionResult: String?
    @Published var showConfirmAction: BBAction? = nil
    var lastFetched: Date?

    var depthHint: String = ""

    enum BBAction: Identifiable {
        case approvePR(BBPR), unapprovePR(BBPR), declinePR(BBPR), mergePR(BBPR), triggerPipeline(String)
        var id: String {
            switch self {
            case .approvePR(let pr): return "approve-\(pr.id)"
            case .unapprovePR(let pr): return "unapprove-\(pr.id)"
            case .declinePR(let pr): return "decline-\(pr.id)"
            case .mergePR(let pr): return "merge-\(pr.id)"
            case .triggerPipeline(let b): return "pipeline-\(b)"
            }
        }
        var title: String {
            switch self {
            case .approvePR: return "Approve PR"
            case .unapprovePR: return "Remove Approval"
            case .declinePR: return "Decline PR"
            case .mergePR: return "Merge PR"
            case .triggerPipeline: return "Trigger Pipeline"
            }
        }
        var isDestructive: Bool {
            switch self {
            case .declinePR, .mergePR: return true
            default: return false
            }
        }
    }

    private let service = BitbucketService()
    private let claudeService = ClaudeService()

    var filteredRepos: [BBRepo] {
        if searchText.isEmpty { return repos }
        return repos.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    func loadRepos(appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
        guard !appState.bitbucketAPIToken.isEmpty else {
            error = "Bitbucket token not configured — add it in Settings."
            return
        }
        let email = appState.bitbucketAuthUser
        let token = appState.bitbucketAPIToken
        let workspace = appState.bitbucketWorkspace
        isLoadingRepos = true; error = nil
        do {
            let activeBBRepos = appState.activeBitbucketRepos
            let fetched = try await service.listWorkspaceRepos(
                workspace: workspace,
                email: email,
                apiToken: token,
                filterRepos: Set(activeBBRepos)
            )
            repos = fetched
            lastFetched = Date()
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingRepos = false
    }

    func loadPRs(repo: BBRepo, appState: AppState) async {
        selectedRepo = repo; prs = []; selectedPR = nil; prDiff = ""; prComments = []; aiAnalysis = nil
        isLoadingPRs = true
        do {
            let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
            prs = try await service.listPRs(
                workspace: appState.bitbucketWorkspace, repoSlug: slug,
                state: prStateFilter, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken
            )
        } catch { self.error = error.localizedDescription }
        isLoadingPRs = false
    }

    func loadPRDetail(pr: BBPR, appState: AppState) async {
        guard let repo = selectedRepo else { return }
        selectedPR = pr; prDiff = ""; prComments = []
        isLoadingDetail = true
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        async let diffTask = service.getPRDiff(workspace: appState.bitbucketWorkspace, repoSlug: slug, prId: pr.id, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)
        async let commentsTask = service.getPRComments(workspace: appState.bitbucketWorkspace, repoSlug: slug, prId: pr.id, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)
        prDiff = (try? await diffTask) ?? ""
        prComments = (try? await commentsTask) ?? []
        isLoadingDetail = false
    }

    func loadBranches(repo: BBRepo, appState: AppState) async {
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        do {
            branches = try await service.listBranches(workspace: appState.bitbucketWorkspace, repoSlug: slug, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)
        } catch {
            branches = []
            self.error = "Branches: \(error.localizedDescription)"
        }
    }

    func loadPipelines(repo: BBRepo, appState: AppState) async {
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        do {
            pipelines = try await service.listPipelines(workspace: appState.bitbucketWorkspace, repoSlug: slug, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)
        } catch {
            pipelines = []
            self.error = "Pipelines: \(error.localizedDescription)"
        }
    }

    func loadCommits(repo: BBRepo, appState: AppState) async {
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        do {
            commits = try await service.listCommits(workspace: appState.bitbucketWorkspace, repoSlug: slug, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)
        } catch {
            commits = []
            self.error = "Commits: \(error.localizedDescription)"
        }
    }

    func reloadComments(pr: BBPR, appState: AppState) async {
        guard let repo = selectedRepo else { return }
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        prComments = (try? await service.getPRComments(workspace: appState.bitbucketWorkspace, repoSlug: slug, prId: pr.id, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)) ?? []
    }

    func postComment(pr: BBPR, text: String, appState: AppState) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let repo = selectedRepo else { return }
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        do {
            try await service.postPRComment(workspace: appState.bitbucketWorkspace, repoSlug: slug, prId: pr.id, comment: text, email: appState.bitbucketAuthUser, apiToken: appState.bitbucketAPIToken)
            actionResult = "Comment posted"
            await reloadComments(pr: pr, appState: appState)
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - AI
    func summarizePR(appState: AppState) async {
        guard let pr = selectedPR else { return }
        guard claudeService.isAIAvailable else { aiError = "No Anthropic API key."; return }
        let diffSnippet = prDiff.isEmpty ? "(No diff)" : String(prDiff.prefix(3000))
        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Summarize this Bitbucket pull request for an SRE engineer.
            PR #\(pr.id): \(pr.title)
            Author: \(pr.authorDisplayName) | \(pr.sourceBranch) → \(pr.destinationBranch)
            Description: \(pr.description.isEmpty ? "(none)" : String(pr.description.prefix(1000)))
            Comments: \(pr.commentCount)
            DIFF SAMPLE:
            \(diffSnippet)
            Provide: 1) What it does, 2) Key changes, 3) Risks
            """)],
            systemPrompt: "You are an SRE reviewing a Bitbucket pull request.",
            maxTokens: 1024
        )
        if self.aiError == nil { ProductivityTracker.shared.log(.aiPRSummary, source: "Bitbucket") }
    }

    func reviewPR(appState: AppState) async {
        guard let pr = selectedPR else { return }
        guard claudeService.isAIAvailable else { aiError = "No Anthropic API key."; return }
        let diffSnippet = prDiff.isEmpty ? "(No diff available)" : String(prDiff.prefix(4000))
        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Do an SRE-focused code review of this Bitbucket PR.
            PR #\(pr.id): \(pr.title)
            Branch: \(pr.sourceBranch) → \(pr.destinationBranch)
            DIFF:
            \(diffSnippet)
            Review: 1) Reliability 2) Performance 3) Security 4) Observability 5) Operability 6) Recommendation
            """)],
            systemPrompt: "You are a senior SRE reviewing code for production safety.",
            maxTokens: 2048
        )
        if self.aiError == nil { ProductivityTracker.shared.log(.aiPRReview, source: "Bitbucket") }
    }

    // MARK: - Actions
    func executeAction(_ action: BBAction, appState: AppState) async {
        guard let repo = selectedRepo else { return }
        let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.name
        let ws = appState.bitbucketWorkspace
        let email = appState.jiraEmail
        let token = appState.bitbucketAPIToken
        do {
            switch action {
            case .approvePR(let pr):
                try await service.approvePR(workspace: ws, repoSlug: slug, prId: pr.id, email: email, apiToken: token)
                actionResult = "PR #\(pr.id) approved"
            case .unapprovePR(let pr):
                try await service.unapprovePR(workspace: ws, repoSlug: slug, prId: pr.id, email: email, apiToken: token)
                actionResult = "Approval removed from PR #\(pr.id)"
            case .declinePR(let pr):
                try await service.declinePR(workspace: ws, repoSlug: slug, prId: pr.id, email: email, apiToken: token)
                actionResult = "PR #\(pr.id) declined"
                await loadPRs(repo: repo, appState: appState)
            case .mergePR(let pr):
                try await service.mergePR(workspace: ws, repoSlug: slug, prId: pr.id, message: "Merged via Boomi SRE", strategy: "merge_commit", email: email, apiToken: token)
                actionResult = "PR #\(pr.id) merged"
                await loadPRs(repo: repo, appState: appState)
            case .triggerPipeline(let branch):
                try await service.triggerPipeline(workspace: ws, repoSlug: slug, branch: branch, email: email, apiToken: token)
                actionResult = "Pipeline triggered on \(branch)"
                await loadPipelines(repo: repo, appState: appState)
            }
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }
}

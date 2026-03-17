import Foundation
import SwiftUI

/// Handles async data fetching for the inline notification detail pane.
/// One instance per expanded notification row, created via @StateObject.
@MainActor
final class NotificationDetailViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isLoading = false
    @Published var loadError: String?

    @Published var consoleOutput: String?
    @Published var jiraIssue: JiraIssueDetail?
    @Published var grafanaAlert: GrafanaAlertDetail?
    @Published var githubPR: GitHubPRDetail?

    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?

    // MARK: - Services

    private let jenkinsService    = JenkinsService()
    private let jiraService       = JiraService()
    private let grafanaService    = GrafanaService()
    private let githubService     = GitHubService()
    private let claudeService     = ClaudeService()
    private var depthHint: String = ""

    // MARK: - Load

    func loadDetail(for notification: SRENotification, appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
        isLoading = true
        loadError = nil
        switch notification.type {
        case .jenkinsBuildFailed, .jenkinsBuildRecovered:
            await loadJenkins(notification: notification, appState: appState)
        case .jiraAssigned, .jiraStatusChange:
            await loadJira(notification: notification, appState: appState)
        case .grafanaAlertFiring, .grafanaAlertResolved:
            await loadGrafana(notification: notification, appState: appState)
        case .githubPRReview, .githubPRMerged, .githubWorkflowFailed:
            await loadGitHub(notification: notification, appState: appState)
        default:
            break
        }
        isLoading = false
    }

    private func loadJenkins(notification: SRENotification, appState: AppState) async {
        guard !appState.jenkinsToken.isEmpty,
              let jobName  = notification.metadata["jobName"],
              let buildStr = notification.metadata["buildNumber"],
              let buildNum = Int(buildStr) else { return }
        do {
            consoleOutput = try await jenkinsService.getConsoleOutput(
                baseURL: appState.jenkinsURL, jobName: jobName, buildNumber: buildNum,
                username: appState.jenkinsUsername, token: appState.jenkinsToken
            )
        } catch {
            loadError = "Could not load console output: \(error.localizedDescription)"
        }
    }

    private func loadJira(notification: SRENotification, appState: AppState) async {
        guard appState.isJiraConfigured,
              let key = notification.metadata["ticketKey"] else { return }
        do {
            let result = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: "key = \(key)",
                fields: ["summary", "status", "priority", "assignee"],
                maxResults: 1
            )
            if let issue = result.issues.first {
                jiraIssue = JiraIssueDetail(
                    key: issue.key,
                    summary: issue.fields.summary ?? "",
                    status: issue.fields.status?.name ?? "",
                    priority: issue.fields.priority?.name ?? "",
                    description: ""
                )
            }
        } catch { /* graceful silent fail */ }
    }

    private func loadGrafana(notification: SRENotification, appState: AppState) async {
        guard !appState.grafanaToken.isEmpty,
              let uid = notification.metadata["alertUID"] else { return }
        do {
            let rules = try await grafanaService.listAlertRules(baseURL: appState.grafanaURL, token: appState.grafanaToken)
            if let rule = rules.first(where: { $0.uid == uid }) {
                grafanaAlert = GrafanaAlertDetail(uid: rule.uid, title: rule.title,
                                                  state: rule.state, labels: rule.labels,
                                                  summary: rule.summary)
            }
        } catch { /* graceful silent fail */ }
    }

    private func loadGitHub(notification: SRENotification, appState: AppState) async {
        guard !appState.githubToken.isEmpty,
              let owner = notification.metadata["owner"],
              let repo  = notification.metadata["repo"],
              let prStr = notification.metadata["prNumber"],
              let prNum = Int(prStr) else { return }
        do {
            let prs = try await githubService.listPRs(owner: owner, repo: repo,
                                                       state: "all", token: appState.githubToken)
            if let pr = prs.first(where: { $0.number == prNum }) {
                githubPR = GitHubPRDetail(
                    number: pr.number, title: pr.title, state: pr.state,
                    authorLogin: pr.authorLogin, headBranch: pr.headBranch,
                    baseBranch: pr.baseBranch, body: pr.body, isDraft: pr.isDraft
                )
            }
        } catch { /* graceful silent fail */ }
    }

    // MARK: - AI Analysis

    func analyzeWithAI(context: String) async {
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."
            return
        }
        isAnalyzing = true
        aiError = nil
        do {
            aiAnalysis = try await claudeService.chat(
                messages: [("user", "Analyze this SRE event and provide a brief assessment with recommended actions:\n\n\(context)")],
                systemPrompt: "You are an SRE assistant. Be concise — 3–5 bullet points max. Focus on what matters and what to do next." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
                maxTokens: 512
            )
        } catch {
            aiError = error.localizedDescription
        }
        isAnalyzing = false
    }

    var hasAPIKey: Bool { claudeService.isAIAvailable }
}

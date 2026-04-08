import Foundation
import SwiftUI

/// Handles async data fetching for the inline notification detail pane.
@Observable
@MainActor
final class NotificationDetailViewModel {

    // MARK: - State

    var isLoading = false
    var loadError: String?

    var consoleOutput: String?
    var jiraIssue: JiraIssueDetail?
    var grafanaAlert: GrafanaAlertDetail?
    var githubPR: GitHubPRDetail?

    var aiAnalysis: String?
    var isAnalyzing = false
    var aiError: String?

    // Jira actions
    var transitions: [JiraTransition] = []
    var commentText: String = ""
    var isSubmittingComment = false
    var commentSuccess: String?
    var isTransitioning = false
    var transitionSuccess: String?

    // MARK: - Services (not observed)

    @ObservationIgnored private let jenkinsService    = JenkinsService()
    @ObservationIgnored private let jiraService       = JiraService()
    @ObservationIgnored private let grafanaService    = GrafanaService()
    @ObservationIgnored private let githubService     = GitHubService()
    @ObservationIgnored private let claudeService     = ClaudeService()
    @ObservationIgnored private var depthHint: String = ""

    // MARK: - Load

    func loadDetail(for notification: SRENotification, appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
        withAnimation(.none) { isLoading = true; loadError = nil }
        switch notification.type {
        case .jenkinsBuildFailed, .jenkinsBuildRecovered:
            await loadJenkins(notification: notification, appState: appState)
        case .jiraAssigned, .jiraStatusChange, .jiraNewComment, .jiraMentioned:
            await loadJira(notification: notification, appState: appState)
        case .grafanaAlertFiring, .grafanaAlertResolved:
            await loadGrafana(notification: notification, appState: appState)
        case .githubPRReview, .githubPRMerged, .githubWorkflowFailed:
            await loadGitHub(notification: notification, appState: appState)
        default:
            break
        }
        withAnimation(.none) { isLoading = false }
    }

    private func loadJenkins(notification: SRENotification, appState: AppState) async {
        guard !appState.jenkinsToken.isEmpty,
              let jobName  = notification.metadata["jobName"],
              let buildStr = notification.metadata["buildNumber"],
              let buildNum = Int(buildStr) else { return }
        do {
            let output = try await jenkinsService.getConsoleOutput(
                baseURL: appState.jenkinsURL, jobName: jobName, buildNumber: buildNum,
                username: appState.jenkinsUsername, token: appState.jenkinsToken
            )
            withAnimation(.none) { consoleOutput = output }
        } catch {
            loadError = "Could not load console output: \(error.localizedDescription)"
        }
    }

    private func loadJira(notification: SRENotification, appState: AppState) async {
        guard appState.isJiraConfigured,
              let key = notification.metadata["ticketKey"] else { return }

        do {
            let (issue, raw) = try await jiraService.getIssue(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                key: key
            )
            let rawFields = (raw["fields"] as? [String: Any]) ?? [:]
            let descMarkdown = extractMarkdownFromADF(rawFields["description"] as? [String: Any])
            withAnimation(.none) {
                jiraIssue = JiraIssueDetail(
                    key: issue.key,
                    summary: issue.fields.summary ?? "",
                    status: issue.fields.status?.name ?? "",
                    priority: issue.fields.priority?.name ?? "",
                    description: descMarkdown
                )
            }
        } catch {
            loadError = "Could not load ticket details: \(error.localizedDescription)"
        }

        // Load transitions in background — don't block the detail pane from showing
        let base = appState.jiraBaseURL, email = appState.jiraEmail, token = appState.jiraAPIToken
        let svc = jiraService
        Task { [weak self] in
            let result = (try? await svc.getTransitions(
                baseURL: base, email: email, apiToken: token, key: key
            )) ?? []
            await MainActor.run { withAnimation(.none) { self?.transitions = result } }
        }
    }

    private func loadGrafana(notification: SRENotification, appState: AppState) async {
        guard !appState.grafanaToken.isEmpty,
              let uid = notification.metadata["alertUID"] else { return }
        do {
            let rules = try await grafanaService.listAlertRules(baseURL: appState.grafanaURL, token: appState.grafanaToken)
            if let rule = rules.first(where: { $0.uid == uid }) {
                withAnimation(.none) {
                    grafanaAlert = GrafanaAlertDetail(uid: rule.uid, title: rule.title,
                                                      state: rule.state, labels: rule.labels,
                                                      summary: rule.summary)
                }
            }
        } catch {
            loadError = "Could not load alert details: \(error.localizedDescription)"
        }
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
                withAnimation(.none) {
                    githubPR = GitHubPRDetail(
                        number: pr.number, title: pr.title, state: pr.state,
                        authorLogin: pr.authorLogin, headBranch: pr.headBranch,
                        baseBranch: pr.baseBranch, body: pr.body, isDraft: pr.isDraft
                    )
                }
            }
        } catch {
            loadError = "Could not load PR details: \(error.localizedDescription)"
        }
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

    // MARK: - Jira Actions

    func submitComment(for key: String, appState: AppState) async {
        let text = commentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, appState.isJiraConfigured else { return }
        isSubmittingComment = true
        commentSuccess = nil
        do {
            try await jiraService.addComment(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, body: text
            )
            commentText = ""
            commentSuccess = "Comment added"
        } catch {
            commentSuccess = "Failed: \(error.localizedDescription)"
        }
        isSubmittingComment = false
    }

    // MARK: - ADF to Markdown extraction

    private func extractMarkdownFromADF(_ node: [String: Any]?) -> String {
        guard let node else { return "" }
        let nodeType = node["type"] as? String ?? ""
        if nodeType == "text" {
            var text = node["text"] as? String ?? ""
            if let marks = node["marks"] as? [[String: Any]] {
                for mark in marks {
                    switch mark["type"] as? String ?? "" {
                    case "strong": text = "**\(text)**"
                    case "em": text = "*\(text)*"
                    case "code": text = "`\(text)`"
                    case "strike": text = "~~\(text)~~"
                    case "link":
                        if let href = (mark["attrs"] as? [String: Any])?["href"] as? String {
                            text = "[\(text)](\(href))"
                        }
                    default: break
                    }
                }
            }
            return text
        }
        let children = node["content"] as? [[String: Any]] ?? []
        let childTexts = children.map { extractMarkdownFromADF($0) }
        switch nodeType {
        case "paragraph":   return childTexts.joined() + "\n\n"
        case "heading":
            let level = (node["attrs"] as? [String: Any])?["level"] as? Int ?? 1
            return String(repeating: "#", count: level) + " " + childTexts.joined() + "\n\n"
        case "bulletList", "orderedList": return childTexts.joined()
        case "listItem":    return "- " + childTexts.joined().trimmingCharacters(in: .newlines) + "\n"
        case "codeBlock":   return "```\n" + childTexts.joined() + "\n```\n\n"
        case "hardBreak":   return "\n"
        default:            return childTexts.joined()
        }
    }

    func transitionIssue(key: String, transitionId: String, appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        isTransitioning = true
        transitionSuccess = nil
        do {
            try await jiraService.transitionIssue(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key, transitionId: transitionId
            )
            let name = transitions.first { $0.id == transitionId }?.name ?? "done"
            transitionSuccess = "Moved to \(name)"
            // Refresh transitions after the change
            transitions = (try? await jiraService.getTransitions(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, key: key
            )) ?? []
        } catch {
            transitionSuccess = "Failed: \(error.localizedDescription)"
        }
        isTransitioning = false
    }
}

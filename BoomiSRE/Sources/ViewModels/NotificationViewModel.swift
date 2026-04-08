import Foundation
import SwiftUI
import UserNotifications

/// Background polling engine and notification store.
/// Owned at the app level and shared via .environment().
@Observable
@MainActor
final class NotificationViewModel {

    // MARK: - Published State

    var notifications: [SRENotification] = []
    var isPolling = false
    var lastPolled: Date?
    var pollError: String?
    /// Rolling log of the last 5 poll errors (service name + message). Useful for diagnosing
    /// "notifications aren't working" without surfacing transient errors to users.
    var recentPollErrors: [(service: String, message: String, at: Date)] = []
    /// Per-service poll errors visible to the UI (service name → error message).
    var pollErrors: [String: String] = [:]

    // MARK: - Polling Config

    /// Services to poll (can be toggled in settings).
    var pollJira       = true
    var pollJenkins    = true
    var pollGrafana    = true
    var pollGitHub     = true
    var pollConfluence = true
    var pollAWSCosts   = true
    var systemNotificationsEnabled = true
    var refreshInterval: TimeInterval = 300   // 5 minutes
    var archiveRetention: ArchiveRetention = .hours24

    // MARK: - Last-Known State (for change detection)

    @ObservationIgnored private var lastKnownJiraKeys:        Set<String>    = []
    @ObservationIgnored private var lastKnownJiraStatuses:    [String: String] = [:]  // key → status
    @ObservationIgnored private var lastKnownFailedBuilds:    [String: Int]   = [:]  // job → build #
    @ObservationIgnored private var lastKnownAlertingUIDs:    Set<String>     = []
    @ObservationIgnored private var lastKnownReviewPRs:       Set<Int>        = []   // PR numbers
    @ObservationIgnored private var lastKnownConfluencePages: [String: Int]   = [:]  // pageID → version
    @ObservationIgnored private var lastKnownCommentCounts:  [String: Int]    = [:]  // issueKey → comment total
    @ObservationIgnored private var initialised = false

    // MARK: - Services

    @ObservationIgnored private let jiraService       = JiraService()
    @ObservationIgnored private let jenkinsService    = JenkinsService()
    @ObservationIgnored private let grafanaService    = GrafanaService()
    @ObservationIgnored private let githubService     = GitHubService()
    @ObservationIgnored private let confluenceService = ConfluenceService()
    @ObservationIgnored private let historyURL: URL

    // MARK: - Background Polling Task

    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.historyURL = home.appendingPathComponent(".boomi_sre_notifications.json")
        loadHistory()
        requestSystemNotificationPermission()
    }

    // MARK: - Polling Lifecycle

    func startPolling(appState: AppState) {
        // Sync settings from AppState
        pollJira       = appState.pollJiraEnabled
        pollJenkins    = appState.pollJenkinsEnabled
        pollGrafana    = appState.pollGrafanaEnabled
        pollGitHub     = appState.pollGitHubEnabled
        pollConfluence = appState.pollConfluenceEnabled
        pollAWSCosts   = appState.pollAWSCostsEnabled
        systemNotificationsEnabled = appState.systemNotificationsEnabled
        archiveRetention = appState.archiveRetention
        refreshInterval = appState.refreshInterval

        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Initial poll immediately
            await self.pollAllServices(appState: appState)
            while !Task.isCancelled {
                let interval = self.refreshInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.pollAllServices(appState: appState)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Main Poll

    func pollAllServices(appState: AppState) async {
        isPolling = true
        pollError = nil
        pollErrors.removeAll()

        // Capture credentials on MainActor before the concurrent block
        let jiraBase  = appState.jiraBaseURL
        let jiraEmail = appState.jiraEmail
        let jiraToken = appState.jiraAPIToken
        let jiraOK    = appState.isJiraConfigured && pollJira

        let jkURL     = appState.jenkinsURL
        let jkUser    = appState.jenkinsUsername
        let jkToken   = appState.jenkinsToken
        let jkOK      = !jkToken.isEmpty && !jkURL.isEmpty && pollJenkins

        let gfURL     = appState.grafanaURL
        let gfToken   = appState.grafanaToken
        let gfOK      = !gfToken.isEmpty && !gfURL.isEmpty && pollGrafana

        let ghToken   = appState.githubToken
        let ghOK      = !ghToken.isEmpty && pollGitHub

        let cfBase    = appState.jiraBaseURL   // same Atlassian instance
        let cfEmail   = appState.jiraEmail
        let cfToken   = appState.confluenceAPIToken
        let cfOK      = !cfToken.isEmpty && !cfBase.isEmpty && pollConfluence

        // Capture product filter context
        let hasProductFilter  = !appState.activeProductIds.isEmpty
        let activeProjectKeys = hasProductFilter ? appState.activeJiraProjectKeys : [String]()
        let activeJobs        = appState.activeJenkinsJobs
        let activeGrafanaTags = hasProductFilter ?
            appState.products.filter { appState.activeProductIds.contains($0.id) }
                .flatMap { $0.grafanaDashboardTags } : [String]()
        let activeGitHubRepos      = appState.activeGitHubRepos
        let activeConfluenceSpaces = appState.activeConfluenceSpaces

        // When a product IS selected but a service has no mapped resources, skip it entirely
        let skipJira       = hasProductFilter && activeProjectKeys.isEmpty
        let skipJenkins    = hasProductFilter && activeJobs.isEmpty
        let skipGrafana    = hasProductFilter && activeGrafanaTags.isEmpty
        let skipGitHub     = hasProductFilter && activeGitHubRepos.isEmpty
        let skipConfluence = hasProductFilter && activeConfluenceSpaces.isEmpty

        // Run polls concurrently
        await withTaskGroup(of: [SRENotification].self) { group in
            if jiraOK && !skipJira {
                group.addTask { await self.pollJira(baseURL: jiraBase, email: jiraEmail, token: jiraToken, activeProjectKeys: activeProjectKeys) }
            }
            if jkOK && !skipJenkins {
                group.addTask { await self.pollJenkins(baseURL: jkURL, username: jkUser, token: jkToken, activeJobs: activeJobs) }
            }
            if gfOK && !skipGrafana {
                group.addTask { await self.pollGrafana(baseURL: gfURL, token: gfToken, activeGrafanaTags: activeGrafanaTags) }
            }
            if ghOK && !skipGitHub {
                group.addTask { await self.pollGitHub(token: ghToken, userEmail: jiraEmail, activeRepos: activeGitHubRepos) }
            }
            if cfOK && !skipConfluence {
                group.addTask { await self.pollConfluencePages(baseURL: cfBase, email: cfEmail, token: cfToken, activeSpaces: activeConfluenceSpaces) }
            }

            for await newItems in group {
                for item in newItems {
                    appendNotification(item)
                }
            }
        }

        initialised = true
        lastPolled = Date()
        isPolling = false
        saveHistory()
    }

    // MARK: - Jira Poll

    private func pollJira(baseURL: String, email: String, token: String, activeProjectKeys: [String] = []) async -> [SRENotification] {
        var results: [SRENotification] = []
        do {
            // Broader JQL: assigned, reporter, or watcher
            var jql = "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser()) AND statusCategory NOT IN (Done)"
            if !activeProjectKeys.isEmpty {
                let filter = activeProjectKeys.map { "\"\($0)\"" }.joined(separator: ", ")
                jql += " AND project IN (\(filter))"
            }
            jql += " ORDER BY updated DESC"
            let result = try await jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql,
                fields: ["summary", "status", "priority", "issuetype", "updated", "comment"],
                maxResults: 50
            )

            // Get current user's display name for filtering self-comments
            let myDisplayName = (try? await jiraService.checkAuth(baseURL: baseURL, email: email, apiToken: token)) ?? ""

            let currentKeys    = Set(result.issues.map(\.key))
            let currentStatuses: [String: String] = result.issues.reduce(into: [:]) {
                $0[$1.key] = $1.fields.status?.name ?? ""
            }

            if initialised {
                // New assignments
                for issue in result.issues where !lastKnownJiraKeys.contains(issue.key) {
                    let n = SRENotification(
                        type: .jiraAssigned,
                        title: "Assigned: \(issue.key)",
                        body: issue.fields.summary ?? "(no summary)",
                        deepLink: "jira_todo",
                        metadata: [
                            "ticketKey": issue.key,
                            "summary": issue.fields.summary ?? "",
                            "status": issue.fields.status?.name ?? "",
                            "priority": issue.fields.priority?.name ?? ""
                        ]
                    )
                    results.append(n)
                }
                // Status changes
                for issue in result.issues {
                    let newStatus = issue.fields.status?.name ?? ""
                    if let oldStatus = lastKnownJiraStatuses[issue.key],
                       !oldStatus.isEmpty, oldStatus != newStatus {
                        let n = SRENotification(
                            type: .jiraStatusChange,
                            title: "\(issue.key) → \(newStatus)",
                            body: issue.fields.summary ?? "",
                            deepLink: "jira_todo",
                            metadata: [
                                "ticketKey": issue.key,
                                "summary": issue.fields.summary ?? "",
                                "oldStatus": oldStatus,
                                "newStatus": newStatus
                            ]
                        )
                        results.append(n)
                    }
                }

                // Comment tracking — detect new comments and mentions
                for issue in result.issues {
                    let commentTotal = issue.fields.commentTotal ?? 0
                    let lastKnown = lastKnownCommentCounts[issue.key] ?? 0
                    if commentTotal > lastKnown && lastKnown > 0 {
                        // Fetch latest comment to get author and check for mentions
                        let comments = (try? await jiraService.getIssueComments(
                            baseURL: baseURL, email: email, apiToken: token, issueKey: issue.key
                        )) ?? []
                        if let latest = comments.last, latest.authorName != myDisplayName {
                            // Check if the comment mentions the current user
                            let bodyLower = latest.bodyText.lowercased()
                            let isMention = bodyLower.contains(myDisplayName.lowercased()) ||
                                bodyLower.contains("@\(email.components(separatedBy: "@").first ?? "")")

                            if isMention {
                                results.append(SRENotification(
                                    type: .jiraMentioned,
                                    title: "Mentioned in \(issue.key)",
                                    body: "\(latest.authorName): \(String(latest.bodyText.prefix(120)))",
                                    deepLink: "jira_todo",
                                    metadata: [
                                        "ticketKey": issue.key,
                                        "summary": issue.fields.summary ?? "",
                                        "commenter": latest.authorName,
                                        "commentBody": String(latest.bodyText.prefix(300))
                                    ]
                                ))
                            } else {
                                results.append(SRENotification(
                                    type: .jiraNewComment,
                                    title: "Comment on \(issue.key)",
                                    body: "\(latest.authorName): \(String(latest.bodyText.prefix(120)))",
                                    deepLink: "jira_todo",
                                    metadata: [
                                        "ticketKey": issue.key,
                                        "summary": issue.fields.summary ?? "",
                                        "commenter": latest.authorName,
                                        "commentBody": String(latest.bodyText.prefix(300))
                                    ]
                                ))
                            }
                        }
                    }
                    lastKnownCommentCounts[issue.key] = commentTotal
                }
            } else {
                // First poll — seed comment counts without generating notifications
                for issue in result.issues {
                    lastKnownCommentCounts[issue.key] = issue.fields.commentTotal ?? 0
                }
            }

            lastKnownJiraKeys    = currentKeys
            lastKnownJiraStatuses = currentStatuses
        } catch { recordPollError(service: "Jira", error) }
        return results
    }

    // MARK: - Jenkins Poll

    private func pollJenkins(baseURL: String, username: String, token: String, activeJobs: [String] = []) async -> [SRENotification] {
        var results: [SRENotification] = []
        do {
            var jobs = try await jenkinsService.listJobs(baseURL: baseURL, username: username, token: token)
            if !activeJobs.isEmpty {
                jobs = jobs.filter { activeJobs.contains($0.name) }
            }
            for job in jobs {
                let isFailing = job.color.hasPrefix("red")
                let builds = try? await jenkinsService.getBuildHistory(
                    baseURL: baseURL, jobName: job.name, username: username, token: token, limit: 1
                )
                guard let latestBuild = builds?.first else { continue }

                if initialised {
                    let lastKnown = lastKnownFailedBuilds[job.name] ?? 0
                    if isFailing && latestBuild.result == "FAILURE" && latestBuild.number > lastKnown {
                        results.append(SRENotification(
                            type: .jenkinsBuildFailed,
                            title: "Build failed: \(job.name)",
                            body: "Build #\(latestBuild.number) failed — \(latestBuild.formattedDuration)",
                            deepLink: "jenkins_browser",
                            metadata: [
                                "jobName": job.name,
                                "buildNumber": "\(latestBuild.number)",
                                "buildURL": latestBuild.url,
                                "duration": latestBuild.formattedDuration
                            ]
                        ))
                        lastKnownFailedBuilds[job.name] = latestBuild.number
                    } else if !isFailing && lastKnown > 0 && latestBuild.result == "SUCCESS" {
                        // Was previously tracked as failed, now recovered
                        results.append(SRENotification(
                            type: .jenkinsBuildRecovered,
                            title: "Build recovered: \(job.name)",
                            body: "Build #\(latestBuild.number) succeeded — \(latestBuild.formattedDuration)",
                            deepLink: "jenkins_browser",
                            metadata: [
                                "jobName": job.name,
                                "buildNumber": "\(latestBuild.number)",
                                "buildURL": latestBuild.url,
                                "duration": latestBuild.formattedDuration
                            ]
                        ))
                        lastKnownFailedBuilds.removeValue(forKey: job.name)
                    }
                } else {
                    // First poll — seed last known state without generating notifications
                    if isFailing && latestBuild.result == "FAILURE" {
                        lastKnownFailedBuilds[job.name] = latestBuild.number
                    }
                }
            }
        } catch { recordPollError(service: "Jenkins", error) }
        return results
    }

    // MARK: - Grafana Poll

    private func pollGrafana(baseURL: String, token: String, activeGrafanaTags: [String] = []) async -> [SRENotification] {
        var results: [SRENotification] = []
        do {
            let rules = try await grafanaService.listAlertRules(baseURL: baseURL, token: token)
            var alertingRules = rules.filter { $0.state.lowercased() == "alerting" }
            if !activeGrafanaTags.isEmpty {
                alertingRules = alertingRules.filter { rule in
                    activeGrafanaTags.contains { tag in
                        rule.labels.keys.contains { $0.lowercased() == tag.lowercased() } ||
                        rule.labels.values.contains { $0.lowercased() == tag.lowercased() }
                    }
                }
            }
            let firingUIDs = Set(alertingRules.map(\.uid))

            if initialised {
                // New alerts firing
                let newFiring = firingUIDs.subtracting(lastKnownAlertingUIDs)
                for uid in newFiring {
                    if let rule = rules.first(where: { $0.uid == uid }) {
                        results.append(SRENotification(
                            type: .grafanaAlertFiring,
                            title: "Alert firing: \(rule.title)",
                            body: rule.summary.isEmpty ? "Grafana alert is firing" : rule.summary,
                            deepLink: "grafana_browser",
                            metadata: [
                                "alertUID": uid,
                                "alertTitle": rule.title,
                                "alertSummary": rule.summary
                            ]
                        ))
                    }
                }
                // Alerts that resolved
                let resolved = lastKnownAlertingUIDs.subtracting(firingUIDs)
                for uid in resolved {
                    // Try to find rule info (may not exist if rule was deleted)
                    let title = rules.first(where: { $0.uid == uid })?.title ?? uid
                    results.append(SRENotification(
                        type: .grafanaAlertResolved,
                        title: "Alert resolved: \(title)",
                        body: "Grafana alert is no longer firing",
                        deepLink: "grafana_browser",
                        metadata: [
                            "alertUID": uid,
                            "alertTitle": title,
                            "alertSummary": ""
                        ]
                    ))
                }
            }

            lastKnownAlertingUIDs = firingUIDs
        } catch { recordPollError(service: "Grafana", error) }
        return results
    }

    // MARK: - GitHub Poll

    private func pollGitHub(token: String, userEmail: String, activeRepos: [String] = []) async -> [SRENotification] {
        var results: [SRENotification] = []
        do {
            let orgRepos = try await githubService.listOrgRepos(org: "Mashery-Boomi", token: token)
            // Filter repos when product filter provides specific repos
            let filteredRepos: [GitHubRepo]
            if !activeRepos.isEmpty {
                filteredRepos = orgRepos.filter { repo in
                    activeRepos.contains(repo.fullName) || activeRepos.contains(repo.name)
                }
            } else {
                filteredRepos = Array(orgRepos)
            }
            var newPRNumbers: Set<Int> = []

            for repo in filteredRepos.prefix(10) {
                let parts = repo.fullName.split(separator: "/").map(String.init)
                guard parts.count == 2 else { continue }
                let prs = (try? await githubService.listPRs(owner: parts[0], repo: parts[1], token: token)) ?? []

                for pr in prs where !pr.requestedReviewers.isEmpty {
                    newPRNumbers.insert(pr.number)
                    if initialised && !lastKnownReviewPRs.contains(pr.number) {
                        let parts2 = repo.fullName.split(separator: "/").map(String.init)
                        let n = SRENotification(
                            type: .githubPRReview,
                            title: "PR review requested: #\(pr.number)",
                            body: "\(repo.name): \(pr.title)",
                            deepLink: "github_browser",
                            metadata: [
                                "owner": parts2.first ?? "",
                                "repo": parts2.last ?? repo.name,
                                "prNumber": "\(pr.number)",
                                "prTitle": pr.title,
                                "authorLogin": pr.authorLogin,
                                "htmlURL": pr.htmlURL
                            ]
                        )
                        results.append(n)
                    }
                }
            }

            lastKnownReviewPRs = newPRNumbers
        } catch { recordPollError(service: "GitHub", error) }
        return results
    }

    // MARK: - Confluence Poll

    private func pollConfluencePages(baseURL: String, email: String, token: String, activeSpaces: [String] = []) async -> [SRENotification] {
        var results: [SRENotification] = []
        do {
            // Fetch recently-updated pages across all spaces (use CQL search for recency)
            let allPages = try await confluenceService.recentlyModifiedPages(
                baseURL: baseURL, email: email, apiToken: token, limit: 20
            )
            // Filter by active Confluence spaces when product filter is set
            let pages: [ConfluenceService.ConfluencePage]
            if !activeSpaces.isEmpty {
                pages = allPages.filter { activeSpaces.contains($0.spaceKey) }
            } else {
                pages = allPages
            }
            for page in pages {
                let knownVersion = lastKnownConfluencePages[page.id]
                if initialised, let known = knownVersion, page.version > known {
                    results.append(SRENotification(
                        type: .confluencePageUpdated,
                        title: "Page updated: \(page.title)",
                        body: "Updated in \(page.spaceKey) by \(page.authorName)",
                        deepLink: "confluence_browser",
                        metadata: [
                            "pageID": page.id,
                            "pageTitle": page.title,
                            "spaceKey": page.spaceKey,
                            "authorName": page.authorName,
                            "pageURL": page.url
                        ]
                    ))
                }
                lastKnownConfluencePages[page.id] = page.version
            }
        } catch { recordPollError(service: "Confluence", error) }
        return results
    }

    // MARK: - Programmatic Notification (called by other ViewModels)

    func addBriefingNotification(type: BriefingType) {
        let n = SRENotification(
            type: .briefingGenerated,
            title: "\(type.title) ready",
            body: "Your \(type.title) has been generated.",
            deepLink: "exec_assistant",
            metadata: ["briefingType": type.rawValue]
        )
        appendNotification(n)
        saveHistory()
    }

    // MARK: - Notification Management

    /// Active (non-archived) notifications.
    var activeNotifications: [SRENotification] {
        notifications.filter { !$0.isArchived }
    }

    /// Archived notifications still within the retention window.
    var archivedNotifications: [SRENotification] {
        let cutoff = archiveRetention.cutoff()
        return notifications.filter { n in
            n.isArchived && (n.archivedAt ?? n.timestamp) > cutoff
        }
    }

    /// Unread count across active (non-archived) notifications only.
    var unreadCount: Int { activeNotifications.filter { !$0.isRead }.count }

    func markAllRead() {
        for i in notifications.indices where !notifications[i].isArchived {
            notifications[i].isRead = true
        }
        saveHistory()
    }

    func markRead(_ notification: SRENotification) {
        if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[idx].isRead = true
            saveHistory()
        }
    }

    /// Move all read active notifications to the archive.
    func archiveRead() {
        let now = Date()
        for i in notifications.indices where notifications[i].isRead && !notifications[i].isArchived {
            notifications[i].isArchived = true
            notifications[i].archivedAt = now
        }
        saveHistory()
    }

    /// Permanently remove all archived notifications.
    func clearArchive() {
        notifications.removeAll { $0.isArchived }
        saveHistory()
    }

    /// Permanently remove everything (active + archived).
    func clear() {
        notifications.removeAll()
        saveHistory()
    }

    // MARK: - Poll Error Tracking

    private func recordPollError(service: String, _ error: Error) {
        recentPollErrors.append((service: service, message: error.localizedDescription, at: Date()))
        if recentPollErrors.count > 5 { recentPollErrors.removeFirst() }
        pollErrors[service] = error.localizedDescription
    }

    // MARK: - Internal Append + System Notification

    private func appendNotification(_ n: SRENotification) {
        // Deduplicate: don't add if same type+metadata within 10 minutes
        let recentCutoff = Date().addingTimeInterval(-600)
        let isDuplicate = notifications.contains { existing in
            existing.type == n.type &&
            existing.metadata == n.metadata &&
            existing.timestamp > recentCutoff
        }
        guard !isDuplicate else { return }

        notifications.insert(n, at: 0)
        // Keep last 200
        if notifications.count > 200 { notifications = Array(notifications.prefix(200)) }

        // Post macOS system notification for high-priority types
        if n.type.isHighPriority && systemNotificationsEnabled {
            postSystemNotification(title: n.title, body: n.body)
        }
    }

    // MARK: - macOS System Notifications

    private func requestSystemNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func postSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([SRENotification].self, from: data) else { return }
        let activityCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let archiveCutoff  = archiveRetention.cutoff()
        notifications = decoded.filter { n in
            if n.isArchived {
                // Keep archived items within the retention window
                return (n.archivedAt ?? n.timestamp) > archiveCutoff
            } else {
                // Keep active items from the last 7 days
                return n.timestamp > activityCutoff
            }
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(notifications) {
            try? data.write(to: historyURL)
        }
    }
}

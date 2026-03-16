import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var myTickets: [JiraIssue] = []
    @Published var recentPRs: [GitHubPR] = []
    @Published var recentBuilds: [(jobName: String, build: JenkinsBuild)] = []
    @Published var firingAlerts: [GrafanaAlertRule] = []
    @Published var jsmOpsAlerts: [OpsAlert] = []
    @Published var recentNotifications: [SRENotification] = []
    @Published var onCallSchedules: [OpsSchedule] = []
    @Published var onCallParticipants: [String: [OnCallParticipant]] = [:]
    @Published var onCallDisplayNames: [String: String] = [:]
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var unreadEmails: [GmailMessage] = []
    @Published var activeIncidents: [Incident] = []
    @Published var feedItems: [FeedItem] = []
    @Published var productRelevantArticles: [KnowledgeBaseService.KBArticle] = []
    @Published var aiSummary: String?
    @Published var aiSummaryDate: Date?
    @Published var isLoading = false
    @Published var loadErrors: [String] = []
    @Published var widgetFirstAlerted: [WidgetType: Date] = [:]

    private let jiraService    = JiraService()
    private let githubService  = GitHubService()
    private let jenkinsService = JenkinsService()
    private let grafanaService = GrafanaService()
    private let googleService  = GoogleService()
    private let claudeService  = ClaudeService()
    private let jsmOpsService = JSMOpsService()
    private let incidentJiraService = JiraService()

    func refreshAll(appState: AppState, notificationVM: NotificationViewModel? = nil) async {
        isLoading = true
        loadErrors = []
        if let nvm = notificationVM { recentNotifications = Array(nvm.notifications.prefix(10)) }

        let jiraOK      = appState.isJiraConfigured
        let ghToken     = appState.githubToken
        let jkURL       = appState.jenkinsURL
        let jkUser      = appState.jenkinsUsername
        let jkToken     = appState.jenkinsToken
        let gfURL       = appState.grafanaURL
        let gfToken     = appState.grafanaToken
        let googleCreds = appState.googleCredentials

        await withTaskGroup(of: Void.self) { group in
            if jiraOK {
                group.addTask { await self.loadJiraTickets(appState: appState) }
                group.addTask { await self.loadJSMOpsAlerts(appState: appState) }
                group.addTask { await self.loadIncidents(appState: appState) }
                group.addTask { await self.loadOnCallForDashboard(appState: appState) }
            }
            if !ghToken.isEmpty {
                group.addTask { await self.loadRecentPRs(token: ghToken, appState: appState) }
            }
            if !jkToken.isEmpty && !jkURL.isEmpty {
                group.addTask { await self.loadJenkinsBuilds(baseURL: jkURL, username: jkUser, token: jkToken, appState: appState) }
            }
            if !gfToken.isEmpty && !gfURL.isEmpty {
                group.addTask { await self.loadGrafanaAlerts(baseURL: gfURL, token: gfToken, appState: appState) }
            }
            if let creds = googleCreds {
                group.addTask { await self.loadCalendarEvents(credentials: creds) }
                group.addTask { await self.loadUnreadEmails(credentials: creds) }
            }
            for await _ in group {}
        }

        // AI summary: generate if never generated or >4 hours old
        if claudeService.discoverAPIKey() != nil {
            let needsRefresh = aiSummaryDate.map { Date().timeIntervalSince($0) > 4 * 3600 } ?? true
            if needsRefresh { await generateAISummary(appState: appState) }
        }

        // Track first-alert timestamps for time-based urgency escalation (Phase 37F)
        updateFirstAlertedTimestamps()

        // Build feed first (without enrichment) so UI transitions directly from skeleton → feed,
        // never passing through "All Clear". isLoading stays true until feed is ready.
        var feed = buildFeed(appState: appState)
        feedItems = feed          // populate before isLoading=false — eliminates All Clear flash
        isLoading = false         // only now stop showing the loading indicator

        // Enrich top items with AI context (runs after feed is already visible)
        if claudeService.discoverAPIKey() != nil {
            await enrichFeedWithAI(items: &feed, appState: appState)
            feedItems = feed
        }
    }

    private func updateFirstAlertedTimestamps() {
        // JSM Ops alerts
        let hasJSMAlerts = jsmOpsAlerts.contains { $0.status.lowercased() == "open" && !$0.acknowledged }
        if hasJSMAlerts {
            if widgetFirstAlerted[.jsmOpsAlerts] == nil { widgetFirstAlerted[.jsmOpsAlerts] = Date() }
        } else {
            widgetFirstAlerted.removeValue(forKey: .jsmOpsAlerts)
        }
        // Grafana alerts
        if firingAlerts.isEmpty { widgetFirstAlerted.removeValue(forKey: .grafanaAlerts) }
        else if widgetFirstAlerted[.grafanaAlerts] == nil { widgetFirstAlerted[.grafanaAlerts] = Date() }
        // Jenkins failures
        let hasFailures = recentBuilds.contains { $0.build.result == "FAILURE" }
        if hasFailures { if widgetFirstAlerted[.jenkinsBuilds] == nil { widgetFirstAlerted[.jenkinsBuilds] = Date() } }
        else { widgetFirstAlerted.removeValue(forKey: .jenkinsBuilds) }
    }

    private func loadIncidents(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        do {
            var jql = "project = \"Boomi Incident Management\" AND statusCategory NOT IN (Done)"
            if !appState.useCustomIncidentJQL {
                if let p = appState.selectedProduct, !p.incidentProductElements.isEmpty {
                    let elements = p.incidentProductElements.map { "\"\($0)\"" }.joined(separator: ", ")
                    jql += " AND \"product element[select list (multiple choices)]\" IN (\(elements))"
                } else if !appState.favoriteProductElements.isEmpty {
                    let elements = appState.favoriteProductElements.map { "\"\($0)\"" }.joined(separator: ", ")
                    jql += " AND \"product element[select list (multiple choices)]\" IN (\(elements))"
                }
                jql += " ORDER BY created DESC"
            } else if !appState.customIncidentJQL.isEmpty {
                jql = appState.customIncidentJQL
            } else {
                jql += " ORDER BY created DESC"
            }
            let result = try await incidentJiraService.searchIssues(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: jql,
                fields: ["summary", "status", "priority", "created", "assignee"], maxResults: 10)
            activeIncidents = result.issues.compactMap { issue in
                let severity: IncidentSeverity = {
                    switch issue.fields.priority?.name.lowercased() ?? "" {
                    case "highest", "blocker": return .p1
                    case "high", "critical": return .p2
                    case "medium": return .p3
                    default: return .p4
                    }
                }()
                let status: IncidentStatus = {
                    switch issue.fields.status?.statusCategory?.key ?? "" {
                    case "done": return .resolved
                    case "indeterminate": return .identified
                    default: return .investigating
                    }
                }()
                return Incident(title: issue.fields.summary ?? issue.key,
                               severity: severity, status: status,
                               jiraTicketKey: issue.key)
            }
        } catch {
            loadErrors.append("Incidents: \(error.localizedDescription)")
        }
    }

    private func matchesAny(_ value: String, patterns: [String]) -> Bool {
        if patterns.isEmpty { return true }
        let lower = value.lowercased()
        return patterns.contains { pattern in
            let p = pattern.lowercased()
            if p.hasPrefix("*") && p.hasSuffix("*") {
                return lower.contains(String(p.dropFirst().dropLast()))
            } else if p.hasPrefix("*") {
                return lower.hasSuffix(String(p.dropFirst()))
            } else if p.hasSuffix("*") {
                return lower.hasPrefix(String(p.dropLast()))
            } else {
                return lower == p
            }
        }
    }

    private func loadOnCallForDashboard(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        do {
            let schedules = try await jsmOpsService.listSchedules(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken)
            onCallSchedules = schedules
            for teamId in appState.favoriteJSMTeams {
                let teamSchedules = schedules.filter { $0.teamId == teamId }
                for schedule in teamSchedules {
                    let participants = try await jsmOpsService.getOnCall(
                        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken, scheduleId: schedule.id)
                    onCallParticipants[schedule.id] = participants
                    for p in participants where onCallDisplayNames[p.name] == nil {
                        if let name = try? await jsmOpsService.resolveDisplayName(
                            accountId: p.name,
                            baseURL: appState.jiraBaseURL,
                            email: appState.jiraEmail,
                            apiToken: appState.jiraAPIToken) {
                            onCallDisplayNames[p.name] = name
                        }
                    }
                }
            }
        } catch {
            loadErrors.append("On-Call Dashboard: \(error.localizedDescription)")
        }
    }

    private func loadJSMOpsAlerts(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        do {
            let allAlerts = try await jsmOpsService.listAlerts(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                limit: 50
            )
            // Product context filter
            let productFilteredAlerts: [OpsAlert]
            if let p = appState.selectedProduct, !p.jsmTeamIds.isEmpty {
                productFilteredAlerts = allAlerts.filter { alert in
                    alert.responders.contains { r in p.jsmTeamIds.contains(r.id) }
                }
            } else {
                productFilteredAlerts = allAlerts
            }
            let userEmail = appState.jiraEmail.lowercased()
            let filtered = productFilteredAlerts.filter { alert in
                let isOpen = alert.status.lowercased() == "open"
                let isUnacked = isOpen && !alert.acknowledged
                let isAssignedToMe = !alert.owner.isEmpty && alert.owner.lowercased() == userEmail
                return isOpen || isUnacked || isAssignedToMe
            }
            // Sort by priority (P1 first), then newest first within same priority
            let priorityOrder = ["P1": 0, "P2": 1, "P3": 2, "P4": 3, "P5": 4]
            jsmOpsAlerts = filtered.sorted { a, b in
                let pa = priorityOrder[a.priority] ?? 5
                let pb = priorityOrder[b.priority] ?? 5
                if pa != pb { return pa < pb }
                return a.createdAt > b.createdAt
            }
        } catch {
            loadErrors.append("JSM Ops Alerts: \(error.localizedDescription)")
        }
    }

    private func loadJiraTickets(appState: AppState) async {
        do {
            var jql = "assignee = currentUser() AND statusCategory NOT IN (Done)"
            if let p = appState.selectedProduct, !p.jiraProjectKeys.isEmpty {
                let projectFilter = p.jiraProjectKeys.map { "\"\($0)\"" }.joined(separator: ", ")
                jql += " AND project IN (\(projectFilter))"
            }
            jql += " ORDER BY priority ASC, updated DESC"
            let result = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: jql,
                fields: ["summary", "status", "priority", "issuetype", "duedate"], maxResults: 20)
            myTickets = result.issues
        } catch { loadErrors.append("Jira: \(error.localizedDescription)") }
    }

    private func loadRecentPRs(token: String, appState: AppState) async {
        do {
            let favorites = appState.favoriteGitHubRepos
            var prs: [GitHubPR] = []
            if !favorites.isEmpty {
                var filteredFavorites = favorites
                if let p = appState.selectedProduct, !p.githubRepoPatterns.isEmpty {
                    filteredFavorites = favorites.filter { fullName in
                        let repoName = fullName.split(separator: "/").last.map(String.init) ?? fullName
                        return matchesAny(repoName, patterns: p.githubRepoPatterns)
                    }
                }
                for fullName in filteredFavorites.prefix(5) {
                    let parts = fullName.split(separator: "/").map(String.init)
                    guard parts.count == 2 else { continue }
                    let repoPRs = (try? await githubService.listPRs(owner: parts[0], repo: parts[1], token: token)) ?? []
                    prs.append(contentsOf: repoPRs.prefix(3))
                }
            } else {
                let orgs = appState.githubOrgs.isEmpty ? [appState.githubOrg] : appState.githubOrgs
                for org in orgs.prefix(2) {
                    var repos = (try? await githubService.listOrgRepos(org: org, token: token)) ?? []
                    if let p = appState.selectedProduct, !p.githubRepoPatterns.isEmpty {
                        repos = repos.filter { matchesAny($0.name, patterns: p.githubRepoPatterns) }
                    }
                    for repo in repos.prefix(5) {
                        let parts = repo.fullName.split(separator: "/").map(String.init)
                        guard parts.count == 2 else { continue }
                        let repoPRs = (try? await githubService.listPRs(owner: parts[0], repo: parts[1], token: token)) ?? []
                        prs.append(contentsOf: repoPRs.prefix(2))
                    }
                }
            }
            recentPRs = Array(prs.prefix(8))
        } catch { loadErrors.append("GitHub: \(error.localizedDescription)") }
    }

    private func loadJenkinsBuilds(baseURL: String, username: String, token: String, appState: AppState) async {
        do {
            let favorites = appState.favoriteJenkinsJobs
            let jobs = try await jenkinsService.listJobs(baseURL: baseURL, username: username, token: token)
            var targetJobs: [JenkinsJob]
            if !favorites.isEmpty {
                targetJobs = jobs.filter { favorites.contains($0.name) }
            } else if let p = appState.selectedProduct, !p.jenkinsJobPatterns.isEmpty {
                targetJobs = jobs.filter { matchesAny($0.name, patterns: p.jenkinsJobPatterns) }
            } else {
                targetJobs = Array(jobs.prefix(5))
            }
            var builds: [(String, JenkinsBuild)] = []
            for job in targetJobs.prefix(5) {
                if let latest = (try? await jenkinsService.getBuildHistory(
                    baseURL: baseURL, jobName: job.name, username: username, token: token, limit: 1))?.first {
                    builds.append((job.name, latest))
                }
            }
            recentBuilds = builds
        } catch { loadErrors.append("Jenkins: \(error.localizedDescription)") }
    }

    private func loadGrafanaAlerts(baseURL: String, token: String, appState: AppState) async {
        do {
            let rules = try await grafanaService.listAlertRules(baseURL: baseURL, token: token)
            var firing = rules.filter { $0.state.lowercased() == "alerting" }
            if let p = appState.selectedProduct, !p.grafanaDashboardTags.isEmpty {
                firing = firing.filter { rule in
                    p.grafanaDashboardTags.contains { tag in
                        rule.labels.keys.contains { $0.lowercased() == tag.lowercased() } ||
                        rule.labels.values.contains { $0.lowercased() == tag.lowercased() }
                    }
                }
            }
            firingAlerts = firing
        } catch { loadErrors.append("Grafana: \(error.localizedDescription)") }
    }

    private func loadCalendarEvents(credentials: GoogleCredentials) async {
        do {
            upcomingEvents = try await googleService.listEvents(credentials: credentials, maxResults: 5, daysAhead: 1)
        } catch { }
    }

    private func loadUnreadEmails(credentials: GoogleCredentials) async {
        do {
            unreadEmails = try await googleService.listMessages(credentials: credentials, query: "is:unread", maxResults: 5)
        } catch { }
    }

    // MARK: - Feed

    /// Build a unified feed from all data sources, sorted by priority then timestamp.
    func buildFeed(appState: AppState) -> [FeedItem] {
        var items: [FeedItem] = []

        // JSM Ops Alerts
        for alert in jsmOpsAlerts {
            let priority: FeedPriority = {
                if alert.priority == "P1" { return .critical }
                if alert.priority == "P2" || (alert.status == "open" && !alert.acknowledged) { return .high }
                return .medium
            }()
            let capturedAlertId = alert.id
            var actions: [FeedAction] = []
            if alert.status.lowercased() == "open" && !alert.acknowledged {
                actions.append(FeedAction(id: "ack-\(alert.id)", label: "ACK", icon: "checkmark.circle", style: .primary) { [weak self] in
                    guard let self = self else { return }
                    try? await self.jsmOpsService.acknowledgeAlert(
                        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken, alertId: capturedAlertId)
                    await self.refreshAll(appState: appState)
                })
            }
            if alert.status.lowercased() != "closed" {
                actions.append(FeedAction(id: "close-\(alert.id)", label: "Close", icon: "xmark.circle", style: .destructive) { [weak self] in
                    guard let self = self else { return }
                    try? await self.jsmOpsService.closeAlert(
                        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                        apiToken: appState.jiraAPIToken, alertId: capturedAlertId)
                    await self.refreshAll(appState: appState)
                })
            }
            items.append(FeedItem(
                id: "jsm-\(alert.id)",
                source: .jsmAlert,
                priority: priority,
                title: alert.message,
                subtitle: "\(alert.priority) · \(alert.source) · \(alert.status.capitalized)",
                detail: "",
                timestamp: parseISO8601(alert.createdAt) ?? Date(),
                actions: actions,
                navigateTo: "oncall",
                metadata: ["alertId": alert.id, "priority": alert.priority, "status": alert.status]
            ))
        }

        // Grafana Alerts
        for alert in firingAlerts {
            items.append(FeedItem(
                id: "grafana-\(alert.uid)",
                source: .grafanaAlert,
                priority: .high,
                title: alert.title,
                subtitle: "Grafana · \(alert.state)",
                detail: alert.summary,
                timestamp: Date(),
                actions: [
                    FeedAction(id: "view-grafana-\(alert.uid)", label: "View in Grafana",
                              icon: "safari", style: .secondary) { await MainActor.run {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "grafana_browser" }
                        appState.showSettings = false
                    } }
                ],
                navigateTo: "grafana_browser",
                metadata: ["uid": alert.uid]
            ))
        }

        // Active Incidents
        for incident in activeIncidents {
            let priority: FeedPriority = incident.severity == .p1 ? .critical : incident.severity == .p2 ? .high : .medium
            let capturedKey = incident.jiraTicketKey ?? ""
            items.append(FeedItem(
                id: "incident-\(incident.id.uuidString)",
                source: .incident,
                priority: priority,
                title: "[\(incident.severity.label)] \(incident.title)",
                subtitle: "\(incident.status.rawValue) · \(incident.elapsedString)",
                detail: "",
                timestamp: incident.createdAt,
                actions: [
                    FeedAction(id: "view-incident-\(incident.id.uuidString)", label: "View Incident",
                              icon: "exclamationmark.shield", style: .primary) { await MainActor.run {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "incidents" }
                        appState.showSettings = false
                    } }
                ],
                navigateTo: "incidents",
                metadata: ["ticketKey": capturedKey]
            ))
        }

        // Jira Tickets — only overdue or high priority
        for ticket in myTickets {
            let isOverdue: Bool = {
                guard let due = ticket.fields.duedate, !due.isEmpty else { return false }
                return due < String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            }()
            let priorityName = ticket.fields.priority?.name.lowercased() ?? ""
            let isHighPri = priorityName == "highest" || priorityName == "high"
            guard isOverdue || isHighPri else { continue }
            let capturedKey = ticket.key
            items.append(FeedItem(
                id: "jira-\(ticket.key)",
                source: .jiraTicket,
                priority: isOverdue ? .high : .medium,
                title: "\(ticket.key) \(ticket.fields.summary ?? "")",
                subtitle: "\(ticket.fields.status?.name ?? "") · \(ticket.fields.priority?.name ?? "")\(isOverdue ? " · OVERDUE" : "")",
                detail: "",
                timestamp: parseISO8601(ticket.fields.updated ?? "") ?? Date(),
                actions: [
                    FeedAction(id: "view-ticket-\(ticket.key)", label: "Open Ticket",
                              icon: "ticket", style: .secondary) { await MainActor.run { appState.selectedTicketKey = capturedKey } }
                ],
                navigateTo: "jira_todo",
                metadata: ["ticketKey": capturedKey]
            ))
        }

        // Jenkins Failures
        for (jobName, build) in recentBuilds where build.result == "FAILURE" {
            items.append(FeedItem(
                id: "jenkins-\(jobName)-\(build.number)",
                source: .jenkinsBuild,
                priority: .high,
                title: "Build failed: \(jobName) #\(build.number)",
                subtitle: "Jenkins · \(build.result ?? "FAILURE")",
                detail: "",
                timestamp: Date(timeIntervalSince1970: build.timestampMs / 1000),
                actions: [
                    FeedAction(id: "view-jenkins-\(jobName)", label: "View Build",
                              icon: "hammer", style: .secondary) { await MainActor.run {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "jenkins_browser" }
                        appState.showSettings = false
                    } }
                ],
                navigateTo: "jenkins_browser",
                metadata: ["jobName": jobName, "buildNumber": String(build.number)]
            ))
        }

        // GitHub PRs
        for pr in recentPRs {
            items.append(FeedItem(
                id: "pr-\(pr.id)",
                source: .githubPR,
                priority: .medium,
                title: "PR #\(pr.number): \(pr.title)",
                subtitle: "@\(pr.authorLogin) · \(pr.headBranch) → \(pr.baseBranch)",
                detail: "",
                timestamp: parseISO8601(pr.updatedAt) ?? Date(),
                actions: [
                    FeedAction(id: "view-pr-\(pr.id)", label: "View PR",
                              icon: "arrow.triangle.pull", style: .secondary) { await MainActor.run {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "github_browser" }
                        appState.showSettings = false
                    } }
                ],
                navigateTo: "github_browser",
                metadata: ["prNumber": String(pr.number)]
            ))
        }

        // On-Call Status
        if !onCallSchedules.isEmpty {
            let summaryParts = onCallSchedules.prefix(3).compactMap { schedule -> String? in
                guard let participants = onCallParticipants[schedule.id],
                      let primary = participants.first else { return nil }
                let name = onCallDisplayNames[primary.name] ?? primary.name
                return "\(schedule.name): \(name)"
            }
            items.append(FeedItem(
                id: "oncall-status",
                source: .onCall,
                priority: .low,
                title: "On-Call",
                subtitle: summaryParts.joined(separator: " · "),
                detail: "",
                timestamp: Date(),
                actions: [
                    FeedAction(id: "view-oncall", label: "View Schedules",
                              icon: "phone.badge.waveform", style: .secondary) { await MainActor.run {
                        appState.selectedReport = ReportCatalog.all.first { $0.id == "oncall" }
                        appState.showSettings = false
                    } }
                ],
                navigateTo: "oncall",
                metadata: [:]
            ))
        }

        // AI Daily Summary
        if let summary = aiSummary {
            let relFormatter = RelativeDateTimeFormatter()
            let subtitleStr = aiSummaryDate.map {
                "Generated \(relFormatter.localizedString(for: $0, relativeTo: Date()))"
            } ?? ""
            items.append(FeedItem(
                id: "ai-summary",
                source: .aiSummary,
                priority: .info,
                title: "AI Daily Brief",
                subtitle: subtitleStr,
                detail: summary,
                timestamp: aiSummaryDate ?? Date(),
                actions: [],
                navigateTo: nil,
                metadata: [:]
            ))
        }

        // Sort: priority first, then newest first within same priority
        items.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.timestamp > b.timestamp
        }

        return items
    }

    private func parseISO8601(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Enrich top feed items with one-sentence AI context.
    func enrichFeedWithAI(items: inout [FeedItem], appState: AppState) async {
        guard claudeService.discoverAPIKey() != nil else { return }
        let topItems = items.prefix(5).filter { $0.priority <= .high && $0.detail.isEmpty }
        guard !topItems.isEmpty else { return }

        let context = topItems.map { "- [\($0.source.rawValue)] \($0.title): \($0.subtitle)" }.joined(separator: "\n")
        let prompt = """
        For each of the following SRE items, provide ONE sentence of actionable context (what to check first, what it likely means, or what to do):
        \(context)
        Respond with one line per item, in the same order. Be specific and concise.
        """

        if let response = try? await claudeService.chat(
            messages: [("user", prompt)],
            systemPrompt: "You are an SRE assistant. Give one-sentence actionable advice per item.",
            maxTokens: 300
        ) {
            let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
            for (i, line) in lines.enumerated() where i < topItems.count {
                if let idx = items.firstIndex(where: { $0.id == topItems[i].id }) {
                    let old = items[idx]
                    items[idx] = FeedItem(
                        id: old.id, source: old.source, priority: old.priority,
                        title: old.title, subtitle: old.subtitle,
                        detail: line.trimmingCharacters(in: .whitespacesAndNewlines),
                        timestamp: old.timestamp, actions: old.actions,
                        navigateTo: old.navigateTo, metadata: old.metadata
                    )
                }
            }
        }
    }

    func loadProductKnowledge(product: ProductContext, appState: AppState) async {
        guard !product.kbTags.isEmpty || !product.keyRunbooks.isEmpty else { return }
        guard !appState.githubToken.isEmpty else { return }
        let kbService = KnowledgeBaseService()
        do {
            let allArticles = try await kbService.fetchArticles(
                owner: appState.kbRepoOwner,
                repo: appState.kbRepoName,
                token: appState.githubToken
            )
            let relevant = allArticles.filter { article in
                // Match by tag in path or title
                let pathLower = article.path.lowercased()
                let titleLower = article.title.lowercased()
                let matchesTag = product.kbTags.contains { tag in
                    pathLower.contains(tag.lowercased()) || titleLower.contains(tag.lowercased())
                }
                // Match by keyRunbook paths
                let matchesRunbook = product.keyRunbooks.contains { rb in
                    pathLower.contains(rb.lowercased()) || rb.lowercased().contains(pathLower)
                }
                return matchesTag || matchesRunbook
            }
            productRelevantArticles = Array(relevant.prefix(6))
        } catch {
            // KB fetch is non-critical, fail silently
        }
    }

    func generateAISummary(appState: AppState) async {
        guard claudeService.discoverAPIKey() != nil else { return }
        let ticketCount   = myTickets.count
        let incidentCount = activeIncidents.count
        let alertCount    = firingAlerts.count
        let failedBuilds  = recentBuilds.filter { $0.1.result == "FAILURE" }.count
        let openPRs       = recentPRs.count

        let prompt = """
        Generate a 3-5 sentence SRE daily status summary for Boomi's APIM SRE team based on:
        - Active incidents: \(incidentCount) (\(activeIncidents.filter { $0.severity == .p1 }.count) P1, \(activeIncidents.filter { $0.severity == .p2 }.count) P2)
        - Open Jira tickets assigned to me: \(ticketCount)
        - Grafana alerts currently firing: \(alertCount)
        - Recent Jenkins build failures: \(failedBuilds)
        - Open PRs: \(openPRs)
        Be direct and actionable. Start with the most critical item. End with a recommendation for what to focus on first.
        """
        do {
            aiSummary = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an SRE status summarizer. Be concise, specific, and action-oriented." + (appState.userProfile.experienceLevel.analysisDepthHint.isEmpty ? "" : "\n\n" + appState.userProfile.experienceLevel.analysisDepthHint),
                maxTokens: 512)
            aiSummaryDate = Date()
        } catch { }
        if aiSummary != nil { ProductivityTracker.shared.log(.aiDailySummary, source: "Dashboard") }
    }
}

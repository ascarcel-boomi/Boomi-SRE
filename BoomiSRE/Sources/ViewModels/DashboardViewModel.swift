import Foundation
import SwiftUI

@Observable
@MainActor
final class DashboardViewModel {
    var myTickets: [JiraIssue] = []
    var recentPRs: [GitHubPR] = []
    var recentBuilds: [(jobName: String, build: JenkinsBuild)] = []
    var firingAlerts: [GrafanaAlertRule] = []
    var jsmOpsAlerts: [OpsAlert] = []
    var recentNotifications: [SRENotification] = []
    var onCallSchedules: [OpsSchedule] = []
    var onCallParticipants: [String: [OnCallParticipant]] = [:]
    var onCallDisplayNames: [String: String] = [:]
    var upcomingEvents: [CalendarEvent] = []
    var unreadEmails: [GmailMessage] = []
    var activeIncidents: [Incident] = []
    var feedItems: [FeedItem] = []
    var productRelevantArticles: [KnowledgeBaseService.KBArticle] = []
    var sloHealthy = 0
    var sloWarning = 0
    var sloCritical = 0
    var sloTotal = 0
    var aiSummary: String?
    var aiSummaryDate: Date?
    var isGeneratingAI = false
    var costTrendTotal: Double = 0
    var costTrendPrevious: Double = 0
    var costTrendProfile: String = ""
    var recentConfluencePages: [(title: String, spaceKey: String, url: String)] = []
    var isLoading = false
    var lastRefreshedAt: Date?
    var loadErrors: [String] = []
    var widgetFirstAlerted: [WidgetType: Date] = [:]

    @ObservationIgnored private let jiraService    = JiraService()
    @ObservationIgnored private let costService = AWSCostService()
    @ObservationIgnored private let confluenceService = ConfluenceService()
    @ObservationIgnored private let githubService  = GitHubService()
    @ObservationIgnored private let jenkinsService = JenkinsService()
    @ObservationIgnored private let grafanaService = GrafanaService()
    @ObservationIgnored private let googleService  = GoogleService()
    @ObservationIgnored private let claudeService  = ClaudeService()
    @ObservationIgnored private let jsmOpsService = JSMOpsService()
    @ObservationIgnored private let incidentJiraService = JiraService()

    // MARK: - Cache TTL

    @ObservationIgnored private let cacheTTL: TimeInterval = 120  // 2 minutes

    var isCacheValid: Bool {
        guard let lastRefresh = lastRefreshedAt else { return false }
        return Date().timeIntervalSince(lastRefresh) < cacheTTL
    }

    func refreshAll(appState: AppState, notificationVM: NotificationViewModel? = nil, force: Bool = false) async {
        guard !isCacheValid || force else { return }
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
                group.addTask { await self.loadSLOHealth(appState: appState) }
            }
            if let creds = googleCreds {
                group.addTask { await self.loadCalendarEvents(credentials: creds) }
                group.addTask { await self.loadUnreadEmails(credentials: creds) }
            }
            if !appState.awsSSOProfile.isEmpty {
                group.addTask { await self.loadCostTrend(appState: appState) }
            }
            if jiraOK && !appState.confluenceAPIToken.isEmpty {
                group.addTask { await self.loadRecentConfluencePages(appState: appState) }
            }
            for await _ in group {}
        }

        // AI summary: no longer auto-generated — user must click the refresh button on the widget

        // Track first-alert timestamps for time-based urgency escalation (Phase 37F)
        updateFirstAlertedTimestamps()

        // Build feed first (without enrichment) so UI transitions directly from skeleton → feed,
        // never passing through "All Clear". isLoading stays true until feed is ready.
        var feed = buildFeed(appState: appState)
        feedItems = feed          // populate before isLoading=false — eliminates All Clear flash
        isLoading = false         // only now stop showing the loading indicator
        lastRefreshedAt = Date()

        // Enrich top items with AI context (runs after feed is already visible)
        if claudeService.isAIAvailable {
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
            let effectiveTeamIds = appState.activeJSMTeamIds.isEmpty
                ? appState.favoriteJSMTeams
                : appState.activeJSMTeamIds
            for teamId in effectiveTeamIds {
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
                } else if appState.selectedProduct != nil {
                    // Product selected but no GitHub repo patterns — show nothing
                    filteredFavorites = []
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
                    } else if appState.selectedProduct != nil {
                        repos = []
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
        }
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
            } else if appState.selectedProduct != nil {
                // Product selected but no Jenkins mappings — show nothing
                targetJobs = []
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
            } else if appState.selectedProduct != nil {
                // Product selected but no Grafana tags — show nothing
                firing = []
            }
            firingAlerts = firing
        } catch { loadErrors.append("Grafana: \(error.localizedDescription)") }
    }

    private func loadSLOHealth(appState: AppState) async {
        let definitions = appState.sloDefinitions.filter { $0.enabled }
        guard !definitions.isEmpty, !appState.prometheusDataSourceUID.isEmpty else { return }
        var healthy = 0, warning = 0, critical = 0
        for def in definitions {
            guard !def.metricQuery.isEmpty else { continue }
            do {
                let result = try await grafanaService.queryPrometheus(
                    query: def.metricQuery,
                    datasourceUID: appState.prometheusDataSourceUID,
                    baseURL: appState.grafanaURL,
                    token: appState.grafanaToken,
                    windowDays: def.windowDays)
                if let sli = result.value, result.error == nil {
                    let budget = 1.0 - def.target
                    let consumed = max(0, 1.0 - sli)
                    let remaining = budget > 0 ? max(0, ((budget - consumed) / budget) * 100) : (sli >= def.target ? 100 : 0)
                    if sli < def.target || remaining < 10 { critical += 1 }
                    else if remaining < 50 { warning += 1 }
                    else { healthy += 1 }
                } else { critical += 1 }
            } catch { critical += 1 }
        }
        sloHealthy = healthy
        sloWarning = warning
        sloCritical = critical
        sloTotal = definitions.count
    }

    private func loadCalendarEvents(credentials: GoogleCredentials) async {
        do {
            upcomingEvents = try await googleService.listEvents(credentials: credentials, maxResults: 5, daysAhead: 1)
        } catch {
            loadErrors.append("Calendar: \(error.localizedDescription)")
        }
    }

    private func loadUnreadEmails(credentials: GoogleCredentials) async {
        do {
            unreadEmails = try await googleService.listMessages(credentials: credentials, query: "is:unread", maxResults: 5)
        } catch {
            loadErrors.append("Gmail: \(error.localizedDescription)")
        }
    }

    // MARK: - AWS Cost Trend

    private func loadCostTrend(appState: AppState) async {
        let profile = appState.awsSSOProfile
        guard !profile.isEmpty else { return }
        costTrendProfile = profile
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let cal = Calendar.current
        let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart)!
        do {
            let thisMonth = try await costService.getTotalCost(
                profile: profile, startDate: fmt.string(from: thisMonthStart),
                endDate: fmt.string(from: now), granularity: .monthly)
            costTrendTotal = thisMonth.reduce(0) { $0 + $1.amount }
            let lastMonth = try await costService.getTotalCost(
                profile: profile, startDate: fmt.string(from: lastMonthStart),
                endDate: fmt.string(from: thisMonthStart), granularity: .monthly)
            costTrendPrevious = lastMonth.reduce(0) { $0 + $1.amount }
        } catch {
            loadErrors.append("AWS Cost: \(error.localizedDescription)")
        }
    }

    // MARK: - Confluence Recent Pages

    private func loadRecentConfluencePages(appState: AppState) async {
        let token = appState.confluenceAPIToken
        guard !token.isEmpty else { return }
        do {
            let pages = try await confluenceService.recentlyModifiedPages(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: token, limit: 5)
            recentConfluencePages = pages.map { (title: $0.title, spaceKey: $0.spaceKey, url: $0.url) }
        } catch {
            loadErrors.append("Confluence: \(error.localizedDescription)")
        }
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
            let alertTitle = alert.title
            items.append(FeedItem(
                id: "grafana-\(alert.uid)",
                source: .grafanaAlert,
                priority: .high,
                title: alert.title,
                subtitle: "Grafana · \(alert.state)",
                detail: alert.summary,
                timestamp: Date(),
                actions: [
                    FeedAction(id: "investigate-grafana-\(alert.uid)", label: "Investigate",
                              icon: "wrench.and.screwdriver", style: .primary) { await MainActor.run {
                        appState.pendingCopilotPrompt = "Troubleshoot this Grafana alert: \"\(alertTitle)\"\n\nCheck for related Jira tickets, recent Jenkins deploys, and relevant Confluence runbooks. What's the likely cause and what should I do first?"
                        appState.navigate(to: "copilot_chat")
                    } },
                    FeedAction(id: "view-grafana-\(alert.uid)", label: "View",
                              icon: "safari", style: .secondary) { await MainActor.run {
                        appState.navigate(to: "grafana_browser")
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
            let capturedTitle = incident.title
            let capturedSeverity = incident.severity.label
            items.append(FeedItem(
                id: "incident-\(incident.id.uuidString)",
                source: .incident,
                priority: priority,
                title: "[\(incident.severity.label)] \(incident.title)",
                subtitle: "\(incident.status.rawValue) · \(incident.elapsedString)",
                detail: "",
                timestamp: incident.createdAt,
                actions: [
                    FeedAction(id: "investigate-incident-\(incident.id.uuidString)", label: "Investigate",
                              icon: "wrench.and.screwdriver", style: .primary) { await MainActor.run {
                        let ticketRef = capturedKey.isEmpty ? "" : " (Jira: \(capturedKey))"
                        appState.pendingCopilotPrompt = "I'm responding to a \(capturedSeverity) incident: \"\(capturedTitle)\"\(ticketRef)\n\nFetch the ticket details, check for related Grafana alerts, recent Jenkins deploys, and search for relevant runbooks. Give me a full situation report: root cause hypothesis, blast radius, and immediate action plan."
                        appState.navigate(to: "copilot_chat")
                    } },
                    FeedAction(id: "view-incident-\(incident.id.uuidString)", label: "View",
                              icon: "exclamationmark.shield", style: .secondary) { await MainActor.run {
                        if !capturedKey.isEmpty {
                            appState.pushNavigation()
                            appState.selectedTicketKey = capturedKey
                        } else {
                            appState.navigate(to: "incidents")
                        }
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
                              icon: "ticket", style: .secondary) { await MainActor.run { appState.pushNavigation(); appState.selectedTicketKey = capturedKey } }
                ],
                navigateTo: "jira_todo",
                metadata: ["ticketKey": capturedKey]
            ))
        }

        // Jenkins Failures
        for (jobName, build) in recentBuilds where build.result == "FAILURE" {
            let capturedJobName = jobName
            let capturedBuildNum = build.number
            items.append(FeedItem(
                id: "jenkins-\(jobName)-\(build.number)",
                source: .jenkinsBuild,
                priority: .high,
                title: "Build failed: \(jobName) #\(build.number)",
                subtitle: "Jenkins · \(build.result ?? "FAILURE")",
                detail: "",
                timestamp: Date(timeIntervalSince1970: build.timestampMs / 1000),
                actions: [
                    FeedAction(id: "investigate-jenkins-\(jobName)", label: "Investigate",
                              icon: "wrench.and.screwdriver", style: .primary) { await MainActor.run {
                        appState.pendingCopilotPrompt = "Jenkins build failed: \(capturedJobName) #\(capturedBuildNum)\n\nCheck the build logs, look for related Jira tickets, and search for relevant runbooks. What likely broke and what should I do?"
                        appState.navigate(to: "copilot_chat")
                    } },
                    FeedAction(id: "view-jenkins-\(jobName)", label: "View",
                              icon: "hammer", style: .secondary) { await MainActor.run {
                        appState.navigate(to: "jenkins_browser")
                    } }
                ],
                navigateTo: "jenkins_browser",
                metadata: ["jobName": jobName, "buildNumber": String(build.number)]
            ))
        }

        // GitHub PRs
        for pr in recentPRs {
            let prURL = pr.htmlURL
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
                        if let url = URL(string: prURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } }
                ],
                navigateTo: "github_browser",
                metadata: ["prNumber": String(pr.number), "prURL": prURL]
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

        // SLO Health Summary
        if sloTotal > 0 {
            let sloPriority: FeedPriority = sloCritical > 0 ? .high : sloWarning > 0 ? .medium : .low
            items.append(FeedItem(
                id: "slo-health",
                source: .grafanaAlert,
                priority: sloPriority,
                title: "SLOs: \(sloHealthy) healthy, \(sloWarning) warning, \(sloCritical) critical",
                subtitle: "\(sloTotal) SLOs monitored",
                detail: sloCritical > 0 ? "\(sloCritical) SLO(s) breaching target — check error budgets" : "",
                timestamp: Date(),
                actions: [
                    FeedAction(id: "view-slos", label: "View SLOs",
                              icon: "chart.bar.xaxis", style: sloCritical > 0 ? .primary : .secondary) { await MainActor.run {
                        appState.navigate(to: "slo_dashboard")
                    } }
                ],
                navigateTo: "slo_dashboard",
                metadata: ["healthy": String(sloHealthy), "warning": String(sloWarning), "critical": String(sloCritical)]
            ))
        }

        // BPOP summary feed item
        let bpopMetrics = BPOPMetric.allMetrics
        let onTrack = bpopMetrics.filter { $0.status == .onTrack }.count
        let bpopTotal = bpopMetrics.count
        items.append(FeedItem(
            id: "bpop-summary",
            source: .aiSummary,
            priority: .info,
            title: "BPOP: \(onTrack)/\(bpopTotal) metrics on track",
            subtitle: "FY27 Plan on a Page — click to view full dashboard",
            detail: "",
            timestamp: Date(),
            actions: [
                FeedAction(id: "view-bpop", label: "View BPOP", icon: "target", style: .secondary) {
                    await MainActor.run {
                        appState.showSettings = true
                        appState.selectedSettingsTab = "productivity"
                    }
                }
            ],
            navigateTo: nil,
            metadata: [:]
        ))

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

        // Cross-service correlation: scan feed items for Jira ticket keys
        // and enrich with cross-references
        items = correlateServices(items: items)

        // Sort: priority first, then newest first within same priority
        items.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.timestamp > b.timestamp
        }

        return items
    }

    /// Scan feed items for Jira ticket keys and cross-reference with other services.
    /// e.g. a Jenkins failure whose job name contains "CAMSRE-123" gets annotated with the ticket summary.
    private func correlateServices(items: [FeedItem]) -> [FeedItem] {
        // Build lookup: ticket key → summary
        let ticketLookup = Dictionary(uniqueKeysWithValues:
            myTickets.map { ($0.key.uppercased(), $0.fields.summary ?? $0.key) })
        let regex = try? NSRegularExpression(pattern: "[A-Z][A-Z0-9]+-\\d+")

        // Build reverse lookup: which ticket keys appear in which non-Jira feed items
        var ticketToSources: [String: [String]] = [:]  // ticketKey → [source descriptions]
        var itemTicketRefs: [String: Set<String>] = [:] // itemId → [ticketKeys found]

        for item in items where item.source != .jiraTicket {
            let searchText = "\(item.title) \(item.subtitle) \(item.detail)"
            let range = NSRange(searchText.startIndex..., in: searchText)
            var foundKeys = Set<String>()
            for match in regex?.matches(in: searchText, range: range) ?? [] {
                if let r = Range(match.range, in: searchText) {
                    foundKeys.insert(String(searchText[r]).uppercased())
                }
            }
            if !foundKeys.isEmpty {
                itemTicketRefs[item.id] = foundKeys
                for key in foundKeys {
                    ticketToSources[key, default: []].append(item.source.rawValue)
                }
            }
        }

        // Enrich items with cross-references
        return items.map { item in
            var enrichedDetail = item.detail

            // For non-Jira items: add ticket summaries
            if let refs = itemTicketRefs[item.id], !refs.isEmpty {
                let ticketHints = refs.compactMap { key -> String? in
                    guard let summary = ticketLookup[key] else { return nil }
                    return "\(key): \(summary)"
                }
                if !ticketHints.isEmpty {
                    let prefix = enrichedDetail.isEmpty ? "" : "\(enrichedDetail)\n"
                    enrichedDetail = "\(prefix)Related tickets: \(ticketHints.joined(separator: "; "))"
                }
            }

            // For Jira ticket items: add cross-service context
            if item.source == .jiraTicket, let key = item.metadata["ticketKey"] {
                let sources = ticketToSources[key.uppercased()] ?? []
                if !sources.isEmpty {
                    let unique = Array(Set(sources))
                    let prefix = enrichedDetail.isEmpty ? "" : "\(enrichedDetail)\n"
                    enrichedDetail = "\(prefix)Also in: \(unique.joined(separator: ", "))"
                }
            }

            guard enrichedDetail != item.detail else { return item }
            return FeedItem(
                id: item.id, source: item.source, priority: item.priority,
                title: item.title, subtitle: item.subtitle,
                detail: enrichedDetail,
                timestamp: item.timestamp, actions: item.actions,
                navigateTo: item.navigateTo, metadata: item.metadata
            )
        }
    }

    private func parseISO8601(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Enrich top feed items with one-sentence AI context.
    func enrichFeedWithAI(items: inout [FeedItem], appState: AppState) async {
        guard claudeService.isAIAvailable else { return }
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
        guard claudeService.isAIAvailable, !isGeneratingAI else { return }
        isGeneratingAI = true
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
        } catch {
            loadErrors.append("AI Summary: \(error.localizedDescription)")
        }
        isGeneratingAI = false
        if aiSummary != nil { ProductivityTracker.shared.log(.aiDailySummary, source: "Dashboard") }
    }
}

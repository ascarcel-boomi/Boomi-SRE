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
                group.addTask { await self.loadRecentPRs(token: ghToken, favorites: appState.favoriteGitHubRepos) }
            }
            if !jkToken.isEmpty && !jkURL.isEmpty {
                group.addTask { await self.loadJenkinsBuilds(baseURL: jkURL, username: jkUser, token: jkToken, favorites: appState.favoriteJenkinsJobs) }
            }
            if !gfToken.isEmpty && !gfURL.isEmpty {
                group.addTask { await self.loadGrafanaAlerts(baseURL: gfURL, token: gfToken) }
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

        isLoading = false
        // Track first-alert timestamps for time-based urgency escalation (Phase 37F)
        updateFirstAlertedTimestamps()
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
            let jql = appState.customIncidentJQL.isEmpty
                ? "project = \"Boomi Incident Management\" AND statusCategory NOT IN (Done) ORDER BY created DESC"
                : appState.customIncidentJQL
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
            let userEmail = appState.jiraEmail.lowercased()
            let filtered = allAlerts.filter { alert in
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
            let result = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: "assignee = currentUser() AND statusCategory NOT IN (Done) ORDER BY priority ASC, updated DESC",
                fields: ["summary", "status", "priority", "issuetype", "duedate"], maxResults: 20)
            myTickets = result.issues
        } catch { loadErrors.append("Jira: \(error.localizedDescription)") }
    }

    private func loadRecentPRs(token: String, favorites: [String]) async {
        do {
            var prs: [GitHubPR] = []
            if !favorites.isEmpty {
                for fullName in favorites.prefix(5) {
                    let parts = fullName.split(separator: "/").map(String.init)
                    guard parts.count == 2 else { continue }
                    let repoPRs = (try? await githubService.listPRs(owner: parts[0], repo: parts[1], token: token)) ?? []
                    prs.append(contentsOf: repoPRs.prefix(3))
                }
            } else {
                let repos = (try? await githubService.listOrgRepos(org: "Mashery-Boomi", token: token)) ?? []
                for repo in repos.prefix(5) {
                    let parts = repo.fullName.split(separator: "/").map(String.init)
                    guard parts.count == 2 else { continue }
                    let repoPRs = (try? await githubService.listPRs(owner: parts[0], repo: parts[1], token: token)) ?? []
                    prs.append(contentsOf: repoPRs.prefix(2))
                }
            }
            recentPRs = Array(prs.prefix(8))
        } catch { loadErrors.append("GitHub: \(error.localizedDescription)") }
    }

    private func loadJenkinsBuilds(baseURL: String, username: String, token: String, favorites: [String]) async {
        do {
            let jobs = try await jenkinsService.listJobs(baseURL: baseURL, username: username, token: token)
            let targetJobs = favorites.isEmpty ? Array(jobs.prefix(5)) : jobs.filter { favorites.contains($0.name) }
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

    private func loadGrafanaAlerts(baseURL: String, token: String) async {
        do {
            let rules = try await grafanaService.listAlertRules(baseURL: baseURL, token: token)
            firingAlerts = rules.filter { $0.state.lowercased() == "alerting" }
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
    }
}

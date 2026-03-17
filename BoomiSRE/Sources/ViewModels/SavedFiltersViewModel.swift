import Foundation
import SwiftUI

/// ViewModel for the Saved Filters panel.
@MainActor
final class SavedFiltersViewModel: ObservableObject {
    @Published var filters: [JiraFilter] = []
    @Published var selectedFilter: JiraFilter?
    @Published var filterResults: JiraSearchResult?
    @Published var isLoadingFilters = false
    @Published var isLoadingResults = false
    @Published var error: String?

    private let jiraService   = JiraService()
    private let claudeService = ClaudeService()

    // MARK: - AI Analysis
    @Published var filterAnalysis: String?
    @Published var isAnalyzingFilter = false
    @Published var filterAnalysisError: String?

    func explainResults(appState: AppState) async {
        guard let results = filterResults, !results.issues.isEmpty,
              let filter = selectedFilter else { return }
        guard claudeService.isAIAvailable else {
            filterAnalysisError = "No Anthropic API key configured."; return
        }
        isAnalyzingFilter = true; filterAnalysisError = nil; filterAnalysis = nil

        let byStatus   = Dictionary(grouping: results.issues, by: { $0.fields.status?.name   ?? "Unknown" })
        let byPriority = Dictionary(grouping: results.issues, by: { $0.fields.priority?.name ?? "Unknown" })
        let byType     = Dictionary(grouping: results.issues, by: { $0.fields.issuetype?.name ?? "Unknown" })

        let sampleLines = results.issues.prefix(25).map { issue in
            let status   = issue.fields.status?.name   ?? "?"
            let priority = issue.fields.priority?.name ?? "?"
            let type_    = issue.fields.issuetype?.name ?? "?"
            return "  • [\(issue.key)] [\(priority)] [\(status)] \(type_): \(issue.fields.summary ?? "")"
        }.joined(separator: "\n")

        let prompt = """
        Analyze the results of this Jira filter for Boomi's APIM SRE team.

        Filter: "\(filter.name)"
        JQL: \(filter.jql)
        Total Issues: \(results.issues.count)

        BREAKDOWN:
        By Status: \(byStatus.map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: ", "))
        By Priority: \(byPriority.map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: ", "))
        By Type: \(byType.map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: ", "))

        SAMPLE ISSUES (first 25):
        \(sampleLines)

        Provide:
        1. **Pattern Detection** — what patterns do you see? Common themes, teams, or components?
        2. **Priority Assessment** — is the priority distribution appropriate? Any mis-prioritized items?
        3. **Trend Signals** — what does this filter tell you about the team's current state?
        4. **Recommendations** — 2–3 specific actions the team should take based on these results

        Reference specific ticket keys where notable. Under 350 words.
        """
        do {
            filterAnalysis = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an SRE team lead analyzing Jira filter results. Be specific, pattern-focused, and actionable." + (appState.userProfile.experienceLevel.analysisDepthHint.isEmpty ? "" : "\n\n" + appState.userProfile.experienceLevel.analysisDepthHint),
                maxTokens: 2048
            )
        } catch { filterAnalysisError = error.localizedDescription }
        isAnalyzingFilter = false
    }

    func loadFilters(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira is not configured."
            return
        }

        isLoadingFilters = true
        error = nil
        do {
            filters = try await jiraService.fetchFavouriteFilters(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken
            )
            isLoadingFilters = false
        } catch {
            self.error = error.localizedDescription
            isLoadingFilters = false
        }
    }

    func runFilter(_ filter: JiraFilter, appState: AppState) async {
        selectedFilter = filter
        isLoadingResults = true
        error = nil
        filterResults = nil

        do {
            filterResults = try await jiraService.searchIssues(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken,
                jql: filter.jql,
                fields: ["summary", "status", "priority", "issuetype",
                         "duedate", "labels", "created", "updated", "assignee"],
                maxResults: 100
            )
            isLoadingResults = false
        } catch {
            self.error = error.localizedDescription
            isLoadingResults = false
        }
    }

    /// Auto-detect chart sections from filter results.
    var chartSections: [ResultSection] {
        guard let results = filterResults else { return [] }
        var sections: [ResultSection] = []

        // Status distribution
        let byStatus = Dictionary(grouping: results.issues, by: { $0.fields.status?.name ?? "Unknown" })
        if byStatus.count > 1 {
            let rows = byStatus.map { ResultRow(label: $0.key, value: Double($0.value.count)) }
                .sorted { $0.value > $1.value }
            sections.append(ResultSection(title: "By Status", rows: rows, chartHint: .pie))
        }

        // Priority distribution
        let byPriority = Dictionary(grouping: results.issues, by: { $0.fields.priority?.name ?? "None" })
        if byPriority.count > 1 {
            let rows = byPriority.map { ResultRow(label: $0.key, value: Double($0.value.count)) }
                .sorted { $0.value > $1.value }
            sections.append(ResultSection(title: "By Priority", rows: rows, chartHint: .bar))
        }

        // Issue type distribution
        let byType = Dictionary(grouping: results.issues, by: { $0.fields.issuetype?.name ?? "Unknown" })
        if byType.count > 1 {
            let rows = byType.map { ResultRow(label: $0.key, value: Double($0.value.count)) }
                .sorted { $0.value > $1.value }
            sections.append(ResultSection(title: "By Issue Type", rows: rows, chartHint: .pie))
        }

        return sections
    }
}

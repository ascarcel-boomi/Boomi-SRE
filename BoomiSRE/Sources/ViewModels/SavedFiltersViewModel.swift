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

    private let jiraService = JiraService()

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
                         "duedate", "labels", "created", "updated"],
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

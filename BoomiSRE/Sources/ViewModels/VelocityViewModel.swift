import Foundation
import SwiftUI

@MainActor
final class VelocityViewModel: ObservableObject {

    // MARK: - Nested Types

    struct SprintVelocity: Identifiable {
        let id: Int           // sprint id
        let name: String
        let committed: Double
        let completed: Double
        let startDate: String?
        let endDate: String?

        var completionRate: Double {
            guard committed > 0 else { return 0 }
            return completed / committed
        }
    }

    struct EpicProgress: Identifiable {
        let id: String        // epic key
        let name: String
        let totalPoints: Double
        let completedPoints: Double

        var progressPercent: Double {
            guard totalPoints > 0 else { return 0 }
            return completedPoints / totalPoints
        }
    }

    // MARK: - Published

    @Published var sprints: [SprintVelocity] = []
    @Published var epics: [EpicProgress] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedBoardName: String = ""

    private let jiraService = JiraService()

    // MARK: - Load

    func loadVelocity(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira is not configured."
            return
        }
        isLoading = true
        error = nil

        let baseURL  = appState.jiraBaseURL
        let email    = appState.jiraEmail
        let token    = appState.jiraAPIToken
        let projects = appState.jiraProjectKeys

        do {
            // Find the first board for any configured project
            var boardId: Int?
            var boardName = ""
            for projectKey in projects where !projectKey.isEmpty {
                let boards = try await jiraService.listBoards(
                    baseURL: baseURL, email: email, apiToken: token, projectKey: projectKey)
                if let first = boards.first {
                    boardId = first.id
                    boardName = first.name
                    break
                }
            }
            guard let bId = boardId else {
                error = "No Jira boards found for configured projects."
                isLoading = false
                return
            }
            selectedBoardName = boardName

            // Fetch recent sprints (active + closed)
            let jiraSprints = try await jiraService.listSprints(
                baseURL: baseURL, email: email, apiToken: token, boardId: bId)

            // For each sprint, fetch issues and calculate velocity
            var velocities: [SprintVelocity] = []
            for sprint in jiraSprints.suffix(8) {  // last 8 sprints
                let issues = try await jiraService.listSprintIssues(
                    baseURL: baseURL, email: email, apiToken: token, sprintId: sprint.id,
                    storyPointsFieldId: appState.storyPointsFieldId)
                let allPoints: [Double] = issues.compactMap { $0.storyPoints }
                let committed: Double = allPoints.reduce(0, +)
                let donePoints: [Double] = issues.filter { $0.statusCategoryKey == "done" }.compactMap { $0.storyPoints }
                let completed: Double = donePoints.reduce(0, +)
                velocities.append(SprintVelocity(
                    id: sprint.id,
                    name: sprint.name,
                    committed: committed,
                    completed: completed,
                    startDate: sprint.startDate,
                    endDate: sprint.endDate
                ))
            }
            sprints = velocities

        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadEpicProgress(appState: AppState) async {
        guard appState.isJiraConfigured else { return }
        let baseURL = appState.jiraBaseURL
        let email   = appState.jiraEmail
        let token   = appState.jiraAPIToken
        let projectKey = appState.jiraProjectKeys.first ?? "CAMSRE"

        do {
            let jql = "project = \"\(projectKey)\" AND issuetype = Epic ORDER BY created DESC"
            let result = try await jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql, fields: ["summary", "status", "customfield_10015"], maxResults: 20)

            epics = result.issues.map { issue in
                let pts = 0.0  // story point totals would require child queries
                return EpicProgress(
                    id: issue.key,
                    name: issue.fields.summary ?? issue.key,
                    totalPoints: pts,
                    completedPoints: 0
                )
            }
        } catch {
            // Epic load is non-critical; silently ignore
        }
    }
}

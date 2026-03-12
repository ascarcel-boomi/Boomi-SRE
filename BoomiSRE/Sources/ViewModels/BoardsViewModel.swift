import Foundation
import SwiftUI

/// A Jira board with its parent project info.
struct JiraBoard: Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String  // "scrum" or "kanban"
    let projectKey: String
    let projectName: String
    let boardURL: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JiraBoard, rhs: JiraBoard) -> Bool { lhs.id == rhs.id }
}

struct JiraProject: Identifiable {
    let id: String
    let key: String
    let name: String
    var boards: [JiraBoard] = []
}

@MainActor
final class BoardsViewModel: ObservableObject {
    @Published var projects: [JiraProject] = []
    @Published var selectedBoard: JiraBoard?
    @Published var boardIssues: [JiraIssue] = []
    @Published var isLoadingProjects = false
    @Published var isLoadingBoard = false
    @Published var error: String?
    @Published var myAccountId: String = ""

    private let jiraService = JiraService()

    /// Discover recent projects and their boards.
    func loadProjects(appState: AppState) async {
        guard appState.isJiraConfigured else {
            error = "Jira not configured"
            return
        }

        isLoadingProjects = true
        error = nil
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)

        do {
            // Get my account ID
            myAccountId = try await jiraService.getMyAccountId(baseURL: baseURL, email: email, apiToken: token)

            // Get recent projects
            let recentProjects = try await fetchRecentProjects(baseURL: baseURL, email: email, token: token)

            // Fetch boards for each project in parallel
            var results: [JiraProject] = []
            await withTaskGroup(of: JiraProject?.self) { group in
                for proj in recentProjects {
                    group.addTask {
                        var p = proj
                        p.boards = (try? await self.fetchBoards(
                            baseURL: baseURL, email: email, token: token, projectKey: proj.key
                        )) ?? []
                        return p.boards.isEmpty ? nil : p
                    }
                }
                for await result in group {
                    if let p = result { results.append(p) }
                }
            }

            projects = results.sorted { $0.key < $1.key }
            isLoadingProjects = false
        } catch {
            self.error = error.localizedDescription
            isLoadingProjects = false
        }
    }

    /// Load issues for a board, filtered to current user.
    func loadBoard(_ board: JiraBoard, myTicketsOnly: Bool, appState: AppState) async {
        selectedBoard = board
        isLoadingBoard = true
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, appState.jiraAPIToken)

        do {
            let assigneeFilter = myTicketsOnly ? " AND assignee = currentUser()" : ""
            let jql: String
            if board.type == "kanban" {
                jql = "project = \(board.projectKey) AND statusCategory NOT IN (Done)\(assigneeFilter) ORDER BY priority ASC, updated DESC"
            } else {
                jql = "project = \(board.projectKey) AND sprint in openSprints()\(assigneeFilter) ORDER BY priority ASC, updated DESC"
            }

            let result = try await jiraService.searchIssues(
                baseURL: baseURL, email: email, apiToken: token,
                jql: jql,
                fields: ["summary", "status", "priority", "issuetype", "duedate", "assignee", "labels", "updated"],
                maxResults: 100
            )
            boardIssues = result.issues
            isLoadingBoard = false
        } catch {
            self.error = error.localizedDescription
            isLoadingBoard = false
        }
    }

    // MARK: - API helpers

    private func fetchRecentProjects(baseURL: String, email: String, token: String) async throws -> [JiraProject] {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/project")!
        components.queryItems = [URLQueryItem(name: "recent", value: "20")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: token)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return arr.compactMap { p in
            guard let id = p["id"] as? String,
                  let key = p["key"] as? String,
                  let name = p["name"] as? String else { return nil }
            return JiraProject(id: id, key: key, name: name)
        }
    }

    private func fetchBoards(baseURL: String, email: String, token: String, projectKey: String) async throws -> [JiraBoard] {
        var components = URLComponents(string: "\(baseURL)/rest/agile/1.0/board")!
        components.queryItems = [URLQueryItem(name: "projectKeyOrId", value: projectKey)]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: token)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[String: Any]] else { return [] }

        return values.compactMap { b in
            guard let id = b["id"] as? Int,
                  let name = b["name"] as? String,
                  let type = b["type"] as? String else { return nil }
            let loc = b["location"] as? [String: Any] ?? [:]
            let projKey = loc["projectKey"] as? String ?? projectKey
            let projName = loc["projectName"] as? String ?? projectKey
            let boardURL = "\(baseURL)/jira/software/c/projects/\(projKey)/boards/\(id)"
            return JiraBoard(id: id, name: name, type: type,
                             projectKey: projKey, projectName: projName, boardURL: boardURL)
        }
    }
}

private extension URLRequest {
    mutating func addBasicAuth(email: String, token: String) {
        if let data = "\(email):\(token)".data(using: .utf8) {
            setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
    }
}

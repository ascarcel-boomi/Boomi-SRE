import Foundation

// MARK: - Models

struct GitHubRepo: Identifiable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: GitHubRepo, rhs: GitHubRepo) -> Bool { lhs.id == rhs.id }
    let id: Int
    let name: String
    let fullName: String   // "owner/repo"
    let description: String
    let isPrivate: Bool
    let defaultBranch: String
    let openIssuesCount: Int
    let htmlURL: String
}

struct GitHubPR: Identifiable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: GitHubPR, rhs: GitHubPR) -> Bool { lhs.id == rhs.id }
    let id: Int
    let number: Int
    let title: String
    let body: String
    let state: String            // "open", "closed"
    let authorLogin: String
    let headBranch: String
    let baseBranch: String
    let createdAt: String
    let updatedAt: String
    let isDraft: Bool
    let htmlURL: String
    let reviewDecision: String?  // "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED"
    let requestedReviewers: [String]
}

struct GitHubPRFile: Identifiable, Sendable {
    var id: String { filename }
    let filename: String
    let status: String   // "added", "modified", "removed", "renamed"
    let additions: Int
    let deletions: Int
    let patch: String?   // actual diff (may be absent for binary files)
}

struct GitHubWorkflowRun: Identifiable, Sendable {
    let id: Int
    let name: String
    let status: String       // "queued", "in_progress", "completed"
    let conclusion: String?  // "success", "failure", "cancelled", "skipped"
    let createdAt: String
    let htmlURL: String
}

// MARK: - Service

/// GitHub REST API v3 client.
actor GitHubService {

    private let baseURL = "https://api.github.com"

    // MARK: - Auth

    func checkAuth(token: String) async throws -> String {
        let (data, response) = try await get("/user", token: token)
        try validate(response, data: data, service: "GitHub")
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let login = json["login"] as? String {
            let name = json["name"] as? String ?? login
            return "\(name) (@\(login))"
        }
        return "Authenticated"
    }

    // MARK: - Repositories

    func listOrgRepos(org: String, token: String) async throws -> [GitHubRepo] {
        var all: [GitHubRepo] = []
        var page = 1
        while true {
            let (data, response) = try await get("/orgs/\(org)/repos?per_page=100&page=\(page)&sort=updated", token: token)
            try validate(response, data: data, service: "GitHub")
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !arr.isEmpty else { break }
            all.append(contentsOf: arr.compactMap(parseRepo))
            if arr.count < 100 { break }
            page += 1
        }
        return all
    }

    func listUserRepos(token: String) async throws -> [GitHubRepo] {
        var all: [GitHubRepo] = []
        var page = 1
        while true {
            let (data, response) = try await get("/user/repos?per_page=100&page=\(page)&sort=updated&affiliation=owner,collaborator,organization_member", token: token)
            try validate(response, data: data, service: "GitHub")
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !arr.isEmpty else { break }
            all.append(contentsOf: arr.compactMap(parseRepo))
            if arr.count < 100 { break }
            page += 1
        }
        return all
    }

    // MARK: - Pull Requests

    func listPRs(owner: String, repo: String, state: String = "open", token: String) async throws -> [GitHubPR] {
        let (data, response) = try await get(
            "/repos/\(owner)/\(repo)/pulls?state=\(state)&per_page=50&sort=updated&direction=desc", token: token
        )
        try validate(response, data: data, service: "GitHub")
        let arr = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return arr.compactMap(parsePR)
    }

    func getPRFiles(owner: String, repo: String, number: Int, token: String) async throws -> [GitHubPRFile] {
        let (data, response) = try await get(
            "/repos/\(owner)/\(repo)/pulls/\(number)/files?per_page=100", token: token
        )
        try validate(response, data: data, service: "GitHub")
        let arr = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return arr.compactMap { f in
            guard let filename = f["filename"] as? String,
                  let status = f["status"] as? String else { return nil }
            return GitHubPRFile(
                filename: filename,
                status: status,
                additions: f["additions"] as? Int ?? 0,
                deletions: f["deletions"] as? Int ?? 0,
                patch: f["patch"] as? String
            )
        }
    }

    func getWorkflowRuns(owner: String, repo: String, token: String) async throws -> [GitHubWorkflowRun] {
        let (data, response) = try await get(
            "/repos/\(owner)/\(repo)/actions/runs?per_page=15", token: token
        )
        try validate(response, data: data, service: "GitHub")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]] else { return [] }
        return runs.compactMap { r in
            guard let id = r["id"] as? Int,
                  let name = r["name"] as? String,
                  let status = r["status"] as? String,
                  let createdAt = r["created_at"] as? String,
                  let htmlURL = r["html_url"] as? String else { return nil }
            return GitHubWorkflowRun(
                id: id, name: name, status: status,
                conclusion: r["conclusion"] as? String,
                createdAt: String(createdAt.prefix(10)),
                htmlURL: htmlURL
            )
        }
    }

    // MARK: - Issues

    func createIssue(
        owner: String,
        repo: String,
        title: String,
        body: String,
        labels: [String],
        token: String
    ) async throws -> (number: Int, htmlURL: String) {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["title": title, "body": body, "labels": labels]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, service: "GitHub")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = json["number"] as? Int,
              let htmlURL = json["html_url"] as? String else {
            throw ServiceError.httpError(service: "GitHub", status: 0, body: "Failed to parse issue response")
        }
        return (number: number, htmlURL: htmlURL)
    }

    // MARK: - Helpers

    private func get(_ path: String, token: String) async throws -> (Data, URLResponse) {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return try await URLSession.shared.data(for: request)
    }

    private func validate(_ response: URLResponse, data: Data, service: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: service, status: code, body: body)
        }
    }

    private func parseRepo(_ r: [String: Any]) -> GitHubRepo? {
        guard let id = r["id"] as? Int,
              let name = r["name"] as? String,
              let fullName = r["full_name"] as? String,
              let htmlURL = r["html_url"] as? String else { return nil }
        return GitHubRepo(
            id: id, name: name, fullName: fullName,
            description: r["description"] as? String ?? "",
            isPrivate: r["private"] as? Bool ?? false,
            defaultBranch: r["default_branch"] as? String ?? "main",
            openIssuesCount: r["open_issues_count"] as? Int ?? 0,
            htmlURL: htmlURL
        )
    }

    private func parsePR(_ p: [String: Any]) -> GitHubPR? {
        guard let id = p["id"] as? Int,
              let number = p["number"] as? Int,
              let title = p["title"] as? String,
              let state = p["state"] as? String,
              let htmlURL = p["html_url"] as? String else { return nil }
        let head = p["head"] as? [String: Any] ?? [:]
        let base = p["base"] as? [String: Any] ?? [:]
        let user = p["user"] as? [String: Any] ?? [:]
        let reviewers = ((p["requested_reviewers"] as? [[String: Any]]) ?? [])
            .compactMap { $0["login"] as? String }
        return GitHubPR(
            id: id, number: number, title: title,
            body: p["body"] as? String ?? "",
            state: state,
            authorLogin: user["login"] as? String ?? "?",
            headBranch: head["ref"] as? String ?? "",
            baseBranch: base["ref"] as? String ?? "",
            createdAt: String((p["created_at"] as? String ?? "").prefix(10)),
            updatedAt: String((p["updated_at"] as? String ?? "").prefix(10)),
            isDraft: p["draft"] as? Bool ?? false,
            htmlURL: htmlURL,
            reviewDecision: nil,
            requestedReviewers: reviewers
        )
    }
}

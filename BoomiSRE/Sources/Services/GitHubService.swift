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
    let mergedAt: String?        // non-nil means merged (subset of closed)
    let isDraft: Bool
    let htmlURL: String
    let reviewDecision: String?  // "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED"
    let requestedReviewers: [String]
    let labels: [String]
    let mergeable: Bool?         // nil if not yet computed by GitHub
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

struct GitHubBranch: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let sha: String
    let isProtected: Bool
}

struct GitHubCommit: Identifiable, Sendable {
    var id: String { sha }
    let sha: String
    let shortSha: String
    let message: String
    let authorName: String
    let date: String
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

    func listUserOrgs(token: String) async throws -> [String] {
        let (data, response) = try await get("/user/orgs?per_page=100", token: token)
        try validate(response, data: data, service: "GitHub")
        let arr = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return arr.compactMap { $0["login"] as? String }
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

    // MARK: - Branches

    func listBranches(owner: String, repo: String, token: String) async throws -> [GitHubBranch] {
        let (data, response) = try await get("/repos/\(owner)/\(repo)/branches?per_page=100", token: token)
        try validate(response, data: data, service: "GitHub")
        let arr = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return arr.compactMap { b -> GitHubBranch? in
            guard let name = b["name"] as? String,
                  let commit = b["commit"] as? [String: Any],
                  let sha = commit["sha"] as? String else { return nil }
            return GitHubBranch(name: name, sha: String(sha.prefix(7)), isProtected: b["protected"] as? Bool ?? false)
        }
    }

    func listCommits(owner: String, repo: String, token: String, perPage: Int = 30) async throws -> [GitHubCommit] {
        let (data, response) = try await get("/repos/\(owner)/\(repo)/commits?per_page=\(perPage)", token: token)
        try validate(response, data: data, service: "GitHub")
        let arr = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return arr.compactMap { c -> GitHubCommit? in
            guard let sha = c["sha"] as? String,
                  let htmlURL = c["html_url"] as? String else { return nil }
            let commit = c["commit"] as? [String: Any] ?? [:]
            let msg = (commit["message"] as? String ?? "").components(separatedBy: "\n").first ?? ""
            let author = commit["author"] as? [String: Any] ?? [:]
            return GitHubCommit(
                sha: sha, shortSha: String(sha.prefix(7)),
                message: String(msg.prefix(120)),
                authorName: author["name"] as? String ?? "?",
                date: String((author["date"] as? String ?? "").prefix(10)),
                htmlURL: htmlURL
            )
        }
    }

    // MARK: - Repo Detail & README

    struct RepoDetail: Sendable {
        let stargazersCount: Int
        let forksCount: Int
        let openIssuesCount: Int
        let language: String
        let license: String
        let topics: [String]
        let pushedAt: String   // ISO date → relative display
        let size: Int          // KB
        let defaultBranch: String
        let description: String
        let htmlURL: String
    }

    func getRepoDetail(owner: String, repo: String, token: String) async throws -> RepoDetail {
        let (data, response) = try await get("/repos/\(owner)/\(repo)", token: token)
        try validate(response, data: data, service: "GitHub")
        guard let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.httpError(service: "GitHub", status: 0, body: "Invalid JSON")
        }
        let license = (r["license"] as? [String: Any])?["spdx_id"] as? String ?? ""
        let topics = r["topics"] as? [String] ?? []
        return RepoDetail(
            stargazersCount: r["stargazers_count"] as? Int ?? 0,
            forksCount: r["forks_count"] as? Int ?? 0,
            openIssuesCount: r["open_issues_count"] as? Int ?? 0,
            language: r["language"] as? String ?? "",
            license: license,
            topics: topics,
            pushedAt: String((r["pushed_at"] as? String ?? "").prefix(10)),
            size: r["size"] as? Int ?? 0,
            defaultBranch: r["default_branch"] as? String ?? "main",
            description: r["description"] as? String ?? "",
            htmlURL: r["html_url"] as? String ?? ""
        )
    }

    func getReadme(owner: String, repo: String, token: String) async throws -> String {
        let (data, response) = try await get("/repos/\(owner)/\(repo)/readme", token: token)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return "" }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = json["content"] as? String else { return "" }
        let stripped = encoded.replacingOccurrences(of: "\n", with: "")
        guard let decoded = Data(base64Encoded: stripped) else { return "" }
        return String(decoding: decoded, as: UTF8.self)
    }

    // MARK: - PR Actions

    func mergePR(owner: String, repo: String, number: Int, method: String, token: String) async throws -> String {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)/merge")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "PUT"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["merge_method": method])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw ServiceError.httpError(service: "GitHub", status: 403, body: "You don't have write access to this repo.")
        }
        try validate(response, data: data, service: "GitHub")
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return json["sha"] as? String ?? "merged"
    }

    func approvePR(owner: String, repo: String, number: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)/reviews")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["event": "APPROVE"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, service: "GitHub")
    }

    func requestChanges(owner: String, repo: String, number: Int, body: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)/reviews")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["event": "REQUEST_CHANGES", "body": body])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, service: "GitHub")
    }

    func closePR(owner: String, repo: String, number: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PATCH"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["state": "closed"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, service: "GitHub")
    }

    func postComment(owner: String, repo: String, number: Int, body: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)/comments")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, service: "GitHub")
    }

    func triggerWorkflow(owner: String, repo: String, workflowId: Int, ref: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/actions/workflows/\(workflowId)/dispatches")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBearerAuth(token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ref": ref])
        let (data, response) = try await URLSession.shared.data(for: request)
        // 204 No Content is success for workflow dispatch
        guard let http = response as? HTTPURLResponse, http.statusCode == 204 || (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "GitHub", status: code, body: body)
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
        let labelNames = ((p["labels"] as? [[String: Any]]) ?? [])
            .compactMap { $0["name"] as? String }
        return GitHubPR(
            id: id, number: number, title: title,
            body: p["body"] as? String ?? "",
            state: state,
            authorLogin: user["login"] as? String ?? "?",
            headBranch: head["ref"] as? String ?? "",
            baseBranch: base["ref"] as? String ?? "",
            createdAt: String((p["created_at"] as? String ?? "").prefix(10)),
            updatedAt: String((p["updated_at"] as? String ?? "").prefix(10)),
            mergedAt: (p["merged_at"] as? String).map { String($0.prefix(10)) },
            isDraft: p["draft"] as? Bool ?? false,
            htmlURL: htmlURL,
            reviewDecision: nil,
            requestedReviewers: reviewers,
            labels: labelNames,
            mergeable: p["mergeable"] as? Bool
        )
    }
}

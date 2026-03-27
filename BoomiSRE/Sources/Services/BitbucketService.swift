import Foundation

actor BitbucketService {
    private let baseURL = "https://api.bitbucket.org/2.0"

    // MARK: - Auth
    func checkAuth(email: String, apiToken: String, workspace: String = "boomii") async throws -> String {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)?pagelen=1")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let size = json["size"] as? Int {
            return "\(workspace) workspace (\(size) repos)"
        }
        return "Connected to \(workspace)"
    }

    // MARK: - Repositories
    func listWorkspaceRepos(workspace: String, email: String, apiToken: String) async throws -> [BBRepo] {
        var all: [BBRepo] = []
        var page = 1
        let maxPages = 50  // safety cap to prevent runaway pagination
        while page <= maxPages {
            let url = URL(string: "\(baseURL)/repositories/\(workspace)?pagelen=100&sort=-updated_on&page=\(page)")!
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.addBasicAuth(email: email, token: apiToken)
            let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["values"] as? [[String: Any]], !values.isEmpty else { break }
            all.append(contentsOf: values.compactMap(parseRepo))
            if values.count < 100 { break }
            page += 1
        }
        return all
    }

    // MARK: - Pull Requests
    func listPRs(workspace: String, repoSlug: String, state: String = "OPEN",
                 email: String, apiToken: String) async throws -> [BBPR] {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests?state=\(state)&pagelen=50")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        let values = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["values"] as? [[String: Any]] ?? []
        return values.compactMap(parsePR)
    }

    func getPRDiff(workspace: String, repoSlug: String, prId: Int,
                   email: String, apiToken: String) async throws -> String {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/diff")!
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func getPRComments(workspace: String, repoSlug: String, prId: Int,
                       email: String, apiToken: String) async throws -> [BBComment] {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/comments?pagelen=50")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        let values = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["values"] as? [[String: Any]] ?? []
        return values.compactMap { c -> BBComment? in
            guard let id = c["id"] as? Int else { return nil }
            let author = ((c["author"] as? [String: Any])?["display_name"] as? String) ?? "?"
            let rawHTML = ((c["content"] as? [String: Any])?["html"] as? String) ?? ""
            let plain = rawHTML.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return BBComment(id: id, authorDisplayName: author, content: plain,
                             createdOn: String((c["created_on"] as? String ?? "").prefix(10)),
                             updatedOn: String((c["updated_on"] as? String ?? "").prefix(10)))
        }
    }

    // MARK: - Branches
    func listBranches(workspace: String, repoSlug: String, email: String, apiToken: String) async throws -> [BBBranch] {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/refs/branches?pagelen=50")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        let values = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["values"] as? [[String: Any]] ?? []
        return values.compactMap { b -> BBBranch? in
            guard let name = b["name"] as? String else { return nil }
            let hash = ((b["target"] as? [String: Any])?["hash"] as? String) ?? ""
            return BBBranch(name: name, target: String(hash.prefix(7)))
        }
    }

    // MARK: - Pipelines
    func listPipelines(workspace: String, repoSlug: String, email: String, apiToken: String) async throws -> [BBPipeline] {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pipelines?pagelen=20&sort=-created_on")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        let values = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["values"] as? [[String: Any]] ?? []
        return values.compactMap(parsePipeline)
    }

    // MARK: - Commits
    func listCommits(workspace: String, repoSlug: String, email: String, apiToken: String, limit: Int = 20) async throws -> [BBCommit] {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/commits?pagelen=\(limit)")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }
        let values = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["values"] as? [[String: Any]] ?? []
        return values.compactMap { c -> BBCommit? in
            guard let hash = c["hash"] as? String else { return nil }
            let msg = ((c["message"] as? String) ?? "").components(separatedBy: "\n").first ?? ""
            let author = ((c["author"] as? [String: Any])?["raw"] as? String) ?? "?"
            return BBCommit(hash: hash, shortHash: String(hash.prefix(7)),
                            message: String(msg.prefix(120)), authorName: author,
                            date: String((c["date"] as? String ?? "").prefix(10)))
        }
    }

    // MARK: - Actions
    func approvePR(workspace: String, repoSlug: String, prId: Int, email: String, apiToken: String) async throws {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/approve")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    func unapprovePR(workspace: String, repoSlug: String, prId: Int, email: String, apiToken: String) async throws {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/approve")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "DELETE"
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    func declinePR(workspace: String, repoSlug: String, prId: Int, email: String, apiToken: String) async throws {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/decline")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    func mergePR(workspace: String, repoSlug: String, prId: Int, message: String, strategy: String, email: String, apiToken: String) async throws {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/merge")!
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["message": message, "merge_strategy": strategy]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    func postPRComment(workspace: String, repoSlug: String, prId: Int, comment: String, email: String, apiToken: String) async throws {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pullrequests/\(prId)/comments")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["content": ["raw": comment]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    func triggerPipeline(workspace: String, repoSlug: String, branch: String, email: String, apiToken: String) async throws {
        let url = URL(string: "\(baseURL)/repositories/\(workspace)/\(repoSlug)/pipelines/")!
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["target": ["ref_type": "branch", "type": "pipeline_ref_target", "ref_name": branch]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Private parsers
    private func parseRepo(_ r: [String: Any]) -> BBRepo? {
        guard let fullName = r["full_name"] as? String else { return nil }
        let slug = r["slug"] as? String ?? String(fullName.split(separator: "/").last ?? "")
        let links = r["links"] as? [String: Any] ?? [:]
        let htmlURL = ((links["html"] as? [String: Any])?["href"] as? String) ?? "https://bitbucket.org/\(fullName)"
        let mainBranch = (r["mainbranch"] as? [String: Any])?["name"] as? String ?? "main"
        return BBRepo(
            id: r["uuid"] as? String ?? fullName,
            name: r["name"] as? String ?? slug,
            fullName: fullName,
            description: r["description"] as? String ?? "",
            isPrivate: r["is_private"] as? Bool ?? true,
            language: r["language"] as? String ?? "",
            mainBranch: mainBranch,
            updatedOn: String((r["updated_on"] as? String ?? "").prefix(10)),
            size: r["size"] as? Int ?? 0,
            htmlURL: htmlURL
        )
    }

    private func parsePR(_ p: [String: Any]) -> BBPR? {
        guard let id = p["id"] as? Int, let title = p["title"] as? String else { return nil }
        let author = p["author"] as? [String: Any] ?? [:]
        let source = p["source"] as? [String: Any] ?? [:]
        let dest = p["destination"] as? [String: Any] ?? [:]
        let links = p["links"] as? [String: Any] ?? [:]
        let htmlURL = ((links["html"] as? [String: Any])?["href"] as? String) ?? ""
        let sourceBranch = ((source["branch"] as? [String: Any])?["name"] as? String) ?? ""
        let destBranch = ((dest["branch"] as? [String: Any])?["name"] as? String) ?? ""
        return BBPR(
            id: id, title: title,
            description: p["description"] as? String ?? "",
            state: p["state"] as? String ?? "OPEN",
            authorDisplayName: author["display_name"] as? String ?? "?",
            authorNickname: author["nickname"] as? String ?? "?",
            sourceBranch: sourceBranch, destinationBranch: destBranch,
            createdOn: String((p["created_on"] as? String ?? "").prefix(10)),
            updatedOn: String((p["updated_on"] as? String ?? "").prefix(10)),
            commentCount: p["comment_count"] as? Int ?? 0,
            taskCount: p["task_count"] as? Int ?? 0,
            htmlURL: htmlURL
        )
    }

    private func parsePipeline(_ p: [String: Any]) -> BBPipeline? {
        guard let uuid = p["uuid"] as? String, let buildNumber = p["build_number"] as? Int else { return nil }
        let stateObj = p["state"] as? [String: Any] ?? [:]
        let state = stateObj["name"] as? String ?? "PENDING"
        let result = (stateObj["result"] as? [String: Any])?["name"] as? String
        let trigger = (p["trigger"] as? [String: Any])?["name"] as? String ?? "push"
        let target = p["target"] as? [String: Any] ?? [:]
        let branch = target["ref_name"] as? String ?? ""
        let links = p["links"] as? [String: Any] ?? [:]
        let htmlURL = ((links["html"] as? [String: Any])?["href"] as? String) ?? ""
        let duration = p["duration_in_seconds"] as? Int
        return BBPipeline(
            id: uuid, buildNumber: buildNumber, state: state, result: result,
            triggerName: trigger, targetBranch: branch,
            createdOn: String((p["created_on"] as? String ?? "").prefix(10)),
            completedOn: (p["completed_on"] as? String).map { String($0.prefix(10)) },
            durationSeconds: duration, htmlURL: htmlURL
        )
    }
}

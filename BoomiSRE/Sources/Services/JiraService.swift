import Foundation

/// Calls the Jira REST API v3 directly via URLSession.
actor JiraService {

    /// Verify credentials by calling GET /rest/api/3/myself.
    func checkAuth(baseURL: String, email: String, apiToken: String) async throws -> String {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/myself")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let user = try JSONDecoder().decode(JiraUser.self, from: data)
        return user.displayName
    }

    /// Search issues using JQL via GET /rest/api/3/search/jql.
    func searchIssues(
        baseURL: String, email: String, apiToken: String,
        jql: String,
        fields: [String] = ["summary", "status", "priority", "issuetype",
                             "duedate", "labels", "created", "updated"],
        maxResults: Int = 50
    ) async throws -> JiraSearchResult {
        let (data, _) = try await executeSearch(
            baseURL: baseURL, email: email, apiToken: apiToken,
            jql: jql, fields: fields, maxResults: maxResults
        )
        return try JSONDecoder().decode(JiraSearchResult.self, from: data)
    }

    /// Search issues and return raw JSON alongside decoded results.
    /// Use this when you need to extract dynamic custom fields (e.g. sprint).
    func searchIssuesRaw(
        baseURL: String, email: String, apiToken: String,
        jql: String, fields: [String], maxResults: Int = 200
    ) async throws -> (result: JiraSearchResult, rawIssues: [[String: Any]]) {
        let (data, _) = try await executeSearch(
            baseURL: baseURL, email: email, apiToken: apiToken,
            jql: jql, fields: fields, maxResults: maxResults
        )
        let decoded = try JSONDecoder().decode(JiraSearchResult.self, from: data)

        var rawIssues: [[String: Any]] = []
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issues = json["issues"] as? [[String: Any]] {
            rawIssues = issues
        }
        return (decoded, rawIssues)
    }

    /// Execute a JQL search via GET /rest/api/3/search/jql with query parameters.
    /// POST with JSON body is rejected by some Jira Cloud instances.
    private func executeSearch(
        baseURL: String, email: String, apiToken: String,
        jql: String, fields: [String], maxResults: Int
    ) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: fields.joined(separator: ",")),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        guard let url = components.url else {
            throw JiraError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)
        return (data, response)
    }

    /// Discover the custom field ID for "Sprint" by scanning all fields.
    func discoverSprintFieldId(
        baseURL: String, email: String, apiToken: String
    ) async throws -> String? {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/field")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let fields = try JSONDecoder().decode([JiraFieldMeta].self, from: data)
        return fields.first { $0.name == "Sprint" }?.id
    }

    /// Fetch the current user's favourite filters.
    func fetchFavouriteFilters(
        baseURL: String, email: String, apiToken: String
    ) async throws -> [JiraFilter] {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/filter/favourite")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        return try JSONDecoder().decode([JiraFilter].self, from: data)
    }

    // MARK: - Ticket Actions

    /// Get full issue details including description and comments.
    func getIssue(
        baseURL: String, email: String, apiToken: String, key: String
    ) async throws -> (issue: JiraIssue, raw: [String: Any]) {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)?fields=summary,status,priority,issuetype,duedate,labels,created,updated,assignee,comment,description")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let issue = try JSONDecoder().decode(JiraIssue.self, from: data)
        let raw = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (issue, raw)
    }

    /// Get available transitions for an issue.
    func getTransitions(
        baseURL: String, email: String, apiToken: String, key: String
    ) async throws -> [JiraTransition] {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/transitions")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        // Parse manually since transitions are nested
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transitions = json["transitions"] as? [[String: Any]] else { return [] }

        return transitions.compactMap { t in
            guard let id = t["id"] as? String,
                  let name = t["name"] as? String,
                  let to = t["to"] as? [String: Any],
                  let toName = to["name"] as? String else { return nil }
            let catName = (to["statusCategory"] as? [String: Any])?["name"] as? String ?? ""
            return JiraTransition(id: id, name: name, toStatus: toName, toCategory: catName)
        }
    }

    /// Transition an issue to a new status.
    func transitionIssue(
        baseURL: String, email: String, apiToken: String,
        key: String, transitionId: String
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/transitions")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["transition": ["id": transitionId]])

        let (data, response) = try await URLSession.shared.data(for: request)
        // 204 No Content is success
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }

    /// Add a comment to an issue (Atlassian Document Format).
    func addComment(
        baseURL: String, email: String, apiToken: String,
        key: String, body: String
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/comment")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // ADF format for a simple text paragraph
        let adf: [String: Any] = [
            "body": [
                "version": 1,
                "type": "doc",
                "content": [
                    ["type": "paragraph", "content": [
                        ["type": "text", "text": body]
                    ]]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: adf)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)
    }

    /// Assign an issue to a user by accountId. Pass nil to unassign.
    func assignIssue(
        baseURL: String, email: String, apiToken: String,
        key: String, accountId: String?
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/assignee")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PUT"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["accountId": accountId as Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }

    /// Search users by name/email for assignment.
    func searchUsers(
        baseURL: String, email: String, apiToken: String, query: String
    ) async throws -> [JiraAssignableUser] {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/user/search")!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        guard let users = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return users.compactMap { u in
            guard let id = u["accountId"] as? String,
                  let name = u["displayName"] as? String else { return nil }
            return JiraAssignableUser(accountId: id, displayName: name)
        }
    }

    /// Get the current user's accountId.
    func getMyAccountId(
        baseURL: String, email: String, apiToken: String
    ) async throws -> String {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/myself")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountId = json["accountId"] as? String else {
            throw JiraError.invalidResponse
        }
        return accountId
    }

    // MARK: - Private

    private func validateResponse(_ service: String, _ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }
}

// MARK: - Errors

enum JiraError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Jira"
        case .httpError(let status, let body):
            return "Jira returned HTTP \(status):\n\(body.prefix(300))"
        case .notConfigured:
            return "Jira is not configured. Open Settings to add your credentials."
        }
    }
}

// MARK: - Helpers

private extension String {
    var trimSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

private extension URLRequest {
    mutating func addBasicAuth(email: String, token: String) {
        if let data = "\(email):\(token)".data(using: .utf8) {
            setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
    }
}

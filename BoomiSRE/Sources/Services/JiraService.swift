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

    /// Search issues using JQL via POST /rest/api/3/search/jql.
    func searchIssues(
        baseURL: String, email: String, apiToken: String,
        jql: String,
        fields: [String] = ["summary", "status", "priority", "issuetype",
                             "duedate", "labels", "created", "updated"],
        maxResults: Int = 50
    ) async throws -> JiraSearchResult {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/search/jql")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["jql": jql, "fields": fields, "maxResults": maxResults]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        return try JSONDecoder().decode(JiraSearchResult.self, from: data)
    }

    /// Search issues and return raw JSON alongside decoded results.
    /// Use this when you need to extract dynamic custom fields (e.g. sprint).
    func searchIssuesRaw(
        baseURL: String, email: String, apiToken: String,
        jql: String, fields: [String], maxResults: Int = 200
    ) async throws -> (result: JiraSearchResult, rawIssues: [[String: Any]]) {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/search/jql")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["jql": jql, "fields": fields, "maxResults": maxResults]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let decoded = try JSONDecoder().decode(JiraSearchResult.self, from: data)

        // Also parse raw JSON for custom field extraction
        var rawIssues: [[String: Any]] = []
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issues = json["issues"] as? [[String: Any]] {
            rawIssues = issues
        }

        return (decoded, rawIssues)
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

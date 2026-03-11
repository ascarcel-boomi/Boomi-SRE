import Foundation

/// Calls the Jira REST API v3 directly via URLSession.
actor JiraService {

    /// Verify credentials by calling GET /rest/api/3/myself.
    /// Returns the display name on success.
    func checkAuth(baseURL: String, email: String, apiToken: String) async throws -> String {
        let url = URL(string: "\(baseURL.trimmingSlash)/rest/api/3/myself")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let user = try JSONDecoder().decode(JiraUser.self, from: data)
        return user.displayName
    }

    /// Search issues using JQL via POST /rest/api/3/search/jql.
    func searchIssues(
        baseURL: String, email: String, apiToken: String,
        jql: String, fields: [String] = ["summary", "status", "priority", "issuetype",
                                           "duedate", "labels", "created", "updated"],
        maxResults: Int = 50
    ) async throws -> JiraSearchResult {
        let url = URL(string: "\(baseURL.trimmingSlash)/rest/api/3/search/jql")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jql": jql,
            "fields": fields,
            "maxResults": maxResults,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(JiraSearchResult.self, from: data)
    }

    // MARK: - Private

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JiraError.httpError(status: http.statusCode, body: body)
        }
    }
}

// MARK: - Models

struct JiraSearchResult: Codable {
    let total: Int
    let issues: [JiraIssue]
}

struct JiraIssue: Codable, Identifiable {
    let id: String
    let key: String
    let fields: JiraFields
}

struct JiraFields: Codable {
    let summary: String?
    let status: JiraNamedField?
    let priority: JiraNamedField?
    let issuetype: JiraNamedField?
    let duedate: String?
    let labels: [String]?
    let created: String?
    let updated: String?
}

struct JiraNamedField: Codable {
    let name: String
}

struct JiraUser: Codable {
    let displayName: String
    let emailAddress: String?
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
            return "Jira is not configured. Open Settings (Cmd+,) to add your credentials."
        }
    }
}

// MARK: - Helpers

private extension String {
    var trimmingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}

private extension URLRequest {
    mutating func addBasicAuth(email: String, token: String) {
        let credentials = "\(email):\(token)"
        if let data = credentials.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
    }
}

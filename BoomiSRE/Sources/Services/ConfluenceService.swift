import Foundation

/// Confluence REST API client — verifies auth via the wiki user endpoint.
actor ConfluenceService {
    /// Check auth by calling GET /wiki/rest/api/user/current.
    /// Returns the display name on success.
    func checkAuth(baseURL: String, email: String, apiToken: String) async throws -> String {
        let url = URL(string: "\(baseURL.trimmingSlash)/wiki/rest/api/user/current")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Confluence", status: code, body: body)
        }

        // Confluence v1 API returns {"displayName": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["displayName"] as? String {
            return name
        }
        return "Authenticated"
    }
}

private extension String {
    var trimmingSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

private extension URLRequest {
    mutating func addBasicAuth(email: String, token: String) {
        if let data = "\(email):\(token)".data(using: .utf8) {
            setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
    }
}

import Foundation

/// Bitbucket Cloud API client — verifies auth via the user endpoint.
actor BitbucketService {
    /// Check auth by calling GET https://api.bitbucket.org/2.0/user.
    /// Returns the display name on success.
    func checkAuth(email: String, apiToken: String) async throws -> String {
        let url = URL(string: "https://api.bitbucket.org/2.0/user")!
        var request = URLRequest(url: url, timeoutInterval: 15)

        // Bitbucket Cloud uses Basic Auth with email:app-password (or API token)
        if let data = "\(email):\(apiToken)".data(using: .utf8) {
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Bitbucket", status: code, body: body)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["display_name"] as? String {
            return name
        }
        return "Authenticated"
    }
}

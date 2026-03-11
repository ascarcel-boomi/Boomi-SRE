import Foundation

/// GitHub API client — verifies auth via the user endpoint.
actor GitHubService {
    /// Check auth by calling GET https://api.github.com/user.
    /// Returns the login name on success.
    func checkAuth(token: String) async throws -> String {
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "GitHub", status: code, body: body)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let login = json["login"] as? String {
            let name = json["name"] as? String ?? login
            return "\(name) (@\(login))"
        }
        return "Authenticated"
    }
}

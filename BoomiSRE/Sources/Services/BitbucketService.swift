import Foundation

/// Bitbucket Cloud API client — verifies auth via the workspace repos endpoint.
///
/// We use /2.0/repositories/boomii instead of /2.0/user because scoped API tokens
/// with only repository permissions (read:repository:bitbucket) can't access /2.0/user
/// (which requires read:user:bitbucket). The repos endpoint works with repo-scoped tokens.
actor BitbucketService {
    /// Check auth by listing repos in the boomii workspace.
    /// Returns the workspace name and repo count on success.
    func checkAuth(email: String, apiToken: String, workspace: String = "boomii") async throws -> String {
        let url = URL(string: "https://api.bitbucket.org/2.0/repositories/\(workspace)?pagelen=1")!
        var request = URLRequest(url: url, timeoutInterval: 15)

        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
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
}

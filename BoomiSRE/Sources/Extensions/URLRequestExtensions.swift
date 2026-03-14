import Foundation

// MARK: - Shared URLRequest Auth Helpers

extension URLRequest {
    /// Add HTTP Basic auth header (email:token → base64).
    /// Used by: JiraService, ConfluenceService, BitbucketService.
    mutating func addBasicAuth(email: String, token: String) {
        if let data = "\(email):\(token)".data(using: .utf8) {
            setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
    }

    /// Add HTTP Bearer auth header.
    /// Used by: GrafanaService (API calls), GitHubService.
    mutating func addBearerAuth(token: String) {
        setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - Shared String URL Helpers

extension String {
    /// Trim a trailing slash from a URL base string.
    var trimSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

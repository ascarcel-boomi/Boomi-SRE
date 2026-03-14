import Foundation

/// Jira Service Management (JSM) Operations API client.
/// Uses the Atlassian API at api.atlassian.com with the same Jira email/token credentials.
actor JSMOpsService {

    private var cloudId: String?

    /// Discover the Atlassian Cloud ID from tenant_info endpoint.
    func getCloudId(baseURL: String) async throws -> String {
        if let cached = cloudId { return cached }
        let url = URL(string: "\(baseURL.trimSlash)/_edge/tenant_info")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: req)
        _ = req  // used above
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JSMError.httpError(status: code, body: "tenant_info request failed")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["cloudId"] as? String else {
            throw JSMError.cloudIdNotFound
        }
        cloudId = id
        return id
    }

    /// List all JSM Ops teams.
    func listTeams(baseURL: String, email: String, apiToken: String) async throws -> [OpsTeam] {
        let cid = try await getCloudId(baseURL: baseURL)
        let url = URL(string: "https://api.atlassian.com/jsm/ops/api/\(cid)/v1/teams")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response, data: data)
        // Try to decode; JSM APIs can return different wrapper shapes
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let values = json["values"] as? [[String: Any]] {
            return values.compactMap { parseTeam($0) }
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { parseTeam($0) }
        }
        return []
    }

    /// Get who is currently on call for a team.
    func getOnCall(baseURL: String, email: String, apiToken: String,
                   teamId: String) async throws -> [OnCallParticipant] {
        let cid = try await getCloudId(baseURL: baseURL)
        // Try team on-call endpoint first
        let url = URL(string: "https://api.atlassian.com/jsm/ops/api/\(cid)/v1/teams/\(teamId)/on-calls")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // Parse participants from various possible response shapes
        let participants = (json["onCallParticipants"] as? [[String: Any]])
            ?? (json["participants"] as? [[String: Any]])
            ?? []
        return participants.compactMap { p in
            guard let name = (p["name"] as? String) ?? (p["displayName"] as? String) else { return nil }
            let type_ = p["type"] as? String ?? "user"
            return OnCallParticipant(name: name, type: type_)
        }
    }

    /// List open alerts.
    func listAlerts(baseURL: String, email: String, apiToken: String,
                    query: String? = nil) async throws -> [OpsAlert] {
        let cid = try await getCloudId(baseURL: baseURL)
        var components = URLComponents(string: "https://api.atlassian.com/jsm/ops/api/\(cid)/v1/alerts")!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "50")]
        if let q = query { queryItems.append(URLQueryItem(name: "query", value: q)) }
        components.queryItems = queryItems
        var req = URLRequest(url: components.url!, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let values = (json["values"] as? [[String: Any]]) ?? (json["alerts"] as? [[String: Any]]) ?? []
        return values.compactMap { parseAlert($0) }
    }

    /// List schedules for a team.
    func listSchedules(baseURL: String, email: String, apiToken: String,
                       teamId: String) async throws -> [OpsSchedule] {
        let cid = try await getCloudId(baseURL: baseURL)
        var components = URLComponents(string: "https://api.atlassian.com/jsm/ops/api/\(cid)/v1/schedules")!
        components.queryItems = [URLQueryItem(name: "teamId", value: teamId)]
        var req = URLRequest(url: components.url!, timeoutInterval: 15)
        req.addBasicAuth(email: email, token: apiToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let values = (json["values"] as? [[String: Any]]) ?? []
        return values.compactMap { s in
            guard let id = s["id"] as? String, let name = s["name"] as? String else { return nil }
            return OpsSchedule(id: id, name: name,
                               teamId: s["teamId"] as? String,
                               enabled: s["enabled"] as? Bool ?? true)
        }
    }

    // MARK: - Private

    private func parseTeam(_ d: [String: Any]) -> OpsTeam? {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        return OpsTeam(id: id, name: name, description: d["description"] as? String)
    }

    private func parseAlert(_ d: [String: Any]) -> OpsAlert? {
        guard let id = d["id"] as? String,
              let message = d["message"] as? String else { return nil }
        return OpsAlert(
            id: id,
            message: message,
            status: d["status"] as? String ?? "open",
            priority: d["priority"] as? String ?? "P3",
            createdAt: d["createdAt"] as? String ?? "",
            updatedAt: d["updatedAt"] as? String ?? "",
            source: d["source"] as? String,
            tags: d["tags"] as? [String],
            teamId: d["teamId"] as? String
        )
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JSMError.httpError(status: code, body: body)
        }
    }
}

// MARK: - Errors

enum JSMError: LocalizedError {
    case cloudIdNotFound
    case httpError(status: Int, body: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .cloudIdNotFound:
            return "Could not discover the Atlassian Cloud ID from tenant_info"
        case .httpError(let status, let body):
            if status == 403 {
                return "JSM Operations returned 403 — your Atlassian plan may not include JSM Operations, or your API token lacks the required scopes."
            }
            return "JSM returned HTTP \(status): \(body.prefix(200))"
        case .notConfigured:
            return "Jira credentials not configured. Add them in Settings → Jira."
        }
    }
}

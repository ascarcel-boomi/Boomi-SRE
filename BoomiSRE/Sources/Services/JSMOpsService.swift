import Foundation

/// JSM Operations API client.
///
/// Base URL: https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/
/// Auth: Standard Atlassian Basic auth — email:apiToken (same as Jira/Confluence)
/// CloudId: discovered from {jiraBaseURL}/_edge/tenant_info (no auth needed, cached)
///
/// Note: Alerts (GET /v1/alerts) return 404 on this API.
/// Alerts require a separate JSM Ops API Integration key (optional — see settings).
actor JSMOpsService {

    private var cloudId: String?

    // MARK: - Cloud ID

    func getCloudId(baseURL: String) async throws -> String {
        if let cached = cloudId { return cached }
        let clean = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let url = URL(string: "\(clean)/_edge/tenant_info")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw JSMError.cloudIdNotFound
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["cloudId"] as? String else {
            throw JSMError.cloudIdNotFound
        }
        cloudId = id
        return id
    }

    // MARK: - Schedules

    func listSchedules(baseURL: String, email: String, apiToken: String) async throws -> [OpsSchedule] {
        let cid = try await getCloudId(baseURL: baseURL)
        let data = try await get(path: "/schedules", cloudId: cid, email: email, apiToken: apiToken)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { s -> OpsSchedule? in
            guard let id = s["id"] as? String, let name = s["name"] as? String else { return nil }
            return OpsSchedule(id: id, name: name,
                               teamId: s["teamId"] as? String,
                               enabled: s["enabled"] as? Bool ?? true)
        }
    }

    func getOnCall(baseURL: String, email: String, apiToken: String,
                   scheduleId: String) async throws -> [OnCallParticipant] {
        let cid = try await getCloudId(baseURL: baseURL)
        let data = try await get(path: "/schedules/\(scheduleId)/on-calls",
                                 cloudId: cid, email: email, apiToken: apiToken)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let participants = (json["onCallParticipants"] as? [[String: Any]]) ?? []
        return participants.compactMap { p -> OnCallParticipant? in
            guard let accountId = p["id"] as? String else { return nil }
            return OnCallParticipant(name: accountId, type: p["type"] as? String ?? "user")
        }
    }

    // MARK: - Teams

    func listTeams(baseURL: String, email: String, apiToken: String) async throws -> [OpsTeam] {
        let cid = try await getCloudId(baseURL: baseURL)
        let data = try await get(path: "/teams", cloudId: cid, email: email, apiToken: apiToken)
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { parseTeam($0) }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let values = json["values"] as? [[String: Any]] {
            return values.compactMap { parseTeam($0) }
        }
        return []
    }

    // MARK: - Alerts (Atlassian API — same auth as schedules and teams)

    /// Fetch alerts from the Atlassian JSM Ops API using the same Jira Basic auth.
    /// Confirmed working: returns 100K+ alerts. Uses {"values": [...]} wrapper (not "data").
    func listAlerts(baseURL: String, email: String, apiToken: String,
                    limit: Int = 50, query: String? = nil) async throws -> [OpsAlert] {
        let cid = try await getCloudId(baseURL: baseURL)
        var path = "/alerts?limit=\(limit)&sort=createdAt&order=desc"
        if let q = query, !q.isEmpty {
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            path += "&query=\(encoded)"
        }
        let data = try await get(path: path, cloudId: cid, email: email, apiToken: apiToken)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { parseAlert($0) }
    }

    // MARK: - Resolve display names

    func resolveDisplayName(accountId: String, baseURL: String,
                            email: String, apiToken: String) async throws -> String {
        let clean = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let url = URL(string: "\(clean)/rest/api/3/user?accountId=\(accountId)")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let authData = "\(email):\(apiToken)".data(using: .utf8) {
            req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return accountId
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return json["displayName"] as? String ?? accountId
    }

    // MARK: - Private

    private func get(path: String, cloudId: String, email: String, apiToken: String) async throws -> Data {
        let url = URL(string: "https://api.atlassian.com/jsm/ops/api/\(cloudId)/v1\(path)")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        if let authData = "\(email):\(apiToken)".data(using: .utf8) {
            req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JSMError.httpError(status: code, body: body)
        }
        return data
    }

    private func parseAlert(_ d: [String: Any]) -> OpsAlert? {
        guard let id = d["id"] as? String,
              let message = d["message"] as? String else { return nil }
        let responders = (d["responders"] as? [[String: Any]] ?? []).compactMap { r -> AlertResponder? in
            guard let rid = r["id"] as? String, let rtype = r["type"] as? String else { return nil }
            return AlertResponder(id: rid, type: rtype)
        }
        return OpsAlert(
            id: id,
            tinyId: d["tinyId"] as? String ?? "",
            message: message,
            status: d["status"] as? String ?? "open",
            priority: d["priority"] as? String ?? "P3",
            acknowledged: d["acknowledged"] as? Bool ?? false,
            owner: d["owner"] as? String ?? "",
            source: d["source"] as? String ?? "",
            integrationType: d["integrationType"] as? String ?? "",
            integrationName: d["integrationName"] as? String ?? "",
            createdAt: d["createdAt"] as? String ?? "",
            updatedAt: d["updatedAt"] as? String ?? "",
            tags: d["tags"] as? [String] ?? [],
            snoozed: d["snoozed"] as? Bool ?? false,
            count: d["count"] as? Int ?? 1,
            responders: responders
        )
    }

    private func parseTeam(_ d: [String: Any]) -> OpsTeam? {
        let id   = d["teamId"] as? String ?? d["id"] as? String
        let name = d["teamName"] as? String ?? d["name"] as? String
        guard let id, let name else { return nil }
        return OpsTeam(id: id, name: name, description: d["description"] as? String)
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
            return "Could not discover the Atlassian Cloud ID. Check your Jira base URL in Settings."
        case .httpError(let status, let body):
            switch status {
            case 401: return "Invalid Jira credentials for JSM Operations. Check your email and API token in Settings → Jira."
            case 403: return "Your Jira account doesn't have access to JSM Operations. Contact your JSM admin."
            case 404: return "JSM Operations endpoint not found — this feature may not be available on your plan."
            default:  return "JSM Operations returned HTTP \(status): \(body.prefix(200))"
            }
        case .notConfigured:
            return "Jira credentials not configured. Add them in Settings → Jira."
        }
    }
}

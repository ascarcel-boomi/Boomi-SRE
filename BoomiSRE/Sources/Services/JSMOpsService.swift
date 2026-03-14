import Foundation

/// JSM Operations (hosted at api.opsgenie.com) API client.
///
/// Authentication: `Authorization: GenieKey {apiKey}` — NOT the Jira API token.
/// Create an API Integration key at: boomii.atlassian.net/jira/ops/integrations
/// Base URL: https://api.opsgenie.com/v2
actor JSMOpsService {

    private let baseURL = "https://api.opsgenie.com/v2"

    // MARK: - Schedules

    /// List all on-call schedules accessible to this API key.
    func listSchedules(apiKey: String) async throws -> [OpsSchedule] {
        let (data, _) = try await request(path: "/schedules", apiKey: apiKey)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["data"] as? [[String: Any]] else { return [] }
        return values.compactMap { s -> OpsSchedule? in
            guard let id = s["id"] as? String, let name = s["name"] as? String else { return nil }
            let teamId = (s["ownerTeam"] as? [String: Any])?["id"] as? String
            return OpsSchedule(id: id, name: name, teamId: teamId, enabled: s["enabled"] as? Bool ?? true)
        }
    }

    /// Get who is currently on call for a schedule.
    func getOnCallForSchedule(scheduleId: String, apiKey: String) async throws -> [OnCallParticipant] {
        let (data, _) = try await request(path: "/schedules/\(scheduleId)/on-calls",
                                          apiKey: apiKey,
                                          queryItems: [URLQueryItem(name: "flat", value: "true")])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any] else { return [] }
        let recipients = inner["onCallRecipients"] as? [String] ?? []
        return recipients.map { OnCallParticipant(name: $0, type: "user") }
    }

    /// List active alerts (max 100).
    func listAlerts(apiKey: String, query: String? = nil) async throws -> [OpsAlert] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "100"),
                                     URLQueryItem(name: "order", value: "desc")]
        if let q = query { items.append(URLQueryItem(name: "query", value: q)) }
        let (data, _) = try await request(path: "/alerts", apiKey: apiKey, queryItems: items)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["data"] as? [[String: Any]] else { return [] }
        return values.compactMap(parseAlert)
    }

    // MARK: - Teams (maps schedules to OpsTeam for backward compatibility with OnCallView)

    /// Returns the list of schedules as OpsTeam objects so the existing UI can display them.
    func listTeams(apiKey: String) async throws -> [OpsTeam] {
        let schedules = try await listSchedules(apiKey: apiKey)
        return schedules.map { OpsTeam(id: $0.id, name: $0.name, description: nil) }
    }

    /// Get on-call participants for a team (by schedule ID).
    func getOnCall(teamId: String, apiKey: String) async throws -> [OnCallParticipant] {
        return try await getOnCallForSchedule(scheduleId: teamId, apiKey: apiKey)
    }

    // MARK: - Private

    private func request(path: String, apiKey: String,
                         queryItems: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var req = URLRequest(url: components.url!, timeoutInterval: 15)
        req.setValue("GenieKey \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw JSMError.httpError(status: 0, body: "No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JSMError.httpError(status: http.statusCode, body: body)
        }
        return (data, http)
    }

    private func parseAlert(_ d: [String: Any]) -> OpsAlert? {
        guard let id = d["id"] as? String,
              let message = d["message"] as? String else { return nil }
        return OpsAlert(
            id: id, message: message,
            status: d["status"] as? String ?? "open",
            priority: d["priority"] as? String ?? "P3",
            createdAt: d["createdAt"] as? String ?? "",
            updatedAt: d["updatedAt"] as? String ?? "",
            source: d["source"] as? String,
            tags: d["tags"] as? [String],
            teamId: (d["teams"] as? [[String: Any]])?.first?["id"] as? String
        )
    }
}

// MARK: - Errors

enum JSMError: LocalizedError {
    case cloudIdNotFound     // kept for source compat but no longer used
    case httpError(status: Int, body: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .cloudIdNotFound:
            return "Cloud ID discovery is no longer used"
        case .httpError(let status, let body):
            switch status {
            case 401: return "JSM Ops API key is invalid or the integration is not turned on. Check Settings → JSM Operations."
            case 403: return "JSM Ops API key lacks access. If using a team-scoped key, the team must have access to the requested schedule/alert."
            case 422: return "Invalid request — check parameters."
            case 429: return "Rate limit hit. Try again in a moment."
            default:  return "JSM Ops returned HTTP \(status): \(body.prefix(200))"
            }
        case .notConfigured:
            return "JSM Ops API key not configured. Add it in Settings → JSM Operations."
        }
    }
}

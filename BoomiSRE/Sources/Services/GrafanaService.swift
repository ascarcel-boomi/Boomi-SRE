import Foundation

// MARK: - Models

struct GrafanaDashboard: Identifiable, Hashable, Equatable, Sendable {
    var id: String { uid }
    func hash(into hasher: inout Hasher) { hasher.combine(uid) }
    static func == (lhs: GrafanaDashboard, rhs: GrafanaDashboard) -> Bool { lhs.uid == rhs.uid }
    let uid: String
    let title: String
    let folderTitle: String
    let tags: [String]
    let url: String   // path, not full URL
}

struct GrafanaPanel: Identifiable, Sendable {
    let id: Int
    let title: String
    let type: String
    let description: String
    let targets: [String]   // PromQL / LogQL expressions
}

struct GrafanaAlertRule: Identifiable, Sendable {
    var id: String { uid }
    let uid: String
    let title: String
    let folderUID: String
    let state: String   // "alerting", "pending", "normal", "nodata", "error"
    let labels: [String: String]
    let summary: String
}

// MARK: - Service

/// Grafana REST API client.
actor GrafanaService {

    // MARK: - Dashboards

    func searchDashboards(baseURL: String, token: String) async throws -> [GrafanaDashboard] {
        let (data, response) = try await get("/api/search?type=dash-db&limit=200",
                                             baseURL: baseURL, token: token)
        try validate(response, data: data, service: "Grafana")
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let uid = d["uid"] as? String,
                  let title = d["title"] as? String else { return nil }
            return GrafanaDashboard(
                uid: uid,
                title: title,
                folderTitle: d["folderTitle"] as? String ?? "General",
                tags: d["tags"] as? [String] ?? [],
                url: d["url"] as? String ?? ""
            )
        }
    }

    func getDashboard(uid: String, baseURL: String, token: String) async throws -> [GrafanaPanel] {
        let (data, response) = try await get("/api/dashboards/uid/\(uid)", baseURL: baseURL, token: token)
        try validate(response, data: data, service: "Grafana")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dashboard = json["dashboard"] as? [String: Any],
              let panels = dashboard["panels"] as? [[String: Any]] else { return [] }

        return panels.compactMap { p in
            guard let id = p["id"] as? Int else { return nil }
            let title = p["title"] as? String ?? "Panel \(id)"
            let type_ = p["type"] as? String ?? "unknown"
            let desc = p["description"] as? String ?? ""
            // Extract query expressions from targets
            var exprs: [String] = []
            if let targets = p["targets"] as? [[String: Any]] {
                for target in targets {
                    if let expr = target["expr"] as? String, !expr.isEmpty { exprs.append(expr) }
                    if let q = target["query"] as? String, !q.isEmpty { exprs.append(q) }
                    if let qs = target["queryString"] as? String, !qs.isEmpty { exprs.append(qs) }
                }
            }
            return GrafanaPanel(id: id, title: title, type: type_, description: desc, targets: exprs)
        }
    }

    // MARK: - Alerts

    func listAlertRules(baseURL: String, token: String) async throws -> [GrafanaAlertRule] {
        let (data, response) = try await get("/api/v1/provisioning/alert-rules",
                                             baseURL: baseURL, token: token)
        // Some Grafana instances may not support provisioning API — fall back to empty
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { r in
            guard let uid = r["uid"] as? String,
                  let title = r["title"] as? String else { return nil }
            let labels = r["labels"] as? [String: String] ?? [:]
            let annotations = r["annotations"] as? [String: String] ?? [:]
            let state = (r["ruleGroup"] as? String) ?? "unknown"
            return GrafanaAlertRule(
                uid: uid, title: title,
                folderUID: r["folderUID"] as? String ?? "",
                state: state,
                labels: labels,
                summary: annotations["summary"] ?? annotations["description"] ?? ""
            )
        }
    }

    // MARK: - Auth check

    func checkAuth(baseURL: String, token: String) async throws -> String {
        let (data, response) = try await get("/api/org", baseURL: baseURL, token: token)
        try validate(response, data: data, service: "Grafana")
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String { return name }
        return "Authenticated"
    }

    // MARK: - Private

    private func get(_ path: String, baseURL: String, token: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: baseURL.trimSlash + path) else {
            throw ServiceError.httpError(service: "Grafana", status: 0, body: "Invalid URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.addBearerAuth(token: token)
        return try await URLSession.shared.data(for: request)
    }

    private func validate(_ response: URLResponse, data: Data, service: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: service, status: code, body: body)
        }
    }
}

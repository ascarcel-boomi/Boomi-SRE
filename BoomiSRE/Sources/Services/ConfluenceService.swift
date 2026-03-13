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

    /// Fetch all accessible spaces via GET /wiki/rest/api/space (paginated).
    func fetchSpaces(
        baseURL: String, email: String, apiToken: String
    ) async throws -> [ConfluenceSpaceSummary] {
        var all: [ConfluenceSpaceSummary] = []
        var start = 0
        let limit = 50

        while true {
            var components = URLComponents(string: "\(baseURL.trimmingSlash)/wiki/rest/api/space")!
            components.queryItems = [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "type", value: "global"),
            ]
            var request = URLRequest(url: components.url!, timeoutInterval: 30)
            request.addBasicAuth(email: email, token: apiToken)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw ServiceError.httpError(service: "Confluence", status: code, body: body)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { break }

            for r in results {
                guard let key = r["key"] as? String,
                      let name = r["name"] as? String else { continue }
                let id = (r["id"] as? Int).map(String.init) ?? key
                all.append(ConfluenceSpaceSummary(id: id, key: key, name: name))
            }

            let size = (json["size"] as? Int) ?? results.count
            let totalSize = (json["totalSize"] as? Int) ?? size
            start += size
            if start >= totalSize || results.count < limit { break }
        }
        return all
    }
    // MARK: - Pages

    struct ConfluencePage: Identifiable, Hashable, Equatable, Sendable {
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: ConfluencePage, rhs: ConfluencePage) -> Bool { lhs.id == rhs.id }
        let id: String
        let title: String
        let spaceKey: String
        let version: Int
        let authorName: String
        let lastModified: String
        let url: String
    }

    /// List pages in a space (v1 API).
    func listPages(
        baseURL: String, email: String, apiToken: String,
        spaceKey: String, limit: Int = 50
    ) async throws -> [ConfluencePage] {
        var all: [ConfluencePage] = []
        var start = 0
        while true {
            var components = URLComponents(string: "\(baseURL.trimmingSlash)/wiki/rest/api/content")!
            components.queryItems = [
                URLQueryItem(name: "spaceKey", value: spaceKey),
                URLQueryItem(name: "type", value: "page"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "expand", value: "version,history.lastUpdated"),
                URLQueryItem(name: "orderby", value: "history.lastUpdated desc"),
            ]
            var request = URLRequest(url: components.url!, timeoutInterval: 20)
            request.addBasicAuth(email: email, token: apiToken)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw ServiceError.httpError(service: "Confluence", status: code, body: body)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]], !results.isEmpty else { break }

            for r in results {
                guard let id = r["id"] as? String, let title = r["title"] as? String else { continue }
                let space = (r["space"] as? [String: Any])?["key"] as? String ?? spaceKey
                let version = (r["version"] as? [String: Any])?["number"] as? Int ?? 1
                let history = (r["history"] as? [String: Any]) ?? [:]
                let lastUpdated = history["lastUpdated"] as? [String: Any] ?? [:]
                let author = (lastUpdated["by"] as? [String: Any])?["displayName"] as? String ?? "?"
                let when = String((lastUpdated["when"] as? String ?? "").prefix(10))
                let links = r["_links"] as? [String: Any] ?? [:]
                let webUI = links["webui"] as? String ?? ""
                all.append(ConfluencePage(id: id, title: title, spaceKey: space, version: version,
                                          authorName: author, lastModified: when,
                                          url: "\(baseURL.trimmingSlash)/wiki\(webUI)"))
            }
            let size = (json["size"] as? Int) ?? results.count
            let totalSize = (json["limit"] as? Int).map { _ in
                (json["totalSize"] as? Int) ?? (start + size + 1)
            } ?? (start + size)
            start += size
            if start >= totalSize || results.count < limit { break }
        }
        return all
    }

    /// Fetch page body as HTML (tries export_view first, then storage fallback).
    func getPageContent(
        baseURL: String, email: String, apiToken: String, pageId: String
    ) async throws -> String {
        var components = URLComponents(string: "\(baseURL.trimmingSlash)/wiki/rest/api/content/\(pageId)")!
        components.queryItems = [URLQueryItem(name: "expand", value: "body.export_view,body.storage")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Confluence", status: code, body: body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? [String: Any] else { return "" }

        // Try export_view first (rendered HTML)
        if let exportView = body["export_view"] as? [String: Any],
           let value = exportView["value"] as? String, !value.isEmpty {
            return value  // Return raw HTML for WebView rendering
        }
        // Fall back to storage (Confluence XML/HTML)
        if let storage = body["storage"] as? [String: Any],
           let value = storage["value"] as? String, !value.isEmpty {
            return value
        }
        return "(Page content could not be loaded. Try opening in Confluence.)"
    }

    /// Fetch page body as plain text (for AI analysis).
    func getPageContentPlainText(
        baseURL: String, email: String, apiToken: String, pageId: String
    ) async throws -> String {
        let html = try await getPageContent(baseURL: baseURL, email: email, apiToken: apiToken, pageId: pageId)
        return stripHTML(html)
    }

    /// Fetch recently modified pages (for notification polling).
    func recentlyModifiedPages(
        baseURL: String, email: String, apiToken: String, limit: Int = 20
    ) async throws -> [ConfluencePage] {
        var components = URLComponents(string: "\(baseURL.trimmingSlash)/wiki/rest/api/search")!
        components.queryItems = [
            URLQueryItem(name: "cql", value: "type=page ORDER BY lastmodified DESC"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "expand", value: "version,history.lastUpdated"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Confluence", status: code, body: body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            let content = r["content"] as? [String: Any] ?? r
            guard let id = content["id"] as? String, let title = content["title"] as? String else { return nil }
            let space = ((content["space"] as? [String: Any])?["key"] as? String) ?? "?"
            let version = (content["version"] as? [String: Any])?["number"] as? Int ?? 1
            let lastUpdated = r["lastModified"] as? String ?? ""
            let authorName = (r["friendlyLastModified"] as? String) ?? ""
            let links = content["_links"] as? [String: Any] ?? [:]
            let webUI = links["webui"] as? String ?? ""
            return ConfluencePage(id: id, title: title, spaceKey: space, version: version,
                                  authorName: authorName, lastModified: lastUpdated,
                                  url: "\(baseURL.trimmingSlash)/wiki\(webUI)")
        }
    }

    /// Search Confluence pages using CQL.
    func searchPages(
        baseURL: String, email: String, apiToken: String, query: String, limit: Int = 20
    ) async throws -> [ConfluencePage] {
        let cql = "type=page AND text~\"\(query)\""
        var components = URLComponents(string: "\(baseURL.trimmingSlash)/wiki/rest/api/search")!
        components.queryItems = [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "expand", value: "version"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(service: "Confluence", status: code, body: body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            let content = r["content"] as? [String: Any] ?? r
            guard let id = content["id"] as? String, let title = content["title"] as? String else { return nil }
            let space = ((content["space"] as? [String: Any])?["key"] as? String) ?? "?"
            let links = content["_links"] as? [String: Any] ?? [:]
            let webUI = links["webui"] as? String ?? ""
            return ConfluencePage(id: id, title: title, spaceKey: space, version: 1,
                                  authorName: "", lastModified: "",
                                  url: "\(baseURL.trimmingSlash)/wiki\(webUI)")
        }
    }

    // MARK: - HTML Stripper

    private func stripHTML(_ html: String) -> String {
        // Remove script/style blocks
        var result = html
        for tag in ["script", "style"] {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Replace block tags with newlines
        for tag in ["p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "tr", "td"] {
            result = result.replacingOccurrences(of: "<\(tag)[^>]*>", with: "\n", options: .regularExpression)
            result = result.replacingOccurrences(of: "</\(tag)>", with: "\n", options: .regularExpression)
        }
        // Strip remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse whitespace
        result = result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return result
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

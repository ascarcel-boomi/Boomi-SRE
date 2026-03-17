import Foundation

/// Native Google Workspace API client.
/// Reads OAuth credentials from the MCP credential file and refreshes tokens as needed.
actor GoogleService {

    private var accessToken: String = ""
    private var tokenExpiry: Date = .distantPast

    // MARK: - Auth

    func checkAuth(credentials: GoogleCredentials) async throws -> String {
        try await refreshTokenIfNeeded(credentials: credentials)
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Google")
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            return email
        }
        return "Authenticated"
    }

    // MARK: - Gmail: List

    func listMessages(
        credentials: GoogleCredentials, query: String = "is:unread", maxResults: Int = 30
    ) async throws -> [GmailMessage] {
        try await refreshTokenIfNeeded(credentials: credentials)
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Gmail")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return [] }

        var result: [GmailMessage] = []
        for msg in messages.prefix(maxResults) {
            guard let id = msg["id"] as? String else { continue }
            if let detail = try? await fetchMessageMetadata(id: id) {
                result.append(detail)
            }
        }
        return result
    }

    private func fetchMessageMetadata(id: String) async throws -> GmailMessage? {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date&metadataHeaders=Cc")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Gmail")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseMessage(json, id: id)
    }

    // MARK: - Gmail: Full message body

    func getFullMessage(credentials: GoogleCredentials, id: String) async throws -> GmailFullMessage {
        try await refreshTokenIfNeeded(credentials: credentials)
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Gmail")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = parseMessage(json, id: id) else {
            throw GoogleError.httpError(service: "Gmail", status: 0, body: "Failed to parse message")
        }

        let body = extractBody(from: json)
        return GmailFullMessage(message: msg, bodyHTML: body.html, bodyText: body.text)
    }

    private func parseMessage(_ json: [String: Any], id: String) -> GmailMessage? {
        let snippet = json["snippet"] as? String ?? ""
        let labelIds = json["labelIds"] as? [String] ?? []
        let internalDate = json["internalDate"] as? String ?? ""
        let threadId = json["threadId"] as? String ?? ""
        let isUnread = labelIds.contains("UNREAD")
        let isStarred = labelIds.contains("STARRED")

        var subject = "", from = "", to = "", cc = "", dateStr = ""
        if let payload = json["payload"] as? [String: Any],
           let headers = payload["headers"] as? [[String: Any]] {
            for h in headers {
                let name = h["name"] as? String ?? ""
                let value = h["value"] as? String ?? ""
                switch name {
                case "Subject": subject = value
                case "From": from = value
                case "To": to = value
                case "Cc": cc = value
                case "Date": dateStr = value
                default: break
                }
            }
        }

        let date: Date
        if let ms = Int64(internalDate) {
            date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        } else {
            date = Date()
        }

        return GmailMessage(
            id: id, threadId: threadId, subject: subject,
            from: from, to: to, cc: cc,
            snippet: snippet, date: date, dateString: dateStr,
            isUnread: isUnread, isStarred: isStarred, labelIds: labelIds
        )
    }

    /// Extract text and HTML body from the message payload (handles multipart).
    private func extractBody(from json: [String: Any]) -> (html: String, text: String) {
        guard let payload = json["payload"] as? [String: Any] else { return ("", "") }
        var html = ""
        var text = ""
        extractParts(payload, html: &html, text: &text)
        return (html, text)
    }

    private func extractParts(_ part: [String: Any], html: inout String, text: inout String) {
        let mimeType = part["mimeType"] as? String ?? ""
        if let body = part["body"] as? [String: Any], let data = body["data"] as? String, !data.isEmpty {
            if let decoded = base64URLDecode(data) {
                if mimeType == "text/html" { html = decoded }
                else if mimeType == "text/plain" { text = decoded }
            }
        }
        if let parts = part["parts"] as? [[String: Any]] {
            for p in parts { extractParts(p, html: &html, text: &text) }
        }
    }

    private func base64URLDecode(_ input: String) -> String? {
        var s = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Gmail: Actions

    func markAsRead(credentials: GoogleCredentials, id: String) async throws {
        try await refreshTokenIfNeeded(credentials: credentials)
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)/modify")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["UNREAD"]])
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Gmail")
    }

    func archiveMessage(credentials: GoogleCredentials, id: String) async throws {
        try await refreshTokenIfNeeded(credentials: credentials)
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)/modify")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["INBOX"]])
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Gmail")
    }

    func toggleStar(credentials: GoogleCredentials, id: String, starred: Bool) async throws {
        try await refreshTokenIfNeeded(credentials: credentials)
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)/modify")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = starred
            ? ["addLabelIds": ["STARRED"]]
            : ["removeLabelIds": ["STARRED"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Gmail")
    }

    // MARK: - Calendar

    func listEvents(
        credentials: GoogleCredentials, maxResults: Int = 50, daysAhead: Int = 7
    ) async throws -> [CalendarEvent] {
        try await refreshTokenIfNeeded(credentials: credentials)
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: daysAhead, to: now)!
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: fmt.string(from: now)),
            URLQueryItem(name: "timeMax", value: fmt.string(from: future)),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Calendar")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let summary = item["summary"] as? String else { return nil }
            let status = item["status"] as? String ?? ""
            let location = item["location"] as? String ?? ""
            let description = item["description"] as? String ?? ""
            let htmlLink = item["htmlLink"] as? String ?? ""
            let startObj = item["start"] as? [String: Any] ?? [:]
            let startDateTime = startObj["dateTime"] as? String ?? startObj["date"] as? String ?? ""
            let isAllDay = startObj["dateTime"] == nil
            let endObj = item["end"] as? [String: Any] ?? [:]
            let endDateTime = endObj["dateTime"] as? String ?? endObj["date"] as? String ?? ""
            let attendees = (item["attendees"] as? [[String: Any]])?.compactMap { $0["email"] as? String } ?? []
            let organizer = (item["organizer"] as? [String: Any])?["email"] as? String ?? ""
            let hangoutLink = item["hangoutLink"] as? String ?? ""

            return CalendarEvent(
                id: id, summary: summary, status: status,
                location: location, description: description,
                startDateTime: startDateTime, endDateTime: endDateTime,
                isAllDay: isAllDay, htmlLink: htmlLink,
                organizer: organizer, attendees: attendees,
                hangoutLink: hangoutLink
            )
        }
    }

    // MARK: - Google Chat

    /// Fetch Chat spaces. Uses a simple list without filter to avoid API issues.
    func listChatSpaces(credentials: GoogleCredentials) async throws -> [ChatSpace] {
        try await refreshTokenIfNeeded(credentials: credentials)

        // Simple endpoint — no filter parameter which can cause 400 errors
        var components = URLComponents(string: "https://chat.googleapis.com/v1/spaces")!
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: "100"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Google Chat")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spaces = json["spaces"] as? [[String: Any]] else { return [] }

        return spaces.compactMap { s in
            guard let name = s["name"] as? String else { return nil }
            let displayName = s["displayName"] as? String ?? name
            let spaceType = s["spaceType"] as? String ?? ""
            let singleUserBotDm = s["singleUserBotDm"] as? Bool ?? false
            // Skip bot DMs
            if singleUserBotDm { return nil }
            return ChatSpace(name: name, displayName: displayName, spaceType: spaceType, singleUserBotDm: singleUserBotDm)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func listChatMessages(
        credentials: GoogleCredentials, spaceName: String, maxResults: Int = 25
    ) async throws -> [ChatMessage] {
        try await refreshTokenIfNeeded(credentials: credentials)

        // Note: orderBy is not supported on all Chat API versions; omit it to avoid errors
        var components = URLComponents(string: "https://chat.googleapis.com/v1/\(spaceName)/messages")!
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: String(maxResults)),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        try validateHTTP(response, data: data, service: "Google Chat")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return [] }

        return messages.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            let text = m["text"] as? String ?? ""
            if text.isEmpty { return nil }  // skip empty/system messages
            let senderName = (m["sender"] as? [String: Any])?["displayName"] as? String ?? ""
            let senderType = (m["sender"] as? [String: Any])?["type"] as? String ?? ""
            let createTime = m["createTime"] as? String ?? ""
            return ChatMessage(name: name, text: text, senderName: senderName, senderType: senderType, createTime: createTime)
        }
    }

    // MARK: - Token Refresh

    private func refreshTokenIfNeeded(credentials: GoogleCredentials) async throws {
        if !accessToken.isEmpty && tokenExpiry > Date().addingTimeInterval(60) { return }

        guard !credentials.refreshToken.isEmpty else { throw GoogleError.noRefreshToken }

        var request = URLRequest(url: URL(string: credentials.tokenURI)!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(credentials.clientId)&client_secret=\(credentials.clientSecret)&refresh_token=\(credentials.refreshToken)&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleError.tokenRefreshFailed(body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["access_token"] as? String else {
            throw GoogleError.tokenRefreshFailed("Invalid response")
        }
        accessToken = newToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(json["expires_in"] as? Int ?? 3600))
    }

    private func validateHTTP(_ response: URLResponse, data: Data, service: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GoogleError.httpError(service: service, status: code, body: body)
        }
    }
}

// MARK: - Credentials Model

struct GoogleCredentials: Codable {
    let token: String?
    let refreshToken: String
    let tokenURI: String
    let clientId: String
    let clientSecret: String
    let scopes: [String]?
    let expiry: String?

    enum CodingKeys: String, CodingKey {
        case token
        case refreshToken = "refresh_token"
        case tokenURI = "token_uri"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case scopes
        case expiry
    }

    static func load(from url: URL) -> GoogleCredentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GoogleCredentials.self, from: data)
    }

    static func discover() -> (credentials: GoogleCredentials, email: String, source: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mcpDir = home.appendingPathComponent(".google_workspace_mcp/credentials")
        if let files = try? FileManager.default.contentsOfDirectory(at: mcpDir, includingPropertiesForKeys: nil),
           let jsonFile = files.first(where: { $0.pathExtension == "json" }),
           let creds = load(from: jsonFile) {
            let email = jsonFile.deletingPathExtension().lastPathComponent
            return (creds, email, "~/.google_workspace_mcp/credentials/")
        }
        let amazonqDir = home.appendingPathComponent(".amazonq/mcp_credentials")
        if let files = try? FileManager.default.contentsOfDirectory(at: amazonqDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.contains("google") || file.lastPathComponent.contains("gmail") {
                if file.pathExtension == "json", let creds = load(from: file) {
                    return (creds, file.deletingPathExtension().lastPathComponent, "~/.amazonq/mcp_credentials/")
                }
            }
        }
        return nil
    }
}

// MARK: - API Models

struct GmailMessage: Identifiable {
    let id: String
    let threadId: String
    let subject: String
    let from: String
    let to: String
    let cc: String
    let snippet: String
    let date: Date
    let dateString: String
    let isUnread: Bool
    let isStarred: Bool
    let labelIds: [String]

    /// Extract just the sender name from "Name <email>" format.
    var senderName: String {
        if let angle = from.firstIndex(of: "<") {
            let name = from[from.startIndex..<angle].trimmingCharacters(in: .whitespaces)
            return name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return from
    }

    var senderEmail: String {
        if let start = from.firstIndex(of: "<"), let end = from.firstIndex(of: ">") {
            return String(from[from.index(after: start)..<end])
        }
        return from
    }
}

struct GmailFullMessage {
    let message: GmailMessage
    let bodyHTML: String
    let bodyText: String
}

struct CalendarEvent: Identifiable {
    let id: String
    let summary: String
    let status: String
    let location: String
    let description: String
    let startDateTime: String
    let endDateTime: String
    let isAllDay: Bool
    let htmlLink: String
    let organizer: String
    let attendees: [String]
    let hangoutLink: String
}

struct ChatSpace: Identifiable, Hashable {
    var id: String { name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: ChatSpace, rhs: ChatSpace) -> Bool { lhs.name == rhs.name }
    let name: String
    let displayName: String
    let spaceType: String
    let singleUserBotDm: Bool
}

struct ChatMessage: Identifiable {
    var id: String { name }
    let name: String
    let text: String
    let senderName: String
    let senderType: String
    let createTime: String
}

enum GoogleError: LocalizedError {
    case noRefreshToken
    case tokenRefreshFailed(String)
    case httpError(service: String, status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token found. Set up Google credentials in Settings."
        case .tokenRefreshFailed(let detail):
            if detail.contains("invalid_grant") {
                return "Google refresh token expired. Re-authenticate via MCP setup or Settings."
            }
            return "Token refresh failed: \(String(detail.prefix(300)))"
        case .httpError(let service, let status, let body):
            if status == 403 && body.contains("not been used") {
                let api = service == "Google Chat" ? "Google Chat API" : "\(service) API"
                return "\(api) is not enabled in the Google Cloud project. Enable it at console.cloud.google.com → APIs & Services."
            }
            return "\(service) HTTP \(status): \(String(body.prefix(300)))"
        }
    }
}

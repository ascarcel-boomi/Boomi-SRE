import Foundation

/// Calls the Anthropic Messages API to analyze Jira tickets and power the AI Copilot.
actor ClaudeService {
    private let model = "claude-sonnet-4-6"
    private let maxTokens = 1024

    // MARK: - API Key Discovery

    /// Auto-discover the API key from known locations.
    nonisolated func discoverAPIKey() -> String? {
        // 1. App's saved secrets
        if let key = KeychainHelper.load(key: "anthropic-api-key"), !key.isEmpty {
            return key
        }

        // 2. Environment variable
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return key
        }

        // 3. macOS Keychain (Claude Code stores it here)
        if let key = readFromMacKeychain(service: "Claude Code") {
            return key
        }

        // 4. Shell profile files
        for file in ["~/.zshrc", "~/.bashrc", "~/.bash_profile"] {
            let path = NSString(string: file).expandingTildeInPath
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                for line in content.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("#") { continue }
                    if trimmed.contains("ANTHROPIC_API_KEY") && trimmed.contains("=") {
                        let parts = trimmed.components(separatedBy: "=")
                        if parts.count >= 2 {
                            var value = parts.dropFirst().joined(separator: "=")
                                .trimmingCharacters(in: .whitespaces)
                            value = value.replacingOccurrences(of: "\"", with: "")
                                .replacingOccurrences(of: "'", with: "")
                            if value.hasPrefix("sk-ant-") { return value }
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Read a password from the macOS login keychain by service name.
    private nonisolated func readFromMacKeychain(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (key?.hasPrefix("sk-ant-") == true) ? key : nil
        } catch {
            return nil
        }
    }

    // MARK: - Ticket Analysis (existing)

    func analyzeTicket(
        apiKey: String,
        ticketDetail: TicketDetail,
        devInfo: JiraDevInfo? = nil
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let ticketContext = buildTicketContext(ticketDetail, devInfo: devInfo)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": """
                You are an SRE assistant helping an engineer manage their Jira tickets efficiently. \
                Given a ticket's full details (including linked pull requests and commits if any), provide a concise analysis with: \
                1. **Current Status** — one sentence summary of where this ticket stands \
                2. **Recommended Next Steps** — 2-4 specific, actionable steps the engineer should take right now \
                3. **Code Changes** — if there are linked PRs or commits, summarize their status and whether they need review/merge \
                4. **Blockers or Risks** — any potential issues or dependencies to watch out for \
                5. **Priority Assessment** — whether the current priority seems appropriate given the context \
                Keep it brief and actionable. Use bullet points. Don't repeat information the engineer already knows. \
                If there are no linked PRs or commits, skip the Code Changes section.
                """,
            "messages": [
                ["role": "user", "content": ticketContext]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ClaudeError.apiError(status: code, body: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeError.invalidResponse
        }

        return text
    }

    // MARK: - Simple Multi-turn Chat (existing)

    /// Multi-turn chat with full conversation history (no tools).
    func chat(
        messages: [(role: String, content: String)],
        systemPrompt: String,
        maxTokens: Int = 4096,
        modelOverride: String? = nil
    ) async throws -> String {
        guard let apiKey = discoverAPIKey() else {
            throw ClaudeError.noAPIKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messagesJSON = messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": modelOverride ?? model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messagesJSON
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ClaudeError.apiError(status: code, body: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeError.invalidResponse
        }

        return text
    }

    // MARK: - Tool-Use Chat (new)

    /// Tool-use capable chat. Sends tool definitions alongside messages; returns either a
    /// final text response or a request to invoke one or more tools.
    ///
    /// - Parameters:
    ///   - apiHistory: Full conversation in Anthropic API format. Each element is a dict
    ///     with "role" and "content"; content may be a `String` or `[[String: Any]]`.
    ///   - tools: Tool definitions array (see `JiraTools.definitions`).
    ///   - systemPrompt: System-level instructions.
    ///   - maxTokens: Max tokens to generate (default 4096).
    func chatWithTools(
        apiHistory: [[String: Any]],
        tools: [[String: Any]],
        systemPrompt: String,
        maxTokens: Int = 4096
    ) async throws -> ClaudeToolResponse {
        guard let apiKey = discoverAPIKey() else { throw ClaudeError.noAPIKey }
        return try await withExponentialBackoff {
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            var request = URLRequest(url: url, timeoutInterval: 90)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": self.model,
                "max_tokens": maxTokens,
                "system": systemPrompt,
                "tools": tools,
                "messages": apiHistory
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                throw ClaudeError.rateLimited
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw ClaudeError.apiError(status: code, body: errorBody)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ClaudeError.invalidResponse
            }

            let contentBlocks = json["content"] as? [[String: Any]] ?? []
            var textParts: [String] = []
            var toolUses: [ClaudeToolUse] = []

            for block in contentBlocks {
                switch block["type"] as? String ?? "" {
                case "text":
                    if let t = block["text"] as? String, !t.isEmpty { textParts.append(t) }
                case "tool_use":
                    if let id   = block["id"]    as? String,
                       let name = block["name"]  as? String,
                       let inp  = block["input"] as? [String: Any] {
                        toolUses.append(ClaudeToolUse(id: id, name: name, input: inp))
                    }
                default: break
                }
            }

            let combinedText = textParts.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !toolUses.isEmpty {
                return .toolUse(
                    textBefore: combinedText.isEmpty ? nil : combinedText,
                    tools: toolUses,
                    rawAssistantBlocks: contentBlocks
                )
            } else {
                return .finalText(combinedText)
            }
        }
    }

    // MARK: - Retry Helpers

    /// Exponential back-off wrapper; retries only on HTTP 429 rate-limit errors.
    private func withExponentialBackoff<T>(
        maxAttempts: Int = 4,
        _ operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch ClaudeError.rateLimited {
                let delaySecs = Double(1 << attempt)  // 1 s, 2 s, 4 s, 8 s
                try await Task.sleep(nanoseconds: UInt64(delaySecs * 1_000_000_000))
                lastError = ClaudeError.rateLimited
            } catch {
                throw error  // non-retryable — propagate immediately
            }
        }
        throw lastError ?? ClaudeError.rateLimited
    }

    // MARK: - Ticket Context Builder (used by analyzeTicket)

    private func buildTicketContext(_ d: TicketDetail, devInfo: JiraDevInfo? = nil) -> String {
        var parts: [String] = []
        parts.append("Ticket: \(d.key)")
        parts.append("Summary: \(d.summary)")
        parts.append("Type: \(d.issueType)")
        parts.append("Status: \(d.status) (category: \(d.statusCategory))")
        parts.append("Priority: \(d.priority)")
        parts.append("Assignee: \(d.assignee)")
        parts.append("Reporter: \(d.reporter)")
        parts.append("Created: \(d.created)")
        parts.append("Updated: \(d.updated)")
        if !d.startDate.isEmpty { parts.append("Start Date: \(d.startDate)") }
        if !d.dueDate.isEmpty { parts.append("Due Date: \(d.dueDate)") }
        if let sprint = d.sprint { parts.append("Sprint: \(sprint.name) (\(sprint.state))") }
        if !d.labels.isEmpty { parts.append("Labels: \(d.labels.joined(separator: ", "))") }
        if !d.parentKey.isEmpty { parts.append("Parent: \(d.parentKey) — \(d.parentSummary)") }

        if !d.description.isEmpty {
            parts.append("\nDescription:\n\(d.description.prefix(1500))")
        }

        if !d.subtasks.isEmpty {
            parts.append("\nSubtasks:")
            for st in d.subtasks {
                parts.append("  \(st.key): \(st.summary) [\(st.status)]")
            }
        }

        if !d.comments.isEmpty {
            parts.append("\nRecent Comments (last 5):")
            for c in d.comments.suffix(5) {
                parts.append("  [\(c.created)] \(c.authorName): \(c.bodyText.prefix(300))")
            }
        }

        if !d.history.isEmpty {
            parts.append("\nRecent History (last 10 changes):")
            for h in d.history.prefix(10) {
                parts.append("  [\(h.date)] \(h.author): \(h.field): \(h.from) → \(h.to)")
            }
        }

        if let dev = devInfo {
            if !dev.pullRequests.isEmpty {
                parts.append("\nLinked Pull Requests:")
                for pr in dev.pullRequests {
                    parts.append("  [\(pr.status)] \(pr.name) by \(pr.author)")
                    parts.append("    \(pr.sourceBranch) → \(pr.destBranch)")
                    parts.append("    URL: \(pr.url)")
                }
            }
            if !dev.commits.isEmpty {
                parts.append("\nLinked Commits:")
                for c in dev.commits.prefix(10) {
                    parts.append("  [\(c.hash)] \(c.message.prefix(100)) by \(c.author) (\(c.date))")
                }
            }
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case apiError(status: Int, body: String)
    case invalidResponse
    case noAPIKey
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .apiError(let status, let body):
            return "Claude API error (HTTP \(status)):\n\(body.prefix(300))"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .noAPIKey:
            return "No Anthropic API key found. The key is auto-discovered from the macOS Keychain (Claude Code), ANTHROPIC_API_KEY environment variable, or ~/.zshrc."
        case .rateLimited:
            return "Claude API rate limit hit — retrying with exponential backoff."
        }
    }
}

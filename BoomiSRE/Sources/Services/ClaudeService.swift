import Foundation

/// Calls the Anthropic Messages API — or falls back to the `claude` CLI (Claude Code) —
/// to analyze Jira tickets and power the AI Copilot.
///
/// Auth precedence:
/// 1. API key (Keychain → env var → macOS Keychain → shell profile)
/// 2. Claude CLI (`claude -p`) — works with Enterprise licenses and API keys alike
actor ClaudeService {
    private let model = "claude-sonnet-4-6"
    private let maxTokens = 1024

    // MARK: - Auth Method

    enum AuthMethod: Sendable {
        case apiKey(String)
        case claudeCLI(path: String)
    }

    /// Returns the best available auth method, or nil if nothing is configured.
    nonisolated func discoverAuthMethod() -> AuthMethod? {
        if let key = discoverAPIKey() { return .apiKey(key) }
        if let path = findClaudeCLI() { return .claudeCLI(path: path) }
        return nil
    }

    /// Quick check: is *any* AI backend available (API key or CLI)?
    nonisolated var isAIAvailable: Bool { discoverAuthMethod() != nil }

    // MARK: - API Key Discovery

    /// Auto-discover an API key from known locations.
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

    // MARK: - Claude CLI Discovery

    /// Find the `claude` CLI binary on the system.
    private nonisolated func findClaudeCLI() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }

        // Fallback: `which claude`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        } catch {}

        return nil
    }

    // MARK: - Claude CLI Runner

    /// Run `claude -p` with the given prompt, returning the text response.
    /// Enforces a timeout (default 120s) to prevent indefinite hangs.
    private func runClaudeCLI(
        cliPath: String,
        prompt: String,
        systemPrompt: String? = nil,
        modelOverride: String? = nil,
        timeout: TimeInterval = 300
    ) async throws -> String {
        var fullPrompt = ""
        if let sys = systemPrompt, !sys.isEmpty {
            fullPrompt += "<system-instructions>\n\(sys)\n</system-instructions>\n\n"
        }
        fullPrompt += prompt

        var args = ["-p", "--output-format", "text", "--max-turns", "1"]
        if let model = modelOverride {
            args += ["--model", model]
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: cliPath)
                    process.arguments = args

                    // Inherit current environment + ensure Zscaler/corporate SSL certs are trusted
                    var env = ProcessInfo.processInfo.environment
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let zscalerCert = "\(home)/zscaler-root.pem"
                    if env["NODE_EXTRA_CA_CERTS"] == nil,
                       FileManager.default.fileExists(atPath: zscalerCert) {
                        env["NODE_EXTRA_CA_CERTS"] = zscalerCert
                    }
                    process.environment = env

                    let inPipe = Pipe()
                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardInput = inPipe
                    process.standardOutput = outPipe
                    process.standardError = errPipe

                    try process.run()

                    // Write prompt via stdin (in background to avoid pipe-buffer deadlock)
                    if let data = fullPrompt.data(using: .utf8) {
                        inPipe.fileHandleForWriting.write(data)
                    }
                    inPipe.fileHandleForWriting.closeFile()

                    // Enforce timeout: kill the process if it runs too long
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now() + timeout)
                    timer.setEventHandler {
                        if process.isRunning { process.terminate() }
                    }
                    timer.resume()

                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timer.cancel()

                    guard process.terminationStatus == 0 else {
                        if process.terminationStatus == 15 || process.terminationStatus == -1 {
                            // SIGTERM from our timeout
                            continuation.resume(throwing: ClaudeError.cliError("Claude CLI timed out after \(Int(timeout))s. Try a smaller prompt or check your network."))
                            return
                        }
                        let stderrStr = String(data: errData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let stdoutStr = String(data: outData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let errStr = stderrStr.isEmpty
                            ? (stdoutStr.isEmpty ? "Claude CLI exited with code \(process.terminationStatus)" : stdoutStr)
                            : stderrStr
                        continuation.resume(throwing: ClaudeError.cliError(String(errStr.prefix(500))))
                        return
                    }

                    let output = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !output.isEmpty else {
                        continuation.resume(throwing: ClaudeError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Ticket Analysis

    func analyzeTicket(
        ticketDetail: TicketDetail,
        devInfo: JiraDevInfo? = nil
    ) async throws -> String {
        guard let auth = discoverAuthMethod() else { throw ClaudeError.noAuth }

        let ticketContext = buildTicketContext(ticketDetail, devInfo: devInfo)
        let systemPrompt = """
            You are an SRE assistant helping an engineer manage their Jira tickets efficiently. \
            Given a ticket's full details (including linked pull requests and commits if any), provide a concise analysis with: \
            1. **Current Status** — one sentence summary of where this ticket stands \
            2. **Recommended Next Steps** — 2-4 specific, actionable steps the engineer should take right now \
            3. **Code Changes** — if there are linked PRs or commits, summarize their status and whether they need review/merge \
            4. **Blockers or Risks** — any potential issues or dependencies to watch out for \
            5. **Priority Assessment** — whether the current priority seems appropriate given the context \
            Keep it brief and actionable. Use bullet points. Don't repeat information the engineer already knows. \
            If there are no linked PRs or commits, skip the Code Changes section.
            """

        switch auth {
        case .apiKey(let key):
            return try await analyzeTicketViaAPI(apiKey: key, systemPrompt: systemPrompt, ticketContext: ticketContext)
        case .claudeCLI(let path):
            return try await runClaudeCLI(cliPath: path, prompt: ticketContext, systemPrompt: systemPrompt)
        }
    }

    private func analyzeTicketViaAPI(apiKey: String, systemPrompt: String, ticketContext: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClaudeError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": ticketContext]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
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

    // MARK: - Simple Multi-turn Chat

    func chat(
        messages: [(role: String, content: String)],
        systemPrompt: String,
        maxTokens: Int = 4096,
        modelOverride: String? = nil
    ) async throws -> String {
        guard let auth = discoverAuthMethod() else { throw ClaudeError.noAuth }

        switch auth {
        case .apiKey(let key):
            return try await chatViaAPI(apiKey: key, messages: messages, systemPrompt: systemPrompt, maxTokens: maxTokens, modelOverride: modelOverride)
        case .claudeCLI(let path):
            return try await chatViaCLI(cliPath: path, messages: messages, systemPrompt: systemPrompt, modelOverride: modelOverride)
        }
    }

    private func chatViaAPI(
        apiKey: String,
        messages: [(role: String, content: String)],
        systemPrompt: String,
        maxTokens: Int,
        modelOverride: String?
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClaudeError.invalidResponse
        }
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

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
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

    private func chatViaCLI(
        cliPath: String,
        messages: [(role: String, content: String)],
        systemPrompt: String,
        modelOverride: String?
    ) async throws -> String {
        // Build a single prompt from the conversation history
        var prompt = ""
        if messages.count == 1 && messages[0].role == "user" {
            prompt = messages[0].content
        } else {
            for msg in messages {
                let label = msg.role == "user" ? "User" : "Assistant"
                prompt += "\(label): \(msg.content)\n\n"
            }
        }

        return try await runClaudeCLI(cliPath: cliPath, prompt: prompt, systemPrompt: systemPrompt, modelOverride: modelOverride)
    }

    // MARK: - Tool-Use Chat

    /// Tool-use capable chat. Requires an API key — Claude CLI does not support custom tool definitions.
    func chatWithTools(
        apiHistory: [[String: Any]],
        tools: [[String: Any]],
        systemPrompt: String,
        maxTokens: Int = 4096
    ) async throws -> ClaudeToolResponse {
        guard let auth = discoverAuthMethod() else { throw ClaudeError.noAuth }
        guard case .apiKey(let apiKey) = auth else {
            throw ClaudeError.cliNoToolSupport
        }
        return try await withExponentialBackoff {
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                throw ClaudeError.invalidResponse
            }
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

            let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)

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

    // MARK: - Ticket Context Builder

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
    case noAuth
    case rateLimited
    case cliError(String)
    case cliNoToolSupport

    var errorDescription: String? {
        switch self {
        case .apiError(let status, let body):
            return "Claude API error (HTTP \(status)):\n\(body.prefix(300))"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .noAuth:
            return "No Claude AI backend found. Install Claude Code (claude CLI) or set an ANTHROPIC_API_KEY environment variable."
        case .rateLimited:
            return "Claude API rate limit hit — retrying with exponential backoff."
        case .cliError(let msg):
            return "Claude CLI error: \(msg.prefix(500))"
        case .cliNoToolSupport:
            return "Tool-use (Copilot) requires an Anthropic API key. The Claude CLI backend supports analysis and chat but not custom tool definitions. Set ANTHROPIC_API_KEY or add a key in Settings to enable Copilot."
        }
    }
}

import Foundation

/// Scans known credential locations across the user's home directory and imports tokens.
struct CredentialDiscovery {
    struct DiscoveredCredentials {
        var jiraToken: String?
        var confluenceToken: String?
        var bitbucketToken: String?
        var bitbucketUsername: String?
        var bitbucketURL: String?
        var githubToken: String?
        var jenkinsURL: String?
        var jenkinsUsername: String?
        var jenkinsToken: String?
        var grafanaURL: String?
        var grafanaToken: String?
        var anthropicAPIKey: String?
        var atlassianEmail: String?
        var atlassianBaseURL: String?
        var sources: [String]
    }

    /// Known directories to scan for credential files.
    private static let searchDirs = [
        ".amazonq/mcp_credentials",
        ".kiro/mcp_credentials",
        ".aws/amazonq",
        ".amazonq",
        ".config",
        ".google_workspace_mcp/credentials",
    ]

    /// Known token patterns to search for in .env and .txt files.
    private static let tokenKeys: Set<String> = [
        "JIRA_API_TOKEN", "CONFLUENCE_API_TOKEN", "BITBUCKET_API_TOKEN",
        "BITBUCKET_USERNAME", "BITBUCKET_URL",
        "ATLASSIAN_API_TOKEN", "ATLASSIAN_URL", "ATLASSIAN_USERNAME",
        "JIRA_URL", "CONFLUENCE_URL",
        "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ANTHROPIC_API_KEY",
        "JENKINS_URL", "JENKINS_USERNAME", "JENKINS_TOKEN", "JENKINS_PASSWORD",
        "GRAFANA_URL", "GRAFANA_API_KEY", "GRAFANA_TOKEN",
        "GMAIL_EMAIL",
    ]

    /// Scan all known credential locations and return what was found.
    static func discover() -> DiscoveredCredentials {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result = DiscoveredCredentials(sources: [])
        var allEnvVars: [String: (value: String, source: String)] = [:]

        // Scan known directories for .env, .txt, and credential files
        for dir in searchDirs {
            let dirPath = "\(home)/\(dir)"
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { continue }

            for entry in entries {
                let filePath = "\(dirPath)/\(entry)"
                guard FileManager.default.isReadableFile(atPath: filePath) else { continue }

                // Skip directories, binaries, and large files
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir)
                if isDir.boolValue { continue }
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                      let size = attrs[.size] as? Int, size < 50_000 else { continue }

                let ext = (entry as NSString).pathExtension.lowercased()
                guard ["env", "txt", "json", ""].contains(ext) || entry == "credentials" else { continue }

                // Try to extract key=value pairs
                guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                let shortSource = "~/\(dir)/\(entry)"

                let vars = extractKeyValues(from: content)
                for (key, value) in vars {
                    if tokenKeys.contains(key) && !value.isEmpty {
                        if allEnvVars[key] == nil {
                            allEnvVars[key] = (value, shortSource)
                        }
                    }
                }
            }
        }

        // Also check the Atlassian-tokens.txt fallback format
        let tokensFile = "\(home)/.amazonq/Atlassian-tokens.txt"
        if let content = try? String(contentsOfFile: tokensFile, encoding: .utf8) {
            let tokens = parseAtlassianTokensFile(content)
            for (key, value) in tokens {
                if allEnvVars[key] == nil {
                    allEnvVars[key] = (value, "~/.amazonq/Atlassian-tokens.txt")
                }
            }
        }

        // Also check standalone token files
        let standaloneFiles: [(path: String, key: String)] = [
            (".amazonq/github-token-mcp.txt", "GITHUB_TOKEN"),
        ]
        for (relPath, key) in standaloneFiles {
            let path = "\(home)/\(relPath)"
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                // Find the first line that looks like a token
                for line in content.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("ghp_") || trimmed.hasPrefix("ATATT") {
                        if allEnvVars[key] == nil {
                            allEnvVars[key] = (trimmed, "~/\(relPath)")
                        }
                        break
                    }
                }
            }
        }

        // Also try git config for email
        let gitConfigPath = "\(home)/.gitconfig"
        if let content = try? String(contentsOfFile: gitConfigPath, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("email") && trimmed.contains("=") {
                    let email = trimmed.components(separatedBy: "=").last?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    if email.contains("@") && allEnvVars["ATLASSIAN_USERNAME"] == nil {
                        allEnvVars["ATLASSIAN_USERNAME"] = (email, "~/.gitconfig")
                    }
                }
            }
        }

        // Map collected vars to result
        if let v = allEnvVars["JIRA_API_TOKEN"] {
            result.jiraToken = v.value; result.sources.append("Jira token from \(v.source)")
        }
        if let v = allEnvVars["CONFLUENCE_API_TOKEN"] ?? allEnvVars["ATLASSIAN_API_TOKEN"] {
            result.confluenceToken = v.value; result.sources.append("Confluence token from \(v.source)")
        }
        // Use ATLASSIAN_API_TOKEN as Jira fallback too
        if result.jiraToken == nil, let v = allEnvVars["ATLASSIAN_API_TOKEN"] {
            result.jiraToken = v.value; result.sources.append("Jira token from \(v.source)")
        }
        if let v = allEnvVars["BITBUCKET_API_TOKEN"] {
            result.bitbucketToken = v.value; result.sources.append("Bitbucket token from \(v.source)")
        }
        if let v = allEnvVars["BITBUCKET_USERNAME"] { result.bitbucketUsername = v.value }
        if let v = allEnvVars["BITBUCKET_URL"] { result.bitbucketURL = v.value }
        if let v = allEnvVars["GITHUB_TOKEN"] ?? allEnvVars["GITHUB_PERSONAL_ACCESS_TOKEN"] {
            result.githubToken = v.value; result.sources.append("GitHub token from \(v.source)")
        }
        if let v = allEnvVars["JENKINS_URL"] { result.jenkinsURL = v.value }
        if let v = allEnvVars["JENKINS_USERNAME"] { result.jenkinsUsername = v.value }
        if let v = allEnvVars["JENKINS_TOKEN"] ?? allEnvVars["JENKINS_PASSWORD"] {
            result.jenkinsToken = v.value; result.sources.append("Jenkins token from \(v.source)")
        }
        if let v = allEnvVars["GRAFANA_URL"] { result.grafanaURL = v.value }
        if let v = allEnvVars["GRAFANA_TOKEN"] ?? allEnvVars["GRAFANA_API_KEY"] {
            result.grafanaToken = v.value; result.sources.append("Grafana token from \(v.source)")
        }
        if let v = allEnvVars["ANTHROPIC_API_KEY"] {
            result.anthropicAPIKey = v.value; result.sources.append("Anthropic API key from \(v.source)")
        }
        if let v = allEnvVars["ATLASSIAN_USERNAME"] ?? allEnvVars["GMAIL_EMAIL"] {
            result.atlassianEmail = v.value; result.sources.append("Email from \(v.source)")
        }
        if let v = allEnvVars["ATLASSIAN_URL"] ?? allEnvVars["JIRA_URL"] {
            result.atlassianBaseURL = v.value
        }
        return result
    }

    /// The app's canonical credential directory.
    static let credentialDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".boomi-sre/credentials")
    }()

    /// Ensure ~/.boomi-sre/credentials/ exists.
    static func ensureCredentialDir() {
        try? FileManager.default.createDirectory(at: credentialDir, withIntermediateDirectories: true)
    }

    /// Persist discovered credentials as .env files in ~/.boomi-sre/credentials/.
    /// Only writes files that don't already exist (won't overwrite user edits).
    static func persistDiscovered(_ creds: DiscoveredCredentials) {
        ensureCredentialDir()

        var lines: [String] = []
        if let v = creds.jiraToken { lines.append("JIRA_API_TOKEN=\(v)") }
        if let v = creds.confluenceToken { lines.append("CONFLUENCE_API_TOKEN=\(v)") }
        if let v = creds.bitbucketToken { lines.append("BITBUCKET_API_TOKEN=\(v)") }
        if let v = creds.githubToken { lines.append("GITHUB_TOKEN=\(v)") }
        if let v = creds.jenkinsURL { lines.append("JENKINS_URL=\(v)") }
        if let v = creds.jenkinsUsername { lines.append("JENKINS_USERNAME=\(v)") }
        if let v = creds.jenkinsToken { lines.append("JENKINS_TOKEN=\(v)") }
        if let v = creds.grafanaURL { lines.append("GRAFANA_URL=\(v)") }
        if let v = creds.grafanaToken { lines.append("GRAFANA_TOKEN=\(v)") }
        if let v = creds.anthropicAPIKey { lines.append("ANTHROPIC_API_KEY=\(v)") }
        if let v = creds.atlassianEmail { lines.append("ATLASSIAN_USERNAME=\(v)") }
        if let v = creds.atlassianBaseURL { lines.append("ATLASSIAN_URL=\(v)") }

        guard !lines.isEmpty else { return }
        let envFile = credentialDir.appendingPathComponent("credentials.env")
        // Only write if the file doesn't exist yet
        if !FileManager.default.fileExists(atPath: envFile.path) {
            let content = lines.joined(separator: "\n") + "\n"
            try? content.write(to: envFile, atomically: true, encoding: .utf8)
        }
    }

    /// Import a Google credential JSON file into ~/.boomi-sre/credentials/.
    /// Copies the file with the same name. Returns the destination path.
    @discardableResult
    static func importGoogleCredentials(from sourceURL: URL) -> URL? {
        ensureCredentialDir()
        let dest = credentialDir.appendingPathComponent(sourceURL.lastPathComponent)
        // Always overwrite — the user is explicitly importing
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// Scan MCP credential directories for Google credential JSON files and import them.
    /// Returns the number of files imported.
    static func importGoogleCredentialsFromMCP() -> Int {
        ensureCredentialDir()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mcpDirs = [
            home.appendingPathComponent(".google_workspace_mcp/credentials"),
            home.appendingPathComponent(".amazonq/mcp_credentials"),
            home.appendingPathComponent(".kiro/mcp_credentials"),
        ]
        var imported = 0
        for dir in mcpDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "json" {
                let name = file.lastPathComponent.lowercased()
                guard name.contains("google") || name.contains("gmail") || name.contains("@") else { continue }
                // Only import if it's a valid credential (has refresh_token)
                guard let data = try? Data(contentsOf: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["refresh_token"] != nil else { continue }
                if importGoogleCredentials(from: file) != nil { imported += 1 }
            }
        }
        return imported
    }

    static func discoveredCount(_ creds: DiscoveredCredentials) -> Int {
        var count = 0
        if creds.jiraToken != nil { count += 1 }
        if creds.confluenceToken != nil { count += 1 }
        if creds.bitbucketToken != nil { count += 1 }
        if creds.githubToken != nil { count += 1 }
        if creds.jenkinsToken != nil { count += 1 }
        if creds.grafanaToken != nil { count += 1 }
        if creds.anthropicAPIKey != nil { count += 1 }
        return count
    }

    // MARK: - Parsers

    /// Extract KEY=VALUE pairs from file content (handles .env, .txt, INI-like formats).
    private static func extractKeyValues(from content: String) -> [(String, String)] {
        var results: [(String, String)] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }
            if let eqRange = trimmed.range(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                var value = trimmed[eqRange.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                // Remove surrounding quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty && !value.isEmpty {
                    results.append((key, value))
                }
            }
        }
        return results
    }

    /// Parse the Atlassian-tokens.txt format: label lines followed by token values.
    private static func parseAtlassianTokensFile(_ content: String) -> [(String, String)] {
        var results: [(String, String)] = []
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for i in 0..<lines.count {
            let line = lines[i]
            if line.hasSuffix("_TOKEN") || line.hasSuffix("_API_TOKEN") {
                // Next non-empty line is the value
                var j = i + 1
                while j < lines.count && lines[j].isEmpty { j += 1 }
                if j < lines.count && !lines[j].isEmpty && !lines[j].hasSuffix("_TOKEN") {
                    results.append((line, lines[j]))
                }
            }
        }
        return results
    }
}

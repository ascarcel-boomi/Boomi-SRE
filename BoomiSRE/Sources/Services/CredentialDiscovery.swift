import Foundation

/// Scans known credential file locations on the Mac and imports tokens.
struct CredentialDiscovery {
    struct DiscoveredCredentials {
        var jiraToken: String?
        var confluenceToken: String?
        var bitbucketToken: String?
        var githubToken: String?
        var atlassianEmail: String?
        var atlassianBaseURL: String?
        var sources: [String]  // human-readable list of where things were found
    }

    /// Scan all known credential locations and return what was found.
    static func discover() -> DiscoveredCredentials {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result = DiscoveredCredentials(sources: [])

        // 1. ~/.amazonq/mcp_credentials/mcp-atlassian.env (has all Atlassian tokens)
        let amazonqAtlassian = "\(home)/.amazonq/mcp_credentials/mcp-atlassian.env"
        if let env = parseEnvFile(amazonqAtlassian) {
            if let v = env["JIRA_API_TOKEN"], !v.isEmpty, result.jiraToken == nil {
                result.jiraToken = v
                result.sources.append("Jira token from ~/.amazonq/mcp_credentials/")
            }
            if let v = env["CONFLUENCE_API_TOKEN"], !v.isEmpty, result.confluenceToken == nil {
                result.confluenceToken = v
                result.sources.append("Confluence token from ~/.amazonq/mcp_credentials/")
            }
            if let v = env["BITBUCKET_API_TOKEN"], !v.isEmpty, result.bitbucketToken == nil {
                result.bitbucketToken = v
                result.sources.append("Bitbucket token from ~/.amazonq/mcp_credentials/")
            }
            if let v = env["JIRA_URL"] ?? env["ATLASSIAN_URL"], !v.isEmpty {
                result.atlassianBaseURL = v
            }
            if let v = env["ATLASSIAN_USERNAME"], !v.isEmpty {
                result.atlassianEmail = v
            }
        }

        // 2. ~/.kiro/mcp_credentials/mcp-atlassian.env (may have different tokens)
        let kiroAtlassian = "\(home)/.kiro/mcp_credentials/mcp-atlassian.env"
        if let env = parseEnvFile(kiroAtlassian) {
            if let v = env["ATLASSIAN_API_TOKEN"], !v.isEmpty {
                // Kiro uses a single token for both Jira and Confluence
                if result.jiraToken == nil {
                    result.jiraToken = v
                    result.sources.append("Jira token from ~/.kiro/mcp_credentials/")
                }
                if result.confluenceToken == nil {
                    result.confluenceToken = v
                    result.sources.append("Confluence token from ~/.kiro/mcp_credentials/")
                }
            }
            if let v = env["ATLASSIAN_URL"], !v.isEmpty, result.atlassianBaseURL == nil {
                result.atlassianBaseURL = v
            }
            if let v = env["ATLASSIAN_USERNAME"], !v.isEmpty, result.atlassianEmail == nil {
                result.atlassianEmail = v
            }
        }

        // 3. GitHub tokens
        for ghPath in [
            "\(home)/.amazonq/mcp_credentials/github.env",
            "\(home)/.kiro/mcp_credentials/github.env",
        ] {
            if result.githubToken != nil { break }
            if let env = parseEnvFile(ghPath) {
                let token = env["GITHUB_TOKEN"] ?? env["GITHUB_PERSONAL_ACCESS_TOKEN"] ?? ""
                if !token.isEmpty {
                    result.githubToken = token
                    let source = ghPath.contains(".amazonq") ? "~/.amazonq" : "~/.kiro"
                    result.sources.append("GitHub token from \(source)/mcp_credentials/")
                }
            }
        }

        // 4. ~/.amazonq/Atlassian-tokens.txt (fallback — different format)
        let tokensFile = "\(home)/.amazonq/Atlassian-tokens.txt"
        if let content = try? String(contentsOfFile: tokensFile, encoding: .utf8) {
            let tokens = parseAtlassianTokensFile(content)
            if let v = tokens["JIRA_API_TOKEN"], !v.isEmpty, result.jiraToken == nil {
                result.jiraToken = v
                result.sources.append("Jira token from ~/.amazonq/Atlassian-tokens.txt")
            }
            if let v = tokens["CONFLUENCE_API_TOKEN"], !v.isEmpty, result.confluenceToken == nil {
                result.confluenceToken = v
                result.sources.append("Confluence token from ~/.amazonq/Atlassian-tokens.txt")
            }
            if let v = tokens["BITBUCKET_API_TOKEN"], !v.isEmpty, result.bitbucketToken == nil {
                result.bitbucketToken = v
                result.sources.append("Bitbucket token from ~/.amazonq/Atlassian-tokens.txt")
            }
        }

        // 5. Try to discover email from git config
        if result.atlassianEmail == nil {
            let gitConfigPath = "\(home)/.gitconfig"
            if let content = try? String(contentsOfFile: gitConfigPath, encoding: .utf8) {
                for line in content.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("email") && trimmed.contains("=") {
                        let email = trimmed.components(separatedBy: "=").last?
                            .trimmingCharacters(in: .whitespaces) ?? ""
                        if email.contains("@") {
                            result.atlassianEmail = email
                            result.sources.append("Email from ~/.gitconfig")
                            break
                        }
                    }
                }
            }
        }

        return result
    }

    /// Count how many credentials were found.
    static func discoveredCount(_ creds: DiscoveredCredentials) -> Int {
        var count = 0
        if creds.jiraToken != nil { count += 1 }
        if creds.confluenceToken != nil { count += 1 }
        if creds.bitbucketToken != nil { count += 1 }
        if creds.githubToken != nil { count += 1 }
        return count
    }

    // MARK: - Parsers

    /// Parse a KEY=VALUE .env file, ignoring comments and blank lines.
    private static func parseEnvFile(_ path: String) -> [String: String]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let eqRange = trimmed.range(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                let value = trimmed[eqRange.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Parse the Atlassian-tokens.txt format: alternating label/blank/value lines.
    private static func parseAtlassianTokensFile(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Look for known token names
            if line == "JIRA_API_TOKEN" || line == "CONFLUENCE_API_TOKEN" || line == "BITBUCKET_API_TOKEN" {
                // Next non-empty line is the value
                var j = i + 1
                while j < lines.count && lines[j].isEmpty { j += 1 }
                if j < lines.count && !lines[j].isEmpty && !lines[j].contains("_TOKEN") {
                    result[line] = lines[j]
                }
            }
            i += 1
        }
        return result
    }
}

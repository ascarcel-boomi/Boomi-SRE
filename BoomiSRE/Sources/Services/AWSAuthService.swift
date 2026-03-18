import Foundation

/// Manages AWS SSO authentication by shelling out to the AWS CLI.
actor AWSAuthService {

    /// Trigger `aws sso login --profile <profile>`. Opens browser for device auth.
    func login(profile: String) async throws -> String {
        let (output, exitCode) = try await runAWS(["sso", "login", "--profile", profile])
        if exitCode != 0 {
            throw AWSAuthError.loginFailed(output)
        }
        return output
    }

    /// Check auth status via `aws sts get-caller-identity`.
    func checkStatus(profile: String) async throws -> String {
        let (output, exitCode) = try await runAWS([
            "sts", "get-caller-identity", "--profile", profile, "--output", "json",
        ])
        if exitCode != 0 {
            throw AWSAuthError.expired
        }

        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let account = json["Account"] as? String,
           let arn = json["Arn"] as? String {
            return "Account \(account) (\(arn))"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// List all available profiles from both ~/.aws/config and ~/.aws/credentials.
    nonisolated func listProfiles() -> [AWSProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var profiles: [AWSProfile] = []
        var seen = Set<String>()

        // SSO profiles from ~/.aws/config
        let configPath = home.appendingPathComponent(".aws/config")
        if let content = try? String(contentsOf: configPath, encoding: .utf8) {
            let blocks = parseINIBlocks(content)
            for (header, fields) in blocks {
                let name: String
                if header.hasPrefix("profile ") {
                    name = String(header.dropFirst("profile ".count))
                } else if header == "default" {
                    name = "default"
                } else {
                    continue
                }
                guard !seen.contains(name) else { continue }
                seen.insert(name)

                let accountId = fields["sso_account_id"] ?? ""
                let roleName = fields["sso_role_name"] ?? ""
                let region = fields["region"] ?? ""
                let output = fields["output"] ?? ""
                let source = accountId.isEmpty ? .credentials : AWSProfileSource.sso

                profiles.append(AWSProfile(
                    name: name, accountId: accountId, roleName: roleName,
                    region: region, outputFormat: output, source: source
                ))
            }
        }

        // Credential profiles from ~/.aws/credentials (portal paste)
        let credPath = home.appendingPathComponent(".aws/credentials")
        if let content = try? String(contentsOf: credPath, encoding: .utf8) {
            let blocks = parseINIBlocks(content)
            for (header, fields) in blocks {
                let name = header
                guard !seen.contains(name) else { continue }
                seen.insert(name)

                // Try to extract account ID from profile name (e.g. "033087822876_ReadOnlyAccess")
                let parts = name.split(separator: "_", maxSplits: 1)
                let accountId = parts.first.map(String.init) ?? ""
                let roleName = parts.count > 1 ? String(parts[1]) : ""
                let hasKeys = fields["aws_access_key_id"] != nil

                if hasKeys {
                    profiles.append(AWSProfile(
                        name: name, accountId: accountId, roleName: roleName,
                        region: "", outputFormat: "", source: .credentials
                    ))
                }
            }
        }

        // Flag duplicates: profiles that share the same accountId + roleName
        // but differ by output format (e.g. json vs text)
        var groupKey: [String: [Int]] = [:]  // "accountId/roleName" -> [indices]
        for (i, p) in profiles.enumerated() {
            guard !p.accountId.isEmpty && !p.roleName.isEmpty else { continue }
            let key = "\(p.accountId)/\(p.roleName)"
            groupKey[key, default: []].append(i)
        }
        for (_, indices) in groupKey where indices.count > 1 {
            for i in indices {
                profiles[i].isDuplicate = true
            }
        }

        return profiles.sorted { $0.name < $1.name }
    }

    /// Resolve an account's friendly name.
    /// Tries `iam list-account-aliases` first (works on any account),
    /// then falls back to `organizations describe-account` (requires org access).
    func resolveAccountName(profile: String, accountId: String = "") async -> String? {
        // 1. Try IAM account aliases (works without org permissions)
        if let result = try? await runAWS([
            "iam", "list-account-aliases", "--profile", profile, "--output", "json",
        ]) {
            let (output, exitCode) = result
            if exitCode == 0,
               let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let aliases = json["AccountAliases"] as? [String],
               let alias = aliases.first, !alias.isEmpty {
                return alias
            }
        }

        // 2. Try Organizations describe-account (works from payer/management account)
        if !accountId.isEmpty {
            if let result = try? await runAWS([
                "organizations", "describe-account",
                "--account-id", accountId,
                "--profile", profile,
                "--output", "json",
            ]) {
                let (output, exitCode) = result
                if exitCode == 0,
                   let data = output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let account = json["Account"] as? [String: Any],
                   let name = account["Name"] as? String, !name.isEmpty {
                    return name
                }
            }
        }

        return nil
    }

    /// Append portal credentials to ~/.aws/credentials and register in ~/.aws/config.
    nonisolated func addPortalCredentials(_ pastedText: String) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credPath = home.appendingPathComponent(".aws/credentials")
        let configPath = home.appendingPathComponent(".aws/config")

        // Normalize line endings — clipboard/AWS portal may use \r\n (Windows) or \r
        let normalized = pastedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("aws_access_key_id") else {
            throw AWSAuthError.invalidCredentials
        }

        // Extract profile name from [ProfileName] header
        var profileName = ""
        for line in trimmed.components(separatedBy: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)  // strips \r too
            if l.hasPrefix("[") && l.hasSuffix("]") {
                profileName = String(l.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        // Fallback if name couldn't be extracted
        if profileName.isEmpty {
            profileName = "portal-\(Int(Date().timeIntervalSince1970))"
        }

        // --- Update ~/.aws/credentials (using normalized text, no \r) ---
        let existingCreds = (try? String(contentsOf: credPath, encoding: .utf8)) ?? ""
        // Remove any stale block with the same name, then append the normalized block
        let filteredCreds = removeINIBlock(from: existingCreds, named: profileName)
        var newCreds = filteredCreds
        if !newCreds.hasSuffix("\n") { newCreds += "\n" }
        newCreds += "\n" + trimmed + "\n"   // trimmed is already \r-free

        try newCreds.write(to: credPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credPath.path)

        // Safety check: verify the profile header appears in the written file
        let writtenCreds = (try? String(contentsOf: credPath, encoding: .utf8)) ?? ""
        guard writtenCreds.contains("[\(profileName)]") else {
            throw AWSAuthError.invalidCredentials  // shouldn't happen, but guard anyway
        }

        // Deduplicate: if removeINIBlock failed on a previous run, remove any remaining duplicates
        let dedupedCreds = deduplicateINIBlocks(writtenCreds)
        if dedupedCreds != writtenCreds {
            try dedupedCreds.write(to: credPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credPath.path)
        }

        // --- Ensure profile is registered in ~/.aws/config ---
        // AWS CLI needs [profile <name>] in config for --profile to work
        var existingConfig = (try? String(contentsOf: configPath, encoding: .utf8)) ?? ""
        let configHeader = "[profile \(profileName)]"

        // Remove stale [profile pasted] entry if present (artifact of previous parsing bug)
        existingConfig = removeINIBlock(from: existingConfig, named: "pasted")

        if !existingConfig.contains(configHeader) {
            if !existingConfig.hasSuffix("\n") { existingConfig += "\n" }
            // Extract region from credentials or default to us-east-1
            existingConfig += "\n\(configHeader)\nregion = us-east-1\noutput = json\n"
            try existingConfig.write(to: configPath, atomically: true, encoding: .utf8)
        }

        return profileName
    }

    /// Remove an INI block by name from file content.
    /// Handles both `[blockName]` (credentials format) and `[profile blockName]` (config format).
    /// Uses whitespacesAndNewlines to correctly strip \r from Windows-style line endings.
    private nonisolated func removeINIBlock(from content: String, named blockName: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var filtered: [String] = []
        var skipping = false
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Match both [blockName] and [profile blockName] formats
            if l == "[\(blockName)]" || l == "[profile \(blockName)]" {
                skipping = true
                continue
            }
            // Stop skipping when we hit the next block header
            if skipping && l.hasPrefix("[") && l.hasSuffix("]") {
                skipping = false
            }
            if !skipping {
                filtered.append(line)
            }
        }
        return filtered.joined(separator: "\n")
    }

    /// Deduplicate INI blocks — if a [header] appears more than once, keep only the LAST occurrence.
    /// This handles credentials files that were corrupted by a previous removeINIBlock failure.
    private nonisolated func deduplicateINIBlocks(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")

        // First pass: collect all blocks in order
        var blockOrder: [String] = []           // ordered block names
        var blockLines: [String: [String]] = [:]  // blockName -> lines (header + body)
        var currentBlock: String? = nil
        var preamble: [String] = []             // lines before any block

        for line in lines {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") && l.hasSuffix("]") {
                // New block header
                let name = String(l.dropFirst().dropLast())
                currentBlock = name
                if !blockOrder.contains(name) {
                    blockOrder.append(name)
                }
                // Overwrite previous block (keeps last occurrence)
                blockLines[name] = [line]
            } else if let block = currentBlock {
                blockLines[block, default: []].append(line)
            } else {
                preamble.append(line)
            }
        }

        // Reconstruct: preamble + blocks in original order (deduped)
        var result = preamble
        for name in blockOrder {
            if let lines = blockLines[name] {
                result.append(contentsOf: lines)
            }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - INI parser

    private nonisolated func parseINIBlocks(_ content: String) -> [(String, [String: String])] {
        var blocks: [(String, [String: String])] = []
        var currentHeader: String?
        var currentFields: [String: String] = [:]

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if let header = currentHeader {
                    blocks.append((header, currentFields))
                }
                currentHeader = String(trimmed.dropFirst().dropLast())
                currentFields = [:]
            } else if let eqRange = trimmed.range(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqRange.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed[eqRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentFields[key] = value
            }
        }
        if let header = currentHeader {
            blocks.append((header, currentFields))
        }
        return blocks
    }

    // MARK: - Private

    static let resolvedAWSPath: String = {
        let candidates = [
            "/usr/local/bin/aws",
            "/opt/homebrew/bin/aws",
            "/usr/local/aws-cli/aws",
            "/usr/bin/aws",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/aws"
    }()

    // Delegates to shared AWSCLIRunner.run() — see Extensions/AWSCLIRunner.swift
    private func runAWS(_ args: [String]) async throws -> (String, Int32) {
        let result = try await AWSCLIRunner.run(arguments: args)
        return (result.output, result.exitCode)
    }

    // MARK: - SSO Account Discovery

    /// Represents an AWS account from IAM Identity Center.
    struct SSOAccount: Sendable {
        let accountId: String
        let accountName: String
        let emailAddress: String
    }

    /// List all AWS accounts the user has access to via IAM Identity Center (SSO).
    /// Reads the cached SSO access token from `~/.aws/sso/cache/` and calls `aws sso list-accounts`.
    func listSSOAccounts() async throws -> [SSOAccount] {
        // 1. Find a valid access token from the SSO cache
        guard let token = findSSOAccessToken() else {
            throw AWSAuthError.loginFailed("No active SSO session. Run `aws sso login` first.")
        }

        // 2. Determine the SSO region from ~/.aws/config
        let ssoRegion = readSSORegion() ?? "us-east-1"

        // 3. Call list-accounts (paginated)
        var accounts: [SSOAccount] = []
        var nextToken: String? = nil

        repeat {
            var args = ["sso", "list-accounts",
                        "--access-token", token,
                        "--region", ssoRegion,
                        "--output", "json",
                        "--no-paginate"]
            if let nt = nextToken { args += ["--next-token", nt] }

            let (output, exitCode) = try await runAWS(args)
            guard exitCode == 0, let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accountList = json["accountList"] as? [[String: Any]] else {
                break
            }

            for a in accountList {
                guard let id = a["accountId"] as? String,
                      let name = a["accountName"] as? String else { continue }
                accounts.append(SSOAccount(
                    accountId: id,
                    accountName: name,
                    emailAddress: a["emailAddress"] as? String ?? ""
                ))
            }

            nextToken = json["nextToken"] as? String
        } while nextToken != nil

        return accounts.sorted { $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending }
    }

    /// List available SSO roles for a specific account.
    func listAccountRoles(accountId: String) async throws -> [String] {
        guard let token = findSSOAccessToken() else { return [] }
        let ssoRegion = readSSORegion() ?? "us-east-1"
        let (output, exitCode) = try await runAWS([
            "sso", "list-account-roles",
            "--account-id", accountId,
            "--access-token", token,
            "--region", ssoRegion,
            "--output", "json"
        ])
        guard exitCode == 0, let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roles = json["roleList"] as? [[String: Any]] else { return [] }
        return roles.compactMap { $0["roleName"] as? String }.sorted()
    }

    /// Bootstrap ~/.aws/config with SSO session and profiles for every account the user can access.
    /// Returns the number of profiles written.
    func bootstrapSSOConfig(
        ssoStartURL: String = "https://d-90678132a6.awsapps.com/start/#",
        ssoRegion: String = "us-east-1",
        defaultRegion: String = "us-east-1",
        sessionName: String = "boomi-sso"
    ) async throws -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".aws/config")

        // Ensure ~/.aws/ directory exists
        let awsDir = home.appendingPathComponent(".aws")
        try FileManager.default.createDirectory(at: awsDir, withIntermediateDirectories: true)

        // Read existing config (if any)
        var config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        // Add sso-session block if missing
        let sessionHeader = "[sso-session \(sessionName)]"
        if !config.contains(sessionHeader) {
            if !config.isEmpty && !config.hasSuffix("\n") { config += "\n" }
            config += """
            \n\(sessionHeader)
            sso_region = \(ssoRegion)
            sso_start_url = \(ssoStartURL)
            sso_registration_scopes = sso:account:access\n
            """
        }

        // Write config so SSO login can find the session
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        // List all accounts
        let accounts = try await listSSOAccounts()
        guard !accounts.isEmpty else { return 0 }

        var profileCount = 0
        for account in accounts {
            // Get roles for this account
            let roles = try await listAccountRoles(accountId: account.accountId)
            let rolesToUse = roles.isEmpty ? ["ReadOnlyAccess"] : roles

            for role in rolesToUse {
                // Profile name: sanitized account name + role
                let safeName = account.accountName
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "/", with: "-")
                    .lowercased()
                let profileName = "\(safeName)-\(role)"
                let profileHeader = "[profile \(profileName)]"

                // Skip if profile already exists
                guard !config.contains(profileHeader) else { continue }

                if !config.hasSuffix("\n") { config += "\n" }
                config += """
                \n\(profileHeader)
                sso_session = \(sessionName)
                sso_account_id = \(account.accountId)
                sso_role_name = \(role)
                region = \(defaultRegion)
                output = json\n
                """
                profileCount += 1
            }
        }

        // Write final config
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        return profileCount
    }

    /// Read the most recent valid SSO access token from `~/.aws/sso/cache/`.
    private nonisolated func findSSOAccessToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cacheDir = "\(home)/.aws/sso/cache"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDir) else { return nil }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        var bestToken: (token: String, expires: Date)?

        for file in files where file.hasSuffix(".json") {
            let path = "\(cacheDir)/\(file)"
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["accessToken"] as? String, !token.isEmpty,
                  let expiresStr = json["expiresAt"] as? String,
                  // Must have a startUrl (not a client registration or Kiro token)
                  json["startUrl"] != nil else { continue }

            let expires = formatter.date(from: expiresStr) ?? formatterNoFrac.date(from: expiresStr)
            guard let expires, expires > now else { continue }

            if bestToken == nil || expires > bestToken!.expires {
                bestToken = (token, expires)
            }
        }

        return bestToken?.token
    }

    /// Read `sso_region` from the first SSO profile in `~/.aws/config`.
    private nonisolated func readSSORegion() -> String? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("sso_region") && trimmed.contains("=") {
                return trimmed.components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - Models

struct AWSProfile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let accountId: String
    let roleName: String
    let region: String
    let outputFormat: String     // "json", "text", "table", or ""
    let source: AWSProfileSource
    var friendlyName: String = ""  // Resolved from AWS, e.g. "boomi-mashery-production"
    /// Set to true when another profile shares the same account+role (disambiguate with output format).
    var isDuplicate: Bool = false

    var displayName: String {
        // Use the profile name directly — it's already human-readable
        // (e.g. "boomi-mashery-production-ReadOnlyAccess")
        var base = name
        if isDuplicate && !outputFormat.isEmpty {
            base += " [\(outputFormat)]"
        }
        return base
    }
}

enum AWSProfileSource {
    case sso
    case credentials
}

enum AWSAuthError: LocalizedError {
    case loginFailed(String)
    case expired
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .loginFailed(let output): return "AWS SSO login failed:\n\(output.prefix(300))"
        case .expired: return "AWS SSO session expired. Click \"Login with SSO\" to re-authenticate."
        case .invalidCredentials: return "Invalid credentials format. Paste the full block from the AWS portal including the [profile] header."
        }
    }
}

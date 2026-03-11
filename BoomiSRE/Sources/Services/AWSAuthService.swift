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
                let source = accountId.isEmpty ? .credentials : AWSProfileSource.sso

                profiles.append(AWSProfile(
                    name: name, accountId: accountId, roleName: roleName,
                    region: region, source: source
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
                        region: "", source: .credentials
                    ))
                }
            }
        }

        return profiles.sorted { $0.name < $1.name }
    }

    /// Append portal credentials to ~/.aws/credentials.
    nonisolated func addPortalCredentials(_ pastedText: String) throws -> String {
        let credPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/credentials")

        // Parse the pasted text to extract the profile block
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("aws_access_key_id") else {
            throw AWSAuthError.invalidCredentials
        }

        // Extract profile name from [profile_name] header
        var profileName = "pasted"
        for line in trimmed.components(separatedBy: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("[") && l.hasSuffix("]") {
                profileName = String(l.dropFirst().dropLast())
                break
            }
        }

        // Read existing file, append new block
        var existing = (try? String(contentsOf: credPath, encoding: .utf8)) ?? ""
        if !existing.hasSuffix("\n") { existing += "\n" }

        // Remove existing block with same name if present
        let lines = existing.components(separatedBy: "\n")
        var filtered: [String] = []
        var skipping = false
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l == "[\(profileName)]" {
                skipping = true
                continue
            }
            if skipping && l.hasPrefix("[") {
                skipping = false
            }
            if !skipping {
                filtered.append(line)
            }
        }

        // Append the new block
        var result = filtered.joined(separator: "\n")
        if !result.hasSuffix("\n") { result += "\n" }
        result += "\n" + trimmed + "\n"

        try result.write(to: credPath, atomically: true, encoding: .utf8)

        // Set permissions to 600
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: credPath.path
        )

        return profileName
    }

    // MARK: - INI parser

    private nonisolated func parseINIBlocks(_ content: String) -> [(String, [String: String])] {
        var blocks: [(String, [String: String])] = []
        var currentHeader: String?
        var currentFields: [String: String] = [:]

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if let header = currentHeader {
                    blocks.append((header, currentFields))
                }
                currentHeader = String(trimmed.dropFirst().dropLast())
                currentFields = [:]
            } else if let eqRange = trimmed.range(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                let value = trimmed[eqRange.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                currentFields[key] = value
            }
        }
        if let header = currentHeader {
            blocks.append((header, currentFields))
        }
        return blocks
    }

    // MARK: - Private

    private static let awsPath: String = {
        let candidates = [
            "/usr/local/bin/aws",
            "/opt/homebrew/bin/aws",
            "/usr/local/aws-cli/aws",
            "/usr/bin/aws",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/aws"
    }()

    private func runAWS(_ args: [String]) async throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.awsPath)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }
}

// MARK: - Models

struct AWSProfile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let accountId: String
    let roleName: String
    let region: String
    let source: AWSProfileSource

    var displayName: String {
        if !accountId.isEmpty && !roleName.isEmpty {
            return "\(name)  (\(accountId) / \(roleName))"
        }
        return name
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

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
    /// Returns a descriptive string like "Account 809167139867 (arn:aws:...)".
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

    /// List available SSO profiles from ~/.aws/config.
    nonisolated func listProfiles() -> [String] {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
            return ["cam-prod-ro-json"]
        }

        var profiles: [String] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[profile ") && trimmed.hasSuffix("]") {
                let name = trimmed
                    .replacingOccurrences(of: "[profile ", with: "")
                    .replacingOccurrences(of: "]", with: "")
                profiles.append(name)
            }
        }
        return profiles.isEmpty ? ["cam-prod-ro-json"] : profiles.sorted()
    }

    // MARK: - Private

    private func runAWS(_ args: [String]) async throws -> (String, Int32) {
        let process = Process()

        // Find aws CLI — could be in /usr/local/bin, /opt/homebrew/bin, etc.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["aws"] + args
        process.environment = ProcessInfo.processInfo.environment

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

enum AWSAuthError: LocalizedError {
    case loginFailed(String)
    case expired

    var errorDescription: String? {
        switch self {
        case .loginFailed(let output): return "AWS SSO login failed:\n\(output.prefix(300))"
        case .expired: return "AWS SSO session expired. Click \"Login with SSO\" to re-authenticate."
        }
    }
}

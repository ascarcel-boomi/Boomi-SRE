import Foundation

// MARK: - AWSCLIRunner
//
// Shared AWS CLI subprocess helper used by AWSAuthService, AWSCostService,
// and AWSInfraService. Extracts the identical runAWS() pattern from all three.

enum AWSCLIRunner {
    /// Run an AWS CLI command and return (output, exitCode).
    ///
    /// Pipes are read BEFORE waitUntilExit() to prevent deadlock when
    /// output exceeds the pipe buffer (~64 KB on macOS).
    static func run(arguments: [String]) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AWSAuthService.resolvedAWSPath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read stdout BEFORE waitUntilExit to avoid pipe-buffer deadlock.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let output: String
        if process.terminationStatus == 0 {
            output = String(data: stdoutData, encoding: .utf8) ?? ""
        } else {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            let out = String(data: stdoutData, encoding: .utf8) ?? ""
            output = err.isEmpty ? out : err
        }
        return (output, process.terminationStatus)
    }
}

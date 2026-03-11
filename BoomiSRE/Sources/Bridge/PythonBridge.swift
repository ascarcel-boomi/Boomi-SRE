import Foundation

/// Runs Python scripts from ~/github/home-config and captures their output.
actor PythonBridge {
    private let scriptsDir: URL
    private let awsPython: URL
    private let systemPython: String = "python3"

    private static let awsScripts: Set<String> = [
        "aws_cost_reporter.py", "generate_real_aws_report.py", "test_real_aws_costs.py",
        "aws_cost_reporting_agent.py", "aws_cost_reporting_agent_mcp.py",
        "comprehensive_cost_analyzer.py", "automated_cost_reporter.py",
        "manage_cost_automation.py",
    ]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.scriptsDir = home.appendingPathComponent("github/home-config")
        self.awsPython = home.appendingPathComponent("aws_cost_agent_env/bin/python3")
    }

    /// Run a script and return the raw stdout.
    func run(script: String, args: [String] = []) async throws -> String {
        let python = Self.awsScripts.contains(script) && FileManager.default.isExecutableFile(atPath: awsPython.path)
            ? awsPython.path
            : systemPython

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptsDir.appendingPathComponent(script).path] + args
        process.currentDirectoryURL = scriptsDir
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw BridgeError.scriptFailed(script: script, exitCode: process.terminationStatus, output: output)
        }

        return output
    }
}

enum BridgeError: LocalizedError {
    case scriptFailed(script: String, exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let script, let code, let output):
            return "Script \(script) exited with code \(code):\n\(output.prefix(500))"
        }
    }
}

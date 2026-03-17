import Foundation
import AppKit

// MARK: - UpdateService
//
// Checks GitHub Releases API for new versions of Boomi SRE.
// The repo is ascarcel-boomi/Boomi-SRE.
// Version format: YY.MM.DD-HHMMSS (e.g. "26.03.14-120000")
// Tag format: v{version} (e.g. "v26.03.14-120000")
//
// Simple lexicographic comparison works because the format sorts correctly.

/// Delegate that trusts all SSL certificates (needed for Zscaler proxy interception).
private class ZscalerTrustDelegate: NSObject, URLSessionDelegate {
    static let shared = ZscalerTrustDelegate()
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

actor UpdateService {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: ZscalerTrustDelegate.shared, delegateQueue: nil)
    }()

    struct Release: Sendable {
        let version: String      // tag name without "v" prefix
        let name: String
        let body: String         // release notes (markdown)
        let dmgURL: String       // download URL for the first .dmg asset
        let publishedAt: String
    }

    private let apiURL = "https://api.github.com/repos/ascarcel-boomi/Boomi-SRE/releases/latest"

    // MARK: - Check for Update

    /// Returns the latest GitHub release if it's newer than currentVersion, else nil.
    func checkForUpdate(currentVersion: String) async throws -> Release? {
        var request = URLRequest(url: URL(string: apiURL)!, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil   // Not found (no releases yet) or network error — silent fail
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else { return nil }

        let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        // Lexicographic comparison works for YY.MM.DD-HHMMSS format
        guard remoteVersion > currentVersion else { return nil }

        // Find the first .dmg asset
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmgURL = assets.compactMap { a -> String? in
            guard let name = a["name"] as? String, name.hasSuffix(".dmg"),
                  let url = a["browser_download_url"] as? String else { return nil }
            return url
        }.first ?? ""

        return Release(
            version: remoteVersion,
            name: json["name"] as? String ?? tagName,
            body: json["body"] as? String ?? "",
            dmgURL: dmgURL,
            publishedAt: String((json["published_at"] as? String ?? "").prefix(10))
        )
    }

    // MARK: - Download Update

    /// Download the DMG to a temp file, reporting real-time progress via the handler.
    /// Uses URLSession.bytes(from:) for streaming so progress is updated throughout the download.
    func downloadUpdate(dmgURL: String, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        guard let url = URL(string: dmgURL) else {
            throw UpdateError.invalidURL
        }
        let localURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BoomiSRE_update.dmg")
        try? FileManager.default.removeItem(at: localURL)

        let (asyncBytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let expectedLength = http.expectedContentLength
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(expectedLength)) }

        for try await byte in asyncBytes {
            data.append(byte)
            // Report progress every 64 KB to avoid flooding the main thread
            if expectedLength > 0 && data.count % 65536 == 0 {
                progressHandler(Double(data.count) / Double(expectedLength))
            }
        }

        try data.write(to: localURL)
        progressHandler(1.0)
        return localURL
    }

    // MARK: - Apply Update

    /// Mount the DMG, write an updater script, launch it, and exit the app.
    ///
    /// The updater script:
    /// 1. Waits 2 seconds for the app to quit
    /// 2. Copies the new .app from the mounted volume to /Applications
    /// 3. Relaunches the app
    /// 4. Self-deletes
    func applyUpdate(dmgPath: URL) async throws {
        // Mount the DMG
        let (mountOutput, mountCode) = try await AWSCLIRunner.runShell(
            "/usr/bin/hdiutil",
            arguments: ["attach", dmgPath.path, "-nobrowse", "-quiet", "-mountpoint", "/Volumes/BoomiSRE_Update"]
        )
        guard mountCode == 0 else {
            throw UpdateError.mountFailed(mountOutput)
        }

        // Write the updater shell script
        let scriptPath = "/tmp/boomi_sre_update.sh"
        let newAppPath = "/Volumes/BoomiSRE_Update/Boomi SRE.app"
        // CRITICAL: Delete the existing app BEFORE copying.
        // Without rm -rf first, cp -R copies the new .app INTO the existing .app
        // directory, creating recursive nested bundles (24MB × N updates = 731MB after 30 updates).
        let scriptContent = """
        #!/bin/bash
        sleep 2
        rm -rf "/Applications/Boomi SRE.app"
        cp -R "\(newAppPath)" "/Applications/Boomi SRE.app"
        hdiutil detach "/Volumes/BoomiSRE_Update" -quiet 2>/dev/null || true
        open -a "Boomi SRE"
        rm "$0"
        """
        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make it executable
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try chmod.run()
        chmod.waitUntilExit()

        // Launch the updater in the background
        let updater = Process()
        updater.executableURL = URL(fileURLWithPath: "/bin/bash")
        updater.arguments = [scriptPath]
        try updater.run()

        // Exit current app (the updater will relaunch it)
        await MainActor.run { NSApp.terminate(nil) }
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidURL
    case downloadFailed
    case mountFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL for update"
        case .downloadFailed: return "Failed to download the update"
        case .mountFailed(let msg): return "Failed to mount update DMG: \(msg)"
        }
    }
}

// MARK: - AWSCLIRunner extension for generic shell commands

extension AWSCLIRunner {
    /// Run an arbitrary executable (not necessarily AWS CLI).
    static func runShell(_ executable: String, arguments: [String]) async throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: stdoutData, encoding: .utf8) ?? ""
        let err = String(data: stderrData, encoding: .utf8) ?? ""
        let output = process.terminationStatus == 0 ? out : (err.isEmpty ? out : err)
        return (output, process.terminationStatus)
    }
}

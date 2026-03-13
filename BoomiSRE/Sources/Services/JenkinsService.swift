import Foundation

// MARK: - Models

struct JenkinsJob: Identifiable, Hashable, Equatable, Sendable {
    var id: String { name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: JenkinsJob, rhs: JenkinsJob) -> Bool { lhs.name == rhs.name }
    let name: String
    let url: String
    let color: String     // "blue", "red", "yellow", "notbuilt", "disabled", "blue_anime" (running)

    var statusLabel: String {
        if color.hasSuffix("_anime") { return "Running" }
        switch color {
        case "blue":     return "Success"
        case "red":      return "Failure"
        case "yellow":   return "Unstable"
        case "disabled": return "Disabled"
        default:         return "Not Built"
        }
    }

    var statusIcon: String {
        if color.hasSuffix("_anime") { return "arrow.triangle.2.circlepath" }
        switch color {
        case "blue":   return "checkmark.circle.fill"
        case "red":    return "xmark.circle.fill"
        case "yellow": return "exclamationmark.triangle.fill"
        default:       return "circle"
        }
    }
}

struct JenkinsBuild: Identifiable, Hashable, Equatable, Sendable {
    var id: String { "\(number)" }
    func hash(into hasher: inout Hasher) { hasher.combine(number) }
    static func == (lhs: JenkinsBuild, rhs: JenkinsBuild) -> Bool { lhs.number == rhs.number }
    let number: Int
    let result: String?      // "SUCCESS", "FAILURE", "UNSTABLE", "ABORTED", nil = running
    let timestampMs: Double
    let durationMs: Double
    let url: String

    var isRunning: Bool { result == nil }
    var displayResult: String { result ?? "RUNNING" }

    var date: Date { Date(timeIntervalSince1970: timestampMs / 1000) }

    var formattedDuration: String {
        let secs = Int(durationMs / 1000)
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }
}

// MARK: - SSL-bypass delegate (for usw2.mashspud.com which is behind Zscaler)

private final class InsecureSSLDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = InsecureSSLDelegate()
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Service

/// Jenkins REST API client.
actor JenkinsService {

    // MARK: - Jobs

    func listJobs(baseURL: String, username: String, token: String) async throws -> [JenkinsJob] {
        let url = "\(baseURL.trimSlash)/api/json?tree=jobs[name,url,color]"
        let (data, response) = try await request(url, username: username, token: token)
        try validate(response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else { return [] }
        return jobs.compactMap { j in
            guard let name = j["name"] as? String,
                  let url = j["url"] as? String else { return nil }
            return JenkinsJob(name: name, url: url, color: j["color"] as? String ?? "notbuilt")
        }
    }

    // MARK: - Builds

    func getBuildHistory(
        baseURL: String, jobName: String, username: String, token: String, limit: Int = 20
    ) async throws -> [JenkinsBuild] {
        let encoded = jobName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobName
        let url = "\(baseURL.trimSlash)/job/\(encoded)/api/json?tree=builds[number,result,timestamp,duration,url]"
        let (data, response) = try await request(url, username: username, token: token)
        try validate(response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let builds = json["builds"] as? [[String: Any]] else { return [] }
        return Array(builds.prefix(limit).compactMap { b in
            guard let number = b["number"] as? Int,
                  let url = b["url"] as? String else { return nil }
            return JenkinsBuild(
                number: number,
                result: b["result"] as? String,
                timestampMs: b["timestamp"] as? Double ?? 0,
                durationMs: b["duration"] as? Double ?? 0,
                url: url
            )
        })
    }

    // MARK: - Console Output

    func getConsoleOutput(
        baseURL: String, jobName: String, buildNumber: Int, username: String, token: String
    ) async throws -> String {
        let encoded = jobName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobName
        let url = "\(baseURL.trimSlash)/job/\(encoded)/\(buildNumber)/consoleText"
        let (data, response) = try await request(url, username: username, token: token)
        // Console text returns 200 even for running builds
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Jenkins", status:
                (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Private

    private func request(_ urlString: String, username: String, token: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else {
            throw ServiceError.httpError(service: "Jenkins", status: 0, body: "Invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        if let data = "\(username):\(token)".data(using: .utf8) {
            req.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        // Use SSL-bypassing session for USW2 host (Zscaler certificate incompatibility)
        let session: URLSession = urlString.contains("usw2")
            ? URLSession(configuration: .default, delegate: InsecureSSLDelegate.shared, delegateQueue: nil)
            : URLSession.shared
        return try await session.data(for: req)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(service: "Jenkins", status:
                (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }
    }
}

private extension String {
    var trimSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

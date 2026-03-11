import Foundation
import SwiftUI

/// Central app state shared across all views.
final class AppState: ObservableObject {
    // Navigation
    @Published var selectedReport: ReportItem?
    @Published var sidebarCollapsed = false
    @Published var viewMode: ViewMode = .chart

    // Report results
    @Published var results: [String: ReportResult] = [:]
    @Published var runningReports: Set<String> = []

    // Config (persisted)
    @Published var csvFolder: String
    @Published var awsSSOProfile: String
    @Published var jiraEmail: String
    @Published var jiraBaseURL: String
    @Published var jiraProjectKeys: [String]

    // Auth status (transient)
    @Published var awsAuthStatus: AuthStatus = .unknown
    @Published var jiraAuthStatus: AuthStatus = .unknown

    private let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configURL = home.appendingPathComponent(".boomi_sre_config.json")
        self.csvFolder = home.appendingPathComponent("Downloads").path
        self.awsSSOProfile = "cam-prod-ro-json"
        self.jiraEmail = ""
        self.jiraBaseURL = "https://boomii.atlassian.net"
        self.jiraProjectKeys = ["CAMSRE", "SRE"]

        loadConfig()
    }

    // MARK: - Config persistence

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
        if let v = config.csvFolder { csvFolder = v }
        if let v = config.awsSSOProfile { awsSSOProfile = v }
        if let v = config.jiraEmail { jiraEmail = v }
        if let v = config.jiraBaseURL { jiraBaseURL = v }
        if let v = config.jiraProjectKeys { jiraProjectKeys = v }
    }

    func saveConfig() {
        let config = AppConfig(
            csvFolder: csvFolder,
            awsSSOProfile: awsSSOProfile,
            jiraEmail: jiraEmail,
            jiraBaseURL: jiraBaseURL,
            jiraProjectKeys: jiraProjectKeys
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    // MARK: - Jira token (Keychain)

    var jiraAPIToken: String {
        get { KeychainHelper.load(key: "jira-api-token") ?? "" }
        set {
            try? KeychainHelper.save(key: "jira-api-token", value: newValue)
            objectWillChange.send()
        }
    }

    var isJiraConfigured: Bool {
        !jiraEmail.isEmpty && !jiraAPIToken.isEmpty && !jiraBaseURL.isEmpty
    }

    var isAWSConfigured: Bool {
        !awsSSOProfile.isEmpty
    }
}

// MARK: - Supporting types

struct AppConfig: Codable {
    var csvFolder: String?
    var awsSSOProfile: String?
    var jiraEmail: String?
    var jiraBaseURL: String?
    var jiraProjectKeys: [String]?
}

enum ViewMode: String, CaseIterable {
    case table = "Table"
    case chart = "Chart"
}

enum AuthStatus: Equatable {
    case unknown
    case checking
    case authenticated(detail: String)
    case expired
    case notConfigured
    case error(String)

    var isOK: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking..."
        case .authenticated(let detail): return "Connected: \(detail)"
        case .expired: return "Session expired"
        case .notConfigured: return "Not configured"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .authenticated: return .green
        case .expired, .error: return .red
        case .checking: return .orange
        default: return .secondary
        }
    }
}

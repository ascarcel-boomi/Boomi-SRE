import Foundation
import SwiftUI

/// Central app state shared across all views.
final class AppState: ObservableObject {
    // Navigation
    @Published var selectedReport: ReportItem?
    @Published var showSettings = false
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

    // AWS account name cache: accountId -> friendly name (persisted)
    @Published var awsAccountNames: [String: String] = [:]

    // Auth status (transient)
    @Published var awsAuthStatus: AuthStatus = .unknown
    @Published var jiraAuthStatus: AuthStatus = .unknown
    @Published var confluenceAuthStatus: AuthStatus = .unknown
    @Published var bitbucketAuthStatus: AuthStatus = .unknown
    @Published var githubAuthStatus: AuthStatus = .unknown

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
        if let v = config.awsAccountNames { awsAccountNames = v }
    }

    func saveConfig() {
        let config = AppConfig(
            csvFolder: csvFolder,
            awsSSOProfile: awsSSOProfile,
            jiraEmail: jiraEmail,
            jiraBaseURL: jiraBaseURL,
            jiraProjectKeys: jiraProjectKeys,
            awsAccountNames: awsAccountNames
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    // MARK: - Keychain-backed tokens

    var jiraAPIToken: String {
        get { KeychainHelper.load(key: "jira-api-token") ?? "" }
        set { try? KeychainHelper.save(key: "jira-api-token", value: newValue); objectWillChange.send() }
    }

    var confluenceAPIToken: String {
        get { KeychainHelper.load(key: "confluence-api-token") ?? "" }
        set { try? KeychainHelper.save(key: "confluence-api-token", value: newValue); objectWillChange.send() }
    }

    var bitbucketAPIToken: String {
        get { KeychainHelper.load(key: "bitbucket-api-token") ?? "" }
        set { try? KeychainHelper.save(key: "bitbucket-api-token", value: newValue); objectWillChange.send() }
    }

    var githubToken: String {
        get { KeychainHelper.load(key: "github-token") ?? "" }
        set { try? KeychainHelper.save(key: "github-token", value: newValue); objectWillChange.send() }
    }

    var isJiraConfigured: Bool {
        !jiraEmail.isEmpty && !jiraAPIToken.isEmpty && !jiraBaseURL.isEmpty
    }

    var isAWSConfigured: Bool {
        !awsSSOProfile.isEmpty
    }

    // MARK: - Startup health checks

    /// Check all configured services in parallel on app launch.
    func checkAllServices() {
        let awsService = AWSAuthService()
        let jiraService = JiraService()
        let confluenceService = ConfluenceService()
        let bitbucketService = BitbucketService()
        let githubService = GitHubService()

        // AWS
        if !awsSSOProfile.isEmpty {
            awsAuthStatus = .checking
            let profile = awsSSOProfile
            Task {
                do {
                    let detail = try await awsService.checkStatus(profile: profile)
                    await MainActor.run { self.awsAuthStatus = .authenticated(detail: detail) }
                } catch is AWSAuthError {
                    await MainActor.run { self.awsAuthStatus = .expired }
                } catch {
                    await MainActor.run { self.awsAuthStatus = .error(error.localizedDescription) }
                }
            }
        }

        // Jira
        if isJiraConfigured {
            jiraAuthStatus = .checking
            let (baseURL, email, token) = (jiraBaseURL, jiraEmail, jiraAPIToken)
            Task {
                do {
                    let name = try await jiraService.checkAuth(baseURL: baseURL, email: email, apiToken: token)
                    await MainActor.run { self.jiraAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.jiraAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            jiraAuthStatus = .notConfigured
        }

        // Confluence
        let confToken = confluenceAPIToken
        if !confToken.isEmpty && !jiraEmail.isEmpty {
            confluenceAuthStatus = .checking
            let (baseURL, email) = (jiraBaseURL, jiraEmail)
            Task {
                do {
                    let name = try await confluenceService.checkAuth(baseURL: baseURL, email: email, apiToken: confToken)
                    await MainActor.run { self.confluenceAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.confluenceAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            confluenceAuthStatus = confToken.isEmpty ? .notConfigured : .notConfigured
        }

        // Bitbucket
        let bbToken = bitbucketAPIToken
        if !bbToken.isEmpty && !jiraEmail.isEmpty {
            bitbucketAuthStatus = .checking
            let email = jiraEmail
            Task {
                do {
                    let name = try await bitbucketService.checkAuth(email: email, apiToken: bbToken)
                    await MainActor.run { self.bitbucketAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.bitbucketAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            bitbucketAuthStatus = .notConfigured
        }

        // GitHub
        let ghToken = githubToken
        if !ghToken.isEmpty {
            githubAuthStatus = .checking
            Task {
                do {
                    let name = try await githubService.checkAuth(token: ghToken)
                    await MainActor.run { self.githubAuthStatus = .authenticated(detail: name) }
                } catch {
                    await MainActor.run { self.githubAuthStatus = .error(error.localizedDescription) }
                }
            }
        } else {
            githubAuthStatus = .notConfigured
        }
    }
}

// MARK: - Supporting types

struct AppConfig: Codable {
    var csvFolder: String?
    var awsSSOProfile: String?
    var jiraEmail: String?
    var jiraBaseURL: String?
    var jiraProjectKeys: [String]?
    var awsAccountNames: [String: String]?  // accountId -> friendly name
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

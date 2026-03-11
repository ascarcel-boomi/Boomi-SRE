import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AWSSettingsTab()
                .tabItem { Label("AWS", systemImage: "cloud") }
            JiraSettingsTab()
                .tabItem { Label("Jira", systemImage: "ticket") }
        }
        .frame(width: 580, height: 440)
    }
}

// MARK: - AWS Tab

struct AWSSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var profiles: [String] = []
    @State private var isLoggingIn = false

    private let awsAuth = AWSAuthService()

    var body: some View {
        Form {
            Section("SSO Profile") {
                Picker("Profile", selection: $appState.awsSSOProfile) {
                    ForEach(profiles, id: \.self) { profile in
                        Text(profile).tag(profile)
                    }
                }
                .onAppear { profiles = awsAuth.listProfiles() }
                .onChange(of: appState.awsSSOProfile) { appState.saveConfig() }
            }

            Section("Authentication") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.awsAuthStatus.color)
                        .frame(width: 10, height: 10)
                    Text(appState.awsAuthStatus.label)
                        .font(.callout)
                        .foregroundStyle(appState.awsAuthStatus.color)
                    Spacer()
                }

                HStack {
                    Button("Login with SSO") {
                        loginSSO()
                    }
                    .disabled(isLoggingIn)

                    Button("Check Status") {
                        checkAWS()
                    }
                    .disabled(isLoggingIn)

                    if isLoggingIn {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }

            Section {
                Text("AWS SSO login opens your browser for device authorization. After approving, return here and click \"Check Status\" to verify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { checkAWS() }
    }

    private func loginSSO() {
        isLoggingIn = true
        appState.awsAuthStatus = .checking
        Task {
            do {
                _ = try await awsAuth.login(profile: appState.awsSSOProfile)
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run {
                    appState.awsAuthStatus = .authenticated(detail: detail)
                    isLoggingIn = false
                }
            } catch {
                await MainActor.run {
                    appState.awsAuthStatus = .error(error.localizedDescription)
                    isLoggingIn = false
                }
            }
        }
    }

    private func checkAWS() {
        appState.awsAuthStatus = .checking
        Task {
            do {
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run {
                    appState.awsAuthStatus = .authenticated(detail: detail)
                }
            } catch is AWSAuthError {
                await MainActor.run { appState.awsAuthStatus = .expired }
            } catch {
                await MainActor.run {
                    appState.awsAuthStatus = .error(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Jira Tab

struct JiraSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField: String = ""
    @State private var projectKeysField: String = ""
    @State private var isTesting = false
    @State private var saved = false

    private let jiraService = JiraService()

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Base URL", text: $appState.jiraBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $appState.jiraEmail)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Token", text: $tokenField)
                    .textFieldStyle(.roundedBorder)

                Link("Get your API token from Atlassian",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
            }

            Section("Projects") {
                TextField("Project keys (comma-separated)", text: $projectKeysField)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. CAMSRE, SRE")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Authentication") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.jiraAuthStatus.color)
                        .frame(width: 10, height: 10)
                    Text(appState.jiraAuthStatus.label)
                        .font(.callout)
                        .foregroundStyle(appState.jiraAuthStatus.color)
                    Spacer()
                }

                HStack {
                    Button("Test Connection") {
                        testJira()
                    }
                    .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)

                    Button("Save") {
                        saveJira()
                    }

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if saved {
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            tokenField = appState.jiraAPIToken
            projectKeysField = appState.jiraProjectKeys.joined(separator: ", ")
            if appState.isJiraConfigured {
                testJira()
            }
        }
    }

    private func saveJira() {
        appState.jiraAPIToken = tokenField
        appState.jiraProjectKeys = projectKeysField
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        appState.saveConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testJira() {
        isTesting = true
        appState.jiraAuthStatus = .checking
        let baseURL = appState.jiraBaseURL
        let email = appState.jiraEmail
        let token = tokenField

        Task {
            do {
                let name = try await jiraService.checkAuth(
                    baseURL: baseURL, email: email, apiToken: token
                )
                await MainActor.run {
                    appState.jiraAuthStatus = .authenticated(detail: name)
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    appState.jiraAuthStatus = .error(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

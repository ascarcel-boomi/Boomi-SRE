import SwiftUI

@main
struct BoomiSREApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    appState.checkAllServices()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            aiMenu
            jiraMenu
            awsMenu
            googleMenu
            favoritesMenu
            viewCommands
        }
    }

    // MARK: - AI Menu

    @CommandsBuilder
    private var aiMenu: some Commands {
        CommandMenu("AI") {
            Button("AI Copilot") { navigateTo("copilot_chat") }
                .keyboardShortcut("/", modifiers: .command)
        }
    }

    // MARK: - Jira Menu

    @CommandsBuilder
    private var jiraMenu: some Commands {
        CommandMenu("Jira") {
            Button("My TODO") { navigateTo("jira_todo") }
                .keyboardShortcut("1", modifiers: .command)

            Button("Saved Filters") { navigateTo("jira_filters") }
                .keyboardShortcut("2", modifiers: .command)

            Button("Boards") { navigateTo("jira_boards") }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Status: \(statusText(appState.jiraAuthStatus))") { }
                .disabled(true)
        }
    }

    // MARK: - AWS Menu

    @CommandsBuilder
    private var awsMenu: some Commands {
        CommandMenu("AWS") {
            Button("Cost Explorer") { navigateTo("aws_cost_explorer") }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Status: \(statusText(appState.awsAuthStatus))") { }
                .disabled(true)
        }
    }

    // MARK: - Google Menu

    @CommandsBuilder
    private var googleMenu: some Commands {
        CommandMenu("Google") {
            Button("Gmail") { navigateTo("google_gmail") }
                .keyboardShortcut("5", modifiers: .command)

            Button("Calendar") { navigateTo("google_calendar") }
                .keyboardShortcut("6", modifiers: .command)

            Button("Chat") { navigateTo("google_chat") }
                .keyboardShortcut("7", modifiers: .command)

            Divider()

            Button("Status: \(statusText(appState.googleAuthStatus))") { }
                .disabled(true)
        }
    }

    // MARK: - Favorites Menu

    @CommandsBuilder
    private var favoritesMenu: some Commands {
        CommandMenu("Favorites") {
            if appState.favoriteAWSProfiles.isEmpty
                && appState.favoriteJiraProjects.isEmpty
                && appState.favoriteConfluenceSpaces.isEmpty {
                Text("No favorites configured")
            } else {
                if !appState.favoriteAWSProfiles.isEmpty {
                    Section("AWS Profiles") {
                        ForEach(appState.favoriteAWSProfiles, id: \.self) { profile in
                            Button(profile) {
                                appState.awsSSOProfile = profile
                                appState.saveConfig()
                            }
                        }
                    }
                }

                if !appState.favoriteJiraProjects.isEmpty {
                    Section("Jira Projects") {
                        ForEach(appState.favoriteJiraProjects, id: \.self) { project in
                            Button(project) {
                                navigateTo("jira_boards")
                            }
                        }
                    }
                }

                if !appState.favoriteConfluenceSpaces.isEmpty {
                    Section("Confluence Spaces") {
                        ForEach(appState.favoriteConfluenceSpaces, id: \.self) { space in
                            Button(space) { }
                        }
                    }
                }
            }
        }
    }

    // MARK: - View Commands

    @CommandsBuilder
    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                appState.refreshTrigger = UUID()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Re-check All Services") {
                appState.checkAllServices()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Home") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedTicketKey = nil
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Settings") {
                appState.selectedReport = nil
                appState.selectedTicketKey = nil
                appState.showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    // MARK: - Helpers

    private func navigateTo(_ reportId: String) {
        appState.showSettings = false
        appState.selectedTicketKey = nil
        appState.selectedReport = ReportCatalog.all.first { $0.id == reportId }
    }

    private func statusText(_ status: AuthStatus) -> String {
        switch status {
        case .authenticated: return "Connected"
        case .expired: return "Session Expired"
        case .checking: return "Checking..."
        case .notConfigured: return "Not Configured"
        case .error: return "Error"
        case .unknown: return "Not Checked"
        }
    }
}

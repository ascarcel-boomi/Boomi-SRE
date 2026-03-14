import SwiftUI

@main
struct BoomiSREApp: App {
    @StateObject private var appState        = AppState()
    @StateObject private var notificationVM  = NotificationViewModel()
    @StateObject private var updateVM        = UpdateViewModel()
    @State private var showResetConfirm      = false
    @State private var showFeatureRequest    = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(notificationVM)
                .environmentObject(updateVM)
                .frame(minWidth: 1000, minHeight: 700)
                .sheet(isPresented: Binding(
                    get: { !appState.hasCompletedOnboarding },
                    set: { if !$0 { appState.hasCompletedOnboarding = true; appState.saveConfig() } }
                )) {
                    OnboardingWizardView()
                        .environmentObject(appState)
                        .environmentObject(notificationVM)
                }
                .onAppear {
                    appState.checkAllServices()
                    // Start background notification polling after a short delay
                    // to let auth checks complete first
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
                        await appState.discoverProfile()
                        notificationVM.startPolling(appState: appState)
                        appState.startBackgroundRefresh()
                        // Check for updates 10 seconds after launch
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        await updateVM.checkForUpdate()
                    }
                }
                .onDisappear {
                    notificationVM.stopPolling()
                    appState.stopBackgroundRefresh()
                }
                .alert("Factory Reset", isPresented: $showResetConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) { appState.factoryReset() }
                } message: {
                    Text("This will reset all app settings, clear notifications, incidents, chat history, and saved credentials. Your AWS config (~/.aws/), MCP credentials (~/.kiro/), and Git config are NOT affected.\n\nThe app will restart with the Onboarding Wizard.")
                }
                .sheet(isPresented: $showFeatureRequest) {
                    FeatureRequestView()
                        .environmentObject(appState)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Boomi SRE") {
                    showAboutPanel()
                }
            }
            aiMenu
            jiraMenu
            awsMenu
            googleMenu
            favoritesMenu
            viewCommands
            helpCommands
        }
    }

    // MARK: - AI Menu

    @CommandsBuilder
    private var aiMenu: some Commands {
        CommandMenu("AI") {
            Button("Notifications") { navigateTo("notifications") }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Incidents") { navigateTo("incidents") }
                .keyboardShortcut("i", modifiers: .command)

            Button("AI Copilot") { navigateTo("copilot_chat") }
                .keyboardShortcut("/", modifiers: .command)

            Button("Executive Assistant") { navigateTo("exec_assistant") }
                .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Refresh Notifications Now") {
                Task { await notificationVM.pollAllServices(appState: appState) }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
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

    // MARK: - Help Menu

    @CommandsBuilder
    private var helpCommands: some Commands {
        CommandGroup(after: .help) {
            Button("Submit Feedback…") {
                showFeatureRequest = true
            }

            Divider()

            Button("Factory Reset…") {
                showResetConfirm = true
            }
        }
    }
}

import SwiftUI

@main
struct BoomiSREApp: App {
    @StateObject private var appState        = AppState()
    @StateObject private var notificationVM  = NotificationViewModel()
    @StateObject private var updateVM        = UpdateViewModel()
    @StateObject private var bitbucketVM     = BitbucketBrowserViewModel()
    @StateObject private var githubVM        = GitHubBrowserViewModel()
    @State private var showResetConfirm      = false
    @State private var showFeatureRequest    = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(notificationVM)
                .environmentObject(updateVM)
                .environmentObject(bitbucketVM)
                .environmentObject(githubVM)
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
                    // One-time cleanup of nested bundles created by the old buggy updater.
                    // The old cp -R without rm -rf first created Boomi SRE.app/Boomi SRE.app/...
                    cleanNestedAppBundles()
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
                Divider()
                Button(updateVM.availableUpdate != nil
                       ? "Check for Updates… (Update Available)"
                       : "Check for Updates…") {
                    appState.selectedSettingsTab = "about"
                    appState.selectedReport = nil
                    appState.showSettings = true
                }
            }
            commandCenterMenu
            workMenu
            infrastructureMenu
            browseMenu
            favoritesMenu
            viewCommands
            helpCommands
        }
    }

    // MARK: - Command Center Menu

    @CommandsBuilder
    private var commandCenterMenu: some Commands {
        CommandMenu("Command Center") {
            Button("Notifications") { navigateTo("notifications") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Incidents") { navigateTo("incidents") }
                .keyboardShortcut("i", modifiers: .command)
            Button("On-Call") { navigateTo("oncall") }
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

    // MARK: - Work Menu

    @CommandsBuilder
    private var workMenu: some Commands {
        CommandMenu("Work") {
            Button("My TODO") { navigateTo("jira_todo") }
                .keyboardShortcut("1", modifiers: .command)
            Button("Saved Filters") { navigateTo("jira_filters") }
                .keyboardShortcut("2", modifiers: .command)
            Button("Boards") { navigateTo("jira_boards") }
                .keyboardShortcut("3", modifiers: .command)
        }
    }

    // MARK: - Infrastructure Menu

    @CommandsBuilder
    private var infrastructureMenu: some Commands {
        CommandMenu("Infrastructure") {
            Button("AWS Health") { navigateTo("aws_health") }
            Button("AWS Costs") { navigateTo("aws_cost_explorer") }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
            Button("Status: \(statusText(appState.awsAuthStatus))") { }.disabled(true)
        }
    }

    // MARK: - Browse Menu (Observability, Source Control, Automation, Knowledge, Communication)

    @CommandsBuilder
    private var browseMenu: some Commands {
        CommandMenu("Browse") {
            Section("Observability") {
                Button("Grafana") { navigateTo("grafana_browser") }
            }
            Section("Source Control") {
                Button("GitHub") { navigateTo("github_browser") }
                Button("Bitbucket") { navigateTo("bitbucket_browser") }
            }
            Section("Automation") {
                Button("Jenkins") { navigateTo("jenkins_browser") }
            }
            Section("Knowledge") {
                Button("Knowledge Base") { navigateTo("knowledge_base") }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Confluence") { navigateTo("confluence_browser") }
            }
            Section("Communication") {
                Button("Gmail") { navigateTo("google_gmail") }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Calendar") { navigateTo("google_calendar") }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Chat") { navigateTo("google_chat") }
                    .keyboardShortcut("7", modifiers: .command)
            }
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
            Button("Knowledge Base") {
                navigateTo("knowledge_base")
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("SOPs") {
                navigateTo("knowledge_base")
            }

            Button("Search Boomi Docs") {
                NSWorkspace.shared.open(URL(string: "https://help.boomi.com/")!)
            }

            Divider()

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

// MARK: - Nested Bundle Cleanup

/// Remove the nested app bundle created by the old buggy updater.
/// The old update script used `cp -R src dst` without deleting dst first,
/// which copied the .app INTO the existing .app directory recursively.
private func cleanNestedAppBundles() {
    let nestedPath = "/Applications/Boomi SRE.app/Boomi SRE.app"
    guard FileManager.default.fileExists(atPath: nestedPath) else { return }
    do {
        try FileManager.default.removeItem(atPath: nestedPath)
        print("[Cleanup] Removed nested app bundle — app size should now be ~24 MB")
    } catch {
        print("[Cleanup] Could not remove nested bundle: \(error.localizedDescription)")
    }
}

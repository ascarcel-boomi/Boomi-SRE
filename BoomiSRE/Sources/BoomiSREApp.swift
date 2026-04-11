import SwiftUI

@main
struct BoomiSREApp: App {
    @StateObject private var appState        = AppState()
    @State private var notificationVM  = NotificationViewModel()
    @State private var updateVM        = UpdateViewModel()
    @State private var bitbucketVM     = BitbucketBrowserViewModel()
    @State private var githubVM        = GitHubBrowserViewModel()
    @State private var chatVM          = ChatViewModel()
    @State private var onCallVM        = OnCallViewModel()
    @State private var skillsVM        = SkillsViewModel()
    @State private var presenceVM      = TeamPresenceViewModel()
    @State private var dashboardVM     = DashboardViewModel()
    @State private var showFeatureRequest    = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(notificationVM)
                .environment(updateVM)
                .environment(bitbucketVM)
                .environment(githubVM)
                .environment(chatVM)
                .environment(onCallVM)
                .environment(skillsVM)
                .environment(presenceVM)
                .environment(dashboardVM)
                .tint(appState.appTheme == "boomi" ? BoomiColors.boomiPurple : nil)
                .appTheme(appState.appTheme)
                .frame(minWidth: 1000, minHeight: 700)
                .sheet(isPresented: Binding(
                    get: { !appState.hasCompletedOnboarding },
                    set: { if !$0 { appState.hasCompletedOnboarding = true; appState.saveConfig() } }
                )) {
                    OnboardingWizardView()
                        .environmentObject(appState)
                        .environment(notificationVM)
                }
                .onAppear {
                    // Always start at Home on launch regardless of last persisted state
                    appState.selectedSidebarItem = "home"
                    appState.pendingTabId = nil
                    appState.selectedTicketKey = nil
                    appState.showSettings = false
                    // One-time cleanup of nested bundles created by the old buggy updater.
                    // The old cp -R without rm -rf first created Boomi SRE.app/Boomi SRE.app/...
                    cleanNestedAppBundles()
                    appState.checkAllServices()
                    _ = bitbucketVM.loadFromCache()
                    // Start background notification polling after a short delay
                    // to let auth checks complete first
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
                        await appState.discoverProfile()
                        notificationVM.startPolling(appState: appState)
                        await bitbucketVM.preloadMappedRepos(appState: appState)
                        appState.startBackgroundRefresh()
                        // Auto-summary on launch if enabled
                        if appState.copilotAutoSummaryOnLaunch && ClaudeService().isAIAvailable {
                            appState.pendingCopilotPrompt = "Give me a brief status update — what's happening across my services right now? Check alerts, recent incidents, and any failed builds."
                        }
                        // Check for updates 10 seconds after launch
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        await updateVM.checkForUpdate()
                    }
                }
                .onDisappear {
                    notificationVM.stopPolling()
                    appState.stopBackgroundRefresh()
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
            navigateMenu
            viewCommands
            helpCommands
            // Disable "Show Tab Bar" — it creates duplicate tabs with no useful purpose
            CommandGroup(replacing: .toolbar) { }
            // Replace built-in Help entry with a disabled placeholder until help docs are built
            CommandGroup(replacing: .help) {
                Button("Boomi SRE Help") { }
                    .disabled(true)
            }
        }
    }

    // MARK: - Navigate Menu

    @CommandsBuilder
    private var navigateMenu: some Commands {
        CommandMenu("Navigate") {
            Button("Home") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "home"
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Alerts & On-Call") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "alerts"
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Incidents") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "incidents"
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("My Work") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "mywork"
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Infrastructure") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "infra"
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Knowledge & Tools") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "knowledge"
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("Communicate") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "communicate"
            }
            .keyboardShortcut("6", modifiers: .command)

            Divider()

            Button("AI Copilot (Home)") {
                appState.selectedReport = nil
                appState.showSettings = false
                appState.selectedSidebarItem = "home"
            }
            .keyboardShortcut("/", modifiers: .command)

            Button("Notifications") { navigateTo("notifications") }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Executive Assistant") { navigateTo("exec_assistant") }
                .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Refresh Notifications Now") {
                Task { await notificationVM.pollAllServices(appState: appState) }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
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
                appState.selectedSidebarItem = "home"
            }

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
        appState.navigate(to: reportId)
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
                appState.pendingKBFilter = "SOPs"
            }

            Button("Search Boomi Docs") {
                if let docsURL = URL(string: "https://help.boomi.com/") {
                    NSWorkspace.shared.open(docsURL)
                }
            }

            Divider()

            Button("Submit Feedback…") {
                showFeatureRequest = true
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

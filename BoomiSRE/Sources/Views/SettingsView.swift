import SwiftUI

/// Inline settings panel displayed in the main content area.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    // Backed by appState so the menu item "Check for Updates..." can deep-link here
    private var selectedTab: String {
        get { appState.selectedSettingsTab }
        nonmutating set { appState.selectedSettingsTab = newValue }
    }
    @State private var discoveryResult: String?
    @State private var discoveryIsError = false
    @State private var showResetConfirm = false
    @State private var showFeatureRequest = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with auto-discover button
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button {
                    runDiscovery()
                } label: {
                    Label("Auto-discover Credentials", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Discovery result banner
            if let result = discoveryResult {
                HStack(spacing: 8) {
                    Image(systemName: discoveryIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    Text(result)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button { discoveryResult = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(discoveryIsError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .foregroundStyle(discoveryIsError ? .red : .green)
            }

            Divider()

            // Corporate identity card — shown when an email is known
            if !appState.jiraEmail.isEmpty || !appState.userProfile.email.isEmpty {
                let email = appState.jiraEmail.isEmpty ? appState.userProfile.email : appState.jiraEmail
                HStack(spacing: 12) {
                    Image(systemName: "key.fill").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Corporate Identity").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(email).font(.callout).textSelection(.enabled)
                        Text("SSO services (Confluence, Grafana) use your Okta session — sign in once, stay signed in. API services need a personal token (see each tab).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        selectedTab = "profile"
                    } label: {
                        Label("Edit Profile", systemImage: "person.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.05))

                Divider()
            }

            HStack(spacing: 0) {
                // Left tab bar
                VStack(alignment: .leading, spacing: 2) {
                    // GENERAL
                    sectionHeader("GENERAL")
                    settingsTab("profile", label: "Profile", icon: "person.circle", status: nil)
                    settingsTab("appearance", label: "Appearance", icon: "paintpalette", status: nil)
                    settingsTab("ai", label: "AI", icon: "sparkles", status: nil)

                    Divider().padding(.vertical, 4)

                    // INTEGRATIONS
                    sectionHeader("INTEGRATIONS")
                    settingsTab("integrations", label: "Overview", icon: "network", status: nil)
                    settingsTab("jira", label: "Jira", icon: "ticket", status: appState.jiraAuthStatus)
                    settingsTab("aws", label: "AWS SSO", icon: "cloud", status: appState.awsAuthStatus)
                    settingsTab("grafana", label: "Grafana", icon: "chart.line.uptrend.xyaxis", status: appState.grafanaAuthStatus)
                    settingsTab("github", label: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: appState.githubAuthStatus)
                    settingsTab("bitbucket", label: "Bitbucket", icon: "externaldrive.connected.to.line.below", status: appState.bitbucketAuthStatus)
                    settingsTab("jenkins", label: "Jenkins", icon: "hammer", status: appState.jenkinsAuthStatus)
                    settingsTab("confluence", label: "Confluence", icon: "book.closed", status: appState.confluenceAuthStatus)
                    settingsTab("google", label: "Google", icon: "envelope", status: appState.googleAuthStatus)

                    Divider().padding(.vertical, 4)

                    // FEATURES
                    sectionHeader("FEATURES")
                    settingsTab("products", label: "Products & Resources", icon: "square.grid.2x2.fill", status: nil)
                    settingsTab("presence", label: "Team Presence", icon: "person.2.wave.2", status: nil)
                    settingsTab("notifications", label: "Notifications", icon: "bell.badge", status: nil)
                    settingsTab("skills", label: "Skills", icon: "brain", status: nil)

                    Divider().padding(.vertical, 4)

                    // ABOUT
                    sectionHeader("ABOUT")
                    settingsTab("productivity", label: "Productivity", icon: "chart.line.uptrend.xyaxis", status: nil)
                    settingsTab("advanced", label: "Advanced", icon: "gearshape.2", status: nil)
                    settingsTab("about", label: "About", icon: "info.circle", status: nil)

                    Spacer()
                }
                .frame(width: 180)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Right content — .id forces fresh @State when switching tabs
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "profile": ProfileView()
                        case "appearance": AppearanceSettingsContent()
                        case "ai": AISettingsContent()
                        case "notifications": NotificationsSettingsContent()
                        case "integrations": IntegrationsOverviewContent()
                        case "aws": AWSSettingsContent()
                        case "jira": JiraSettingsContent()
                        case "confluence": ConfluenceSettingsContent()
                        case "bitbucket": BitbucketSettingsContent()
                        case "github": GitHubSettingsContent()
                        case "jenkins": JenkinsSettingsContent()
                        case "grafana": GrafanaSettingsContent()
                        case "google": GoogleSettingsContent()
                        case "jsm": JiraSettingsContent()  // redirect to Jira tab
                        case "incidents": JiraSettingsContent()  // redirect to Jira tab
                        case "products": ProductSettingsContent()
                        case "presence": TeamPresenceSettingsContent()
                        case "skills": SkillsConfigSettingsContent()
                        case "productivity": ProductivityTabView()
                        case "advanced": AdvancedSettingsContent(showFeatureRequest: $showFeatureRequest)
                        case "about": AboutSettingsContent(showFeatureRequest: $showFeatureRequest)
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(selectedTab)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Factory Reset", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                appState.factoryReset()
            }
        } message: {
            Text("This will reset all app settings, clear notifications, incidents, chat history, and saved credentials. Your AWS config (~/.aws/), MCP credentials (~/.kiro/), and Git config are NOT affected.\n\nThe app will restart with the Onboarding Wizard.")
        }
        .sheet(isPresented: $showFeatureRequest) {
            FeatureRequestView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsProfileTab)) { _ in
            selectedTab = "profile"
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutTab)) { _ in
            selectedTab = "about"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func settingsTab(_ id: String, label: String, icon: String, status: AuthStatus?) -> some View {
        Button {
            selectedTab = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                    .font(.body)
                Spacer()
                if let status = status {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == id ? Color.accentColor.opacity(0.15) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runDiscovery() {
        let creds = CredentialDiscovery.discover()
        let count = CredentialDiscovery.discoveredCount(creds)

        if count == 0 && creds.atlassianEmail == nil {
            discoveryResult = "No credentials found in ~/.kiro/, ~/.amazonq/, ~/.aws/, or ~/.config/"
            discoveryIsError = true
            return
        }

        appState.importDiscoveredCredentials()

        discoveryResult = "Imported \(creds.sources.count) items: \(creds.sources.joined(separator: ", "))"
        discoveryIsError = false

        appState.checkAllServices()
    }
}

// MARK: - Reusable field components

struct SettingsSection: View {
    let title: String
    let content: AnyView

    init(_ title: String, @ViewBuilder content: () -> some View) {
        self.title = title
        self.content = AnyView(content())
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isSecure {
                SecureField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct StatusBadge: View {
    let status: AuthStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(status.color).frame(width: 10, height: 10)
            Text(status.label)
                .font(.callout)
                .foregroundStyle(status.color)
                .textSelection(.enabled)
        }
    }
}

struct TokenStatus: View {
    let token: String
    let name: String

    var body: some View {
        if token.isEmpty {
            Label("No \(name) token saved", systemImage: "xmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Label("\(name) token saved (\(token.count) chars)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        }
    }
}

// MARK: - Connection Explanation

struct ConnectionExplanationView: View {
    let serviceName: String
    let apiDescription: String
    var webDescription: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How Boomi SRE connects to \(serviceName)", systemImage: "info.circle")
                .font(.subheadline.bold())

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("API Connection").font(.caption.bold())
                    Text(apiDescription).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let webDesc = webDescription {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Web View").font(.caption.bold())
                        Text(webDesc).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.blue.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).strokeBorder(Color.blue.opacity(0.15)))
    }
}

// MARK: - Notifications

struct NotificationsSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(NotificationViewModel.self) var notificationVM

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Notifications").font(.title2.bold())
            Text("Configure background polling and notification preferences.")
                .font(.callout).foregroundStyle(.secondary)

            SettingsSection("Background Polling") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("macOS system notifications", isOn: Binding(
                            get: { appState.systemNotificationsEnabled },
                            set: { appState.systemNotificationsEnabled = $0; notificationVM.systemNotificationsEnabled = $0; appState.saveConfig() }
                        )).toggleStyle(.switch)
                        Text("Shows native macOS banners for high-priority items (on-call alerts, P1 incidents). Requires Notification permissions in System Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Jira ticket assignments & status changes", isOn: Binding(
                            get: { appState.pollJiraEnabled },
                            set: { appState.pollJiraEnabled = $0; notificationVM.pollJira = $0; appState.saveConfig() }
                        )).toggleStyle(.switch)
                        Text("Polls Jira for tickets assigned to you or updated on your active epics.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Jenkins build failures", isOn: Binding(
                            get: { appState.pollJenkinsEnabled },
                            set: { appState.pollJenkinsEnabled = $0; notificationVM.pollJenkins = $0; appState.saveConfig() }
                        )).toggleStyle(.switch)
                        Text("Monitors Jenkins jobs in your active products for failed or unstable builds.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Grafana alert firing", isOn: Binding(
                            get: { appState.pollGrafanaEnabled },
                            set: { appState.pollGrafanaEnabled = $0; notificationVM.pollGrafana = $0; appState.saveConfig() }
                        )).toggleStyle(.switch)
                        Text("Checks Grafana for alerting rules that have fired in your configured dashboards.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("GitHub PR review requests", isOn: Binding(
                            get: { appState.pollGitHubEnabled },
                            set: { appState.pollGitHubEnabled = $0; notificationVM.pollGitHub = $0; appState.saveConfig() }
                        )).toggleStyle(.switch)
                        Text("Polls GitHub for open PRs where you are a requested reviewer across your active product repos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection("Refresh Interval") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Every \(Int(appState.refreshInterval / 60)) minutes").font(.subheadline).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { appState.refreshInterval },
                        set: { appState.refreshInterval = $0; notificationVM.refreshInterval = $0; appState.saveConfig() }
                    ), in: 60...1800, step: 60)
                    Text("Range: 1–30 minutes").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            SettingsSection("Archive Retention") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How long to keep read notifications in the archive:")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { appState.archiveRetention },
                        set: { appState.archiveRetention = $0; notificationVM.archiveRetention = $0; appState.saveConfig() }
                    )) {
                        ForEach(ArchiveRetention.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
        }
    }
}

// MARK: - AI Settings

struct AISettingsContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI").font(.title2.bold())
            Text("Configure the AI Copilot model, chat behavior, and Executive Assistant briefings.")
                .font(.callout).foregroundStyle(.secondary)

            SettingsSection("Claude Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Model", selection: $appState.claudeModel) {
                        Text("claude-sonnet-4-6 (recommended)").tag("claude-sonnet-4-6")
                        Text("claude-opus-4-6 (slower, smarter)").tag("claude-opus-4-6")
                        Text("claude-haiku-4-5 (fastest, cheapest)").tag("claude-haiku-4-5-20251001")
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: appState.claudeModel) { appState.saveConfig() }

                    let authMethod = ClaudeService().discoverAuthMethod()
                    if case .claudeCLI = authMethod {
                        Label("Using Claude CLI (Enterprise license detected)", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if case .apiKey = authMethod {
                        Label("Using Anthropic API key", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("No AI backend configured", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            SettingsSection("Chat Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-inject context in AI Copilot", isOn: Binding(
                        get: { appState.autoContextEnabled },
                        set: { appState.autoContextEnabled = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)

                    Toggle("Auto-generate status summary on launch", isOn: Binding(
                        get: { appState.copilotAutoSummaryOnLaunch },
                        set: { appState.copilotAutoSummaryOnLaunch = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Text("When enabled, the AI Copilot will automatically generate a status brief when you open the app.")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Analysis Depth", selection: Binding(
                        get: { appState.analysisDepth },
                        set: { appState.analysisDepth = $0; appState.saveConfig() }
                    )) {
                        Text("Brief").tag("brief")
                        Text("Standard").tag("standard")
                        Text("Thorough").tag("thorough")
                    }
                    .pickerStyle(.segmented)
                    Text("Controls how much detail the AI includes in analyses and summaries.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SettingsSection("Executive Assistant") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Auto-generate briefings on app launch", isOn: Binding(
                        get: { appState.autoGenerateBriefingsOnLaunch },
                        set: { appState.autoGenerateBriefingsOnLaunch = $0; appState.saveConfig() }
                    )).toggleStyle(.switch)
                    Text("Automatically generates the enabled briefing types below each time the app starts.")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("Enabled briefing types:").font(.subheadline.bold()).padding(.top, 4)

                    let allTypes: [(key: String, label: String, description: String)] = [
                        ("morningBrief", "Morning Brief", "Daily status overview: incidents, PRs, on-call, and top Jira priorities."),
                        ("emailTriage", "Email Triage", "Summarizes your Gmail inbox and flags action items."),
                        ("preMeetingBrief", "Pre-Meeting Brief", "Pulls context for your next calendar event."),
                        ("actionTracker", "Action Tracker", "Tracks open action items from past meetings and Jira."),
                        ("eodDigest", "EOD Digest", "End-of-day summary of completed work and tomorrow's plan."),
                        ("dailyTicketBrief", "Daily Ticket Brief", "Summarizes Jira ticket activity across your active products."),
                        ("claudeUsage", "Claude Usage", "Reports AI Copilot usage and token consumption.")
                    ]
                    ForEach(allTypes, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(item.label, isOn: Binding(
                                get: { appState.enabledBriefingTypes.contains(item.key) },
                                set: { on in
                                    if on { appState.enabledBriefingTypes.insert(item.key) }
                                    else  { appState.enabledBriefingTypes.remove(item.key) }
                                    appState.saveConfig()
                                }
                            )).toggleStyle(.switch)
                            Text(item.description)
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Skills Config Settings

struct SkillsConfigSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(SkillsViewModel.self) var skillsVM

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills").font(.title2.bold())
                Text("Enable or disable skills for the AI Copilot. Claude Code skills are discovered from ~/.claude/skills/.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            // Summary row
            HStack(spacing: 16) {
                Label("\(skillsVM.skills.count) total", systemImage: "sparkles")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("\(skillsVM.skills.filter { $0.isClaudeCodeSkill }.count) Claude Code", systemImage: "terminal")
                    .font(.subheadline).foregroundStyle(.teal)
                Label("\(skillsVM.skills.filter { $0.isBuiltIn && !$0.isClaudeCodeSkill }.count) built-in", systemImage: "checkmark.seal")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    skillsVM.discoverClaudeCodeSkills()
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            // Built-in skills section
            let builtIns = skillsVM.skills.filter { $0.isBuiltIn && !$0.isClaudeCodeSkill }
            if !builtIns.isEmpty {
                SettingsSection("Built-in Skills") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(builtIns) { skill in
                            skillRow(skill)
                            if skill.id != builtIns.last?.id { Divider().padding(.vertical, 2) }
                        }
                    }
                }
            }

            // Claude Code skills section
            let claudeCodeSkills = skillsVM.skills.filter { $0.isClaudeCodeSkill }
            SettingsSection("Claude Code Skills  (~/.claude/skills/)") {
                if claudeCodeSkills.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No skills found in ~/.claude/skills/")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Create a subdirectory with a SKILL.md file to add a skill. Press Re-scan to refresh.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(claudeCodeSkills) { skill in
                            skillRow(skill)
                            if skill.id != claudeCodeSkills.last?.id { Divider().padding(.vertical, 2) }
                        }
                    }
                }
            }

            // Custom skills section
            let custom = skillsVM.skills.filter { !$0.isBuiltIn && !$0.isClaudeCodeSkill }
            if !custom.isEmpty {
                SettingsSection("Custom Skills") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(custom) { skill in
                            skillRow(skill)
                            if skill.id != custom.last?.id { Divider().padding(.vertical, 2) }
                        }
                    }
                }
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        let isEnabled = !appState.disabledClaudeSkills.contains(skill.name)
        return HStack(spacing: 10) {
            Image(systemName: skill.icon)
                .font(.body)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.callout.bold())
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                    if skill.isClaudeCodeSkill {
                        Text("Claude Code")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.teal))
                    } else if skill.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                if !skill.skillDescription.isEmpty {
                    Text(skill.skillDescription)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { !appState.disabledClaudeSkills.contains(skill.name) },
                set: { enabled in
                    if enabled {
                        appState.disabledClaudeSkills.remove(skill.name)
                    } else {
                        appState.disabledClaudeSkills.insert(skill.name)
                    }
                    appState.saveConfig()
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Lightweight model for Jira project list in Preferences.
struct JiraProjectSummary: Identifiable, Codable {
    let id: String
    let key: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, key, name
    }
}

// MARK: - AWS

struct AWSSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var profiles: [AWSProfile] = []
    @State private var isLoggingIn = false
    @State private var isBootstrapping = false
    @State private var bootstrapMessage = ""
    @State private var bootstrapIsError = false
    @State private var bootstrapProgress = ""
    @State private var bootstrapElapsed = 0
    @State private var bootstrapTimer: Timer?
    @State private var pasteText = ""
    @State private var pasteMessage = ""
    @State private var pasteIsError = false
    @State private var detectedProfileName: String = ""

    private let awsAuth = AWSAuthService()

    private var hasAWSConfig: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/config")
        return FileManager.default.fileExists(atPath: path.path)
    }

    private var selectedProfile: AWSProfile? {
        profiles.first { $0.name == appState.awsSSOProfile }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "AWS",
                apiDescription: "AWS SSO or portal credentials are used to run AWS CLI commands for Cost Explorer, EC2, RDS, and other infrastructure queries."
            )

            if !hasAWSConfig {
                // No config — show setup flow
                SettingsSection("Setup Required") {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("No AWS configuration found. Click below to set up AWS SSO and discover all your accounts.")
                            .font(.callout).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            bootstrapSSOConfig()
                        } label: {
                            Label(isBootstrapping ? "Setting up..." : "Setup AWS SSO",
                                  systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBootstrapping)

                        if isBootstrapping {
                            ProgressView().scaleEffect(0.7)
                            Text(bootstrapProgress.isEmpty ? "Elapsed: \(bootstrapElapsed)s" : bootstrapProgress)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if !bootstrapMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: bootstrapIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            Text(bootstrapMessage).font(.caption).textSelection(.enabled)
                        }
                        .foregroundStyle(bootstrapIsError ? .red : .green)
                    }

                    Text("This opens the Boomi SSO page in your browser. After you authenticate, it auto-creates ~/.aws/config with profiles for every account you have access to.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                // Config exists — show status + re-bootstrap option
                SettingsSection("Authentication") {
                    StatusBadge(status: appState.awsAuthStatus)

                    HStack(spacing: 12) {
                        Button("Login with SSO") { loginSSO() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoggingIn || isBootstrapping)
                        Button("Check Status") { checkAWS() }
                            .disabled(isLoggingIn)
                        if isLoggingIn { ProgressView().scaleEffect(0.7) }
                    }

                    Text("\(profiles.count) profiles loaded from ~/.aws/config. Accounts are managed per product in Products & Resources.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SettingsSection("Rebuild Config") {
                    HStack(spacing: 12) {
                        Button {
                            bootstrapSSOConfig()
                        } label: {
                            Label(isBootstrapping ? "Rebuilding..." : "Rebuild AWS Config",
                                  systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBootstrapping || isLoggingIn)

                        if isBootstrapping {
                            ProgressView().scaleEffect(0.7)
                            Text(bootstrapProgress.isEmpty ? "Elapsed: \(bootstrapElapsed)s" : bootstrapProgress)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if !bootstrapMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: bootstrapIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            Text(bootstrapMessage).font(.caption).textSelection(.enabled)
                        }
                        .foregroundStyle(bootstrapIsError ? .red : .green)
                    }

                    Text("Re-discovers all accounts and roles. Use after getting access to new accounts.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

        }
        .onAppear {
            profiles = loadProfilesWithNames()
            resolveUnknownNames()
        }
    }

    private func bootstrapSSOConfig() {
        isBootstrapping = true
        bootstrapMessage = ""
        bootstrapProgress = "Preparing SSO session..."
        bootstrapElapsed = 0

        // Start elapsed timer
        bootstrapTimer?.invalidate()
        bootstrapTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in bootstrapElapsed += 1 }
        }

        Task {
            do {
                // Step 1: Ensure the sso-session block exists so `aws sso login` can work
                let home = FileManager.default.homeDirectoryForCurrentUser
                let configURL = home.appendingPathComponent(".aws/config")
                let awsDir = home.appendingPathComponent(".aws")
                try FileManager.default.createDirectory(at: awsDir, withIntermediateDirectories: true)

                var config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
                let sessionName = "boomi-sso"
                let sessionHeader = "[sso-session \(sessionName)]"
                if !config.contains(sessionHeader) {
                    if !config.isEmpty && !config.hasSuffix("\n") { config += "\n" }
                    config += "\n\(sessionHeader)\nsso_region = us-east-1\nsso_start_url = https://d-90678132a6.awsapps.com/start/#\nsso_registration_scopes = sso:account:access\n"

                    // Add a minimal default profile so `aws sso login` has something to reference
                    if !config.contains("[profile default]") {
                        config += "\n[profile default]\nsso_session = \(sessionName)\nregion = us-east-1\noutput = json\n"
                    }
                    try config.write(to: configURL, atomically: true, encoding: .utf8)
                }

                // Step 2: Check if SSO token exists; if not, trigger login
                await MainActor.run { bootstrapProgress = "Checking SSO session..." }
                if awsAuth.findSSOAccessTokenPublic() == nil {
                    await MainActor.run { bootstrapProgress = "Opening SSO login page..." }
                    // Open the start URL directly in the browser
                    if let url = URL(string: "https://d-90678132a6.awsapps.com/start/#") {
                        _ = await MainActor.run { NSWorkspace.shared.open(url) }
                    }
                    // Run `aws sso login` to register the device and cache the token
                    do {
                        _ = try await awsAuth.login(profile: "default")
                    } catch {
                        await MainActor.run { bootstrapProgress = "SSO login failed: \(error.localizedDescription). Waiting for browser auth..." }
                    }

                    // Poll for the token (user is authenticating in browser)
                    for _ in 0..<60 {
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                        if awsAuth.findSSOAccessTokenPublic() != nil { break }
                    }

                    guard awsAuth.findSSOAccessTokenPublic() != nil else {
                        throw AWSAuthError.loginFailed("SSO authentication timed out. Please try again.")
                    }
                }

                // Step 3: Build profiles
                await MainActor.run { bootstrapProgress = "Discovering accounts..." }
                let count = try await awsAuth.bootstrapSSOConfig()

                await MainActor.run {
                    bootstrapTimer?.invalidate()
                    if count > 0 {
                        bootstrapMessage = "Created \(count) AWS profiles in ~/.aws/config (\(bootstrapElapsed)s)"
                        bootstrapIsError = false
                    } else {
                        bootstrapMessage = "No new profiles to add (all accounts already configured)"
                        bootstrapIsError = false
                    }
                    profiles = loadProfilesWithNames()
                    isBootstrapping = false
                    bootstrapProgress = ""
                }
            } catch {
                await MainActor.run {
                    bootstrapTimer?.invalidate()
                    bootstrapMessage = error.localizedDescription
                    bootstrapIsError = true
                    isBootstrapping = false
                    bootstrapProgress = ""
                }
            }
        }
    }

    private func loginSSO() {
        isLoggingIn = true; appState.awsAuthStatus = .checking
        Task {
            do {
                _ = try await awsAuth.login(profile: "default")
                let detail = try await awsAuth.checkStatus(profile: "default")
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail); isLoggingIn = false }
            } catch {
                await MainActor.run { appState.awsAuthStatus = .error(error.localizedDescription); isLoggingIn = false }
            }
        }
    }

    private func checkAWS() {
        appState.awsAuthStatus = .checking
        Task {
            do {
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
            } catch is AWSAuthError {
                await MainActor.run { appState.awsAuthStatus = .expired }
            } catch {
                await MainActor.run { appState.awsAuthStatus = .error(error.localizedDescription) }
            }
        }
    }

    private func updateDetectedProfile() {
        let normalized = pasteText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") && l.hasSuffix("]") {
                let name = String(l.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                detectedProfileName = name.isEmpty ? "portal-fallback" : name
                return
            }
        }
        detectedProfileName = pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "portal-fallback"
    }

    private func addCredentials() {
        do {
            let profileName = try awsAuth.addPortalCredentials(pasteText)
            pasteMessage = "Added profile: \(profileName) — resolving account name..."
            pasteIsError = false
            pasteText = ""
            detectedProfileName = ""
            profiles = loadProfilesWithNames()
            appState.awsSSOProfile = profileName
            appState.saveConfig()

            // Immediately check status so user gets confirmation it works
            Task {
                appState.awsAuthStatus = .checking
                do {
                    let detail = try await awsAuth.checkStatus(profile: profileName)
                    await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
                } catch {
                    await MainActor.run { appState.awsAuthStatus = .error(error.localizedDescription) }
                }
            }

            // Resolve the account's friendly name in the background
            Task {
                if let alias = await awsAuth.resolveAccountName(profile: profileName) {
                    await MainActor.run {
                        // Extract account ID from profile name
                        let parts = profileName.split(separator: "_", maxSplits: 1)
                        let accountId = parts.first.map(String.init) ?? profileName
                        appState.awsAccountNames[accountId] = alias.uppercased()
                        appState.saveConfig()
                        profiles = loadProfilesWithNames()
                        pasteMessage = "Added: \(alias.uppercased()) (\(accountId))"
                    }
                } else {
                    await MainActor.run {
                        pasteMessage = "Added profile: \(profileName) (couldn't resolve account name)"
                    }
                }
            }
        } catch {
            pasteMessage = error.localizedDescription
            pasteIsError = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { pasteMessage = "" }
    }

    private func loadProfilesWithNames() -> [AWSProfile] {
        var list = awsAuth.listProfiles()
            .filter { $0.name != "pasted" }   // filter out bug-artifact profiles
        for i in list.indices {
            if !list[i].accountId.isEmpty,
               let name = appState.awsAccountNames[list[i].accountId] {
                list[i].friendlyName = name
            }
        }
        return list
    }

    /// Resolve friendly names for profiles that don't have one cached yet.
    private func resolveUnknownNames() {
        let unknowns = profiles.filter { !$0.accountId.isEmpty && $0.friendlyName.isEmpty }
        guard !unknowns.isEmpty else { return }

        for profile in unknowns {
            Task {
                if let alias = await awsAuth.resolveAccountName(profile: profile.name, accountId: profile.accountId) {
                    await MainActor.run {
                        appState.awsAccountNames[profile.accountId] = alias.uppercased()
                        appState.saveConfig()
                        profiles = loadProfilesWithNames()
                    }
                }
            }
        }
    }
}

// MARK: - Jira

struct JiraSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var projectKeysField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false
    @State private var jiraSubTab = 0

    private let jiraService = JiraService()

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("", selection: $jiraSubTab) {
                Text("Credentials").tag(0)
                Text("Incidents").tag(1)
                Text("On-Call").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            ScrollView {
                switch jiraSubTab {
                case 0:
                    jiraCredentialsContent
                        .padding(24)
                case 1:
                    IncidentSettingsContent()
                        .padding(24)
                case 2:
                    JSMSettingsContent()
                        .padding(24)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jiraCredentialsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Jira",
                apiDescription: "Your personal API token is used to fetch tickets, filters, boards, and post comments. Generate one at id.atlassian.com."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Base URL", text: $appState.jiraBaseURL, placeholder: "https://yoursite.atlassian.net")
                FieldRow(label: "Email", text: $appState.jiraEmail, placeholder: "you@company.com")
                FieldRow(label: "API Token", text: $tokenField, isSecure: true, placeholder: "your-api-token")
                HStack {
                    Link("Get a token from Atlassian",
                         destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        .font(.caption)
                    Spacer()
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection("Projects") {
                FieldRow(label: "Project keys (comma-separated)", text: $projectKeysField,
                         placeholder: "CAMSRE, SRE")
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.jiraAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testJira() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                    Button("Save") { saveJira() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear {
            tokenField = appState.jiraAPIToken
            projectKeysField = appState.jiraProjectKeys.joined(separator: ", ")
        }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .jira)
                .environmentObject(appState)
        }
    }

    private func saveJira() {
        appState.jiraAPIToken = tokenField
        appState.jiraProjectKeys = projectKeysField
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        appState.saveConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testJira() {
        isTesting = true; appState.jiraAuthStatus = .checking
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, tokenField)
        Task {
            do {
                let name = try await jiraService.checkAuth(baseURL: baseURL, email: email, apiToken: token)
                await MainActor.run { appState.jiraAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.jiraAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Confluence

struct ConfluenceSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false

    private let service = ConfluenceService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Confluence",
                apiDescription: "Your API token fetches spaces, pages, and search results.",
                webDescription: "Some pages with complex macros or embedded content are rendered in an embedded browser view. If you see a login page, sign in once — the session persists."
            )

            SettingsSection("Connection") {
                Text("Confluence uses the same base URL and email as Jira.")
                    .font(.caption).foregroundStyle(.secondary)
                FieldRow(label: "Base URL (from Jira)", text: .constant(appState.jiraBaseURL))
                FieldRow(label: "Email (from Jira)", text: .constant(appState.jiraEmail))
                FieldRow(label: "Confluence API Token", text: $tokenField, isSecure: true, placeholder: "your-api-token")
                Link("Get a token from Atlassian",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.confluenceAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                    Button("Save") { saveToken() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear { tokenField = appState.confluenceAPIToken }
    }

    private func saveToken() {
        appState.confluenceAPIToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.confluenceAuthStatus = .checking
        let (baseURL, email, token) = (appState.jiraBaseURL, appState.jiraEmail, tokenField)
        Task {
            do {
                let name = try await service.checkAuth(baseURL: baseURL, email: email, apiToken: token)
                await MainActor.run { appState.confluenceAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.confluenceAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Bitbucket

struct BitbucketSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var workspaceField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false

    private let service = BitbucketService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Bitbucket",
                apiDescription: "Bitbucket Cloud uses scoped API tokens (created at id.atlassian.com). App Passwords are deprecated since Sept 2025 and will be disabled June 2026."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Workspace", text: $workspaceField, placeholder: "e.g. boomii")
                FieldRow(label: "Scoped API Token", text: $tokenField, isSecure: true, placeholder: "your-scoped-api-token")

                HStack {
                    Link("Create a Scoped API Token at id.atlassian.com",
                         destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        .font(.caption)
                    Spacer()
                    Button { showGuide = true } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Text("Create a scoped API token at id.atlassian.com → API Tokens → \"Create API token with scopes\". Select **Bitbucket** as the target app and grant: read:repository, read:pullrequest, read:pipeline, read:workspace, read:project. Uses your Jira email for authentication.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.bitbucketAuthStatus)
                if appState.jiraEmail.isEmpty {
                    Label("Jira email not configured — set it in Jira settings first (used for Bitbucket auth)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || appState.jiraEmail.isEmpty)
                    Button("Save") { saveToken() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear {
            tokenField = appState.bitbucketAPIToken
            workspaceField = appState.bitbucketWorkspace
        }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .bitbucket)
                .environmentObject(appState)
        }
    }

    private func saveToken() {
        appState.bitbucketAPIToken = tokenField
        appState.bitbucketWorkspace = workspaceField.isEmpty ? "boomii" : workspaceField
        appState.saveConfig()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.bitbucketAuthStatus = .checking
        let (email, token, workspace) = (appState.jiraEmail, tokenField, appState.bitbucketWorkspace)
        Task {
            do {
                let name = try await service.checkAuth(email: email, apiToken: token, workspace: workspace)
                await MainActor.run { appState.bitbucketAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.bitbucketAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - GitHub

struct GitHubSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false
    @State private var newOrgField = ""
    @State private var isDiscovering = false
    @State private var discoveredOrgs: [String] = []
    @State private var discoveryError: String?

    private let service = GitHubService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "GitHub",
                apiDescription: "Your personal access token (classic or fine-grained) is used to list repos, PRs, files, workflow runs, and create issues. Generate one at github.com/settings/tokens."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Personal Access Token", text: $tokenField, isSecure: true,
                         placeholder: "ghp_...")
                HStack {
                    Link("Create a token at github.com",
                         destination: URL(string: "https://github.com/settings/tokens")!)
                        .font(.caption)
                    Spacer()
                    Button { showGuide = true } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Text("Needs repo and read:org scopes for Mashery-Boomi org access.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsSection("GitHub Organizations") {
                Text("Repos from these orgs will appear in the GitHub browser.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(appState.githubOrgs, id: \.self) { org in
                    HStack {
                        Text(org).font(.callout)
                        Spacer()
                        Button { appState.githubOrgs.removeAll { $0 == org }; appState.saveConfig() } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add org (e.g. my-company)", text: $newOrgField)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newOrgField.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !appState.githubOrgs.contains(trimmed) {
                            appState.githubOrgs.append(trimmed); appState.saveConfig()
                        }
                        newOrgField = ""
                    }.buttonStyle(.bordered).disabled(newOrgField.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack(spacing: 10) {
                    Button {
                        isDiscovering = true
                        discoveryError = nil
                        let token = tokenField.isEmpty ? appState.githubToken : tokenField
                        Task {
                            do {
                                discoveredOrgs = try await service.listUserOrgs(token: token)
                            } catch {
                                discoveredOrgs = []
                                await MainActor.run { discoveryError = "Failed to discover orgs: \(error.localizedDescription)" }
                            }
                            await MainActor.run { isDiscovering = false }
                        }
                    } label: {
                        if isDiscovering { HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Discovering…") } }
                        else { Label("Discover My Orgs", systemImage: "magnifyingglass") }
                    }
                    .buttonStyle(.bordered).disabled(isDiscovering || (tokenField.isEmpty && appState.githubToken.isEmpty))
                }

                if let discoveryError {
                    Text(discoveryError)
                        .font(.caption).foregroundStyle(.red)
                }

                if !discoveredOrgs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Discovered orgs — tap to add:").font(.caption).foregroundStyle(.secondary)
                        ForEach(discoveredOrgs, id: \.self) { org in
                            HStack {
                                Text(org).font(.callout)
                                Spacer()
                                if appState.githubOrgs.contains(org) {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                } else {
                                    Button("Add") {
                                        appState.githubOrgs.append(org); appState.saveConfig()
                                    }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.secondary.opacity(0.05)))
                }
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.githubAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty)
                    Button("Save") { saveToken() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear { tokenField = appState.githubToken }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .github).environmentObject(appState)
        }
    }

    private func saveToken() {
        appState.githubToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveToken()
        isTesting = true; appState.githubAuthStatus = .checking
        let token = tokenField
        Task {
            do {
                let name = try await service.checkAuth(token: token)
                await MainActor.run { appState.githubAuthStatus = .authenticated(detail: name); isTesting = false }
            } catch {
                await MainActor.run { appState.githubAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Jenkins

struct JenkinsSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var urlField = ""
    @State private var usernameField = ""
    @State private var tokenField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false
    @State private var newServerName = ""
    @State private var newServerURL = ""
    @State private var newServerUser = ""
    @State private var newServerToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Jenkins",
                apiDescription: "Your Jenkins API token is used to list jobs, fetch build history, and read console output. Find it in Jenkins \u{2192} Your Name \u{2192} Configure \u{2192} API Token."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Jenkins URL", text: $urlField,
                         placeholder: "https://jenkins-master.mashspud.com")
                FieldRow(label: "Username", text: $usernameField, placeholder: "your-jenkins-user")
                FieldRow(label: "API Token", text: $tokenField, isSecure: true, placeholder: "your-api-token")
                HStack {
                    Spacer()
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.jenkinsAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || urlField.isEmpty)
                    Button("Save") { saveAll() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }

            // Multi-server management
            SettingsSection("Jenkins Servers (\(appState.jenkinsServers.count))") {
                Text("Configure multiple Jenkins servers. Jobs from all servers are available for product mapping.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(appState.jenkinsServers.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.jenkinsServers[idx].name).font(.callout.bold())
                            Text(appState.jenkinsServers[idx].url).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            appState.jenkinsServers.remove(at: idx)
                            appState.saveConfig()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Server").font(.caption.bold())
                    FieldRow(label: "Name", text: $newServerName, placeholder: "e.g. Jenkins USW2")
                    FieldRow(label: "URL", text: $newServerURL, placeholder: "https://jenkins.example.com")
                    FieldRow(label: "Username", text: $newServerUser, placeholder: "your-jenkins-user")
                    FieldRow(label: "Token", text: $newServerToken, isSecure: true, placeholder: "your-api-token")
                    HStack {
                        Spacer()
                        Button("Add Server") {
                            let server = JenkinsServer(
                                id: UUID().uuidString,
                                name: newServerName.isEmpty ? "Jenkins" : newServerName,
                                url: newServerURL, username: newServerUser, token: newServerToken
                            )
                            appState.jenkinsServers.append(server)
                            appState.saveConfig()
                            newServerName = ""; newServerURL = ""; newServerUser = ""; newServerToken = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(newServerURL.isEmpty || newServerToken.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            urlField = appState.jenkinsURL
            usernameField = appState.jenkinsUsername
            tokenField = appState.jenkinsToken
        }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .jenkins(jenkinsURL: appState.jenkinsURL))
                .environmentObject(appState)
        }
    }

    private func saveAll() {
        appState.jenkinsURL = urlField
        appState.jenkinsUsername = usernameField
        appState.jenkinsToken = tokenField
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveAll()
        isTesting = true
        appState.jenkinsAuthStatus = .checking
        let url = urlField.hasSuffix("/") ? urlField : urlField + "/"
        let username = usernameField
        let token = tokenField

        Task {
            do {
                let testURL = URL(string: "\(url)api/json")!
                var request = URLRequest(url: testURL, timeoutInterval: 15)
                if let data = "\(username):\(token)".data(using: .utf8) {
                    request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                if let http, (200...299).contains(http.statusCode) {
                    let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "OK"
                    await MainActor.run { appState.jenkinsAuthStatus = .authenticated(detail: desc); isTesting = false }
                } else {
                    let code = http?.statusCode ?? 0
                    await MainActor.run { appState.jenkinsAuthStatus = .error("HTTP \(code)"); isTesting = false }
                }
            } catch {
                await MainActor.run { appState.jenkinsAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Grafana

struct GrafanaSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var urlField = ""
    @State private var tokenField = ""
    @State private var webUsernameField = ""
    @State private var webPasswordField = ""
    @State private var isTesting = false
    @State private var saved = false
    @State private var showGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Grafana",
                apiDescription: "Your Service Account token is used to fetch dashboards, panels, queries, and alert rules via the Grafana API.",
                webDescription: "Dashboard views are rendered in an embedded browser using your Grafana web session. If you see a login screen, sign in once — the session persists."
            )

            SettingsSection("Connection") {
                FieldRow(label: "Grafana URL", text: $urlField,
                         placeholder: "https://grafana.mashery.com")
                FieldRow(label: "Service Account Token", text: $tokenField, isSecure: true,
                         placeholder: "glsa_...")
                HStack {
                    Spacer()
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection("Web View Credentials (Optional)") {
                Text("Used to auto-fill the Grafana login form in embedded browser views.")
                    .font(.caption).foregroundStyle(.secondary)
                FieldRow(label: "Grafana Web Username", text: $webUsernameField, placeholder: "your-grafana-user")
                FieldRow(label: "Grafana Web Password", text: $webPasswordField, isSecure: true, placeholder: "your-password")
            }

            SettingsSection("Authentication") {
                StatusBadge(status: appState.grafanaAuthStatus)
                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || tokenField.isEmpty || urlField.isEmpty)
                    Button("Save") { saveAll() }
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .onAppear {
            urlField = appState.grafanaURL
            tokenField = appState.grafanaToken
            webUsernameField = KeychainHelper.load(key: "grafana-web-username") ?? ""
            webPasswordField = KeychainHelper.load(key: "grafana-web-password") ?? ""
        }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .grafana(grafanaURL: appState.grafanaURL))
                .environmentObject(appState)
        }
    }

    private func saveAll() {
        appState.grafanaURL = urlField
        appState.grafanaToken = tokenField
        if !webUsernameField.isEmpty {
            try? KeychainHelper.save(key: "grafana-web-username", value: webUsernameField)
        }
        if !webPasswordField.isEmpty {
            try? KeychainHelper.save(key: "grafana-web-password", value: webPasswordField)
        }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func testConnection() {
        saveAll()
        isTesting = true
        appState.grafanaAuthStatus = .checking
        let url = urlField.hasSuffix("/") ? urlField : urlField + "/"
        let token = tokenField

        Task {
            do {
                let testURL = URL(string: "\(url)api/org")!
                var request = URLRequest(url: testURL, timeoutInterval: 15)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await ZscalerTrustURLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                if let http, (200...299).contains(http.statusCode) {
                    let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String ?? "OK"
                    await MainActor.run { appState.grafanaAuthStatus = .authenticated(detail: name); isTesting = false }
                } else {
                    let code = http?.statusCode ?? 0
                    await MainActor.run { appState.grafanaAuthStatus = .error("HTTP \(code)"); isTesting = false }
                }
            } catch {
                await MainActor.run { appState.grafanaAuthStatus = .error(error.localizedDescription); isTesting = false }
            }
        }
    }
}

// MARK: - Google

struct GoogleSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    @State private var discoveredSource = ""
    @State private var discoveredEmail = ""
    @State private var scopes: [String] = []
    @State private var setupMessage = ""
    @State private var setupIsError = false
    @State private var showGuide = false

    private let googleService = GoogleService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionExplanationView(
                serviceName: "Google",
                apiDescription: "Google Workspace integration uses OAuth credentials for Gmail and Calendar.",
                webDescription: "Some Gmail features use an embedded browser. Sign in to your Google account once within the app — the session persists across launches."
            )

            SettingsSection("Account") {
                StatusBadge(status: appState.googleAuthStatus)

                if !appState.googleEmail.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.blue)
                        Text(appState.googleEmail)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                if !discoveredSource.isEmpty {
                    Text("Credentials loaded from: \(discoveredSource)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Auto-discover") { discover() }
                        .buttonStyle(.borderedProminent)
                    Button("Test Connection") { testConnection() }
                        .disabled(isTesting || appState.googleCredentials == nil)
                    if isTesting { ProgressView().scaleEffect(0.7) }
                    Button {
                        showGuide = true
                    } label: {
                        Label("Setup Guide / OAuth Help", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection("OAuth Scopes") {
                if scopes.isEmpty {
                    Text("Click Auto-discover to load credential details.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(scopes.count) scopes authorized:")
                        .font(.caption).foregroundStyle(.secondary)

                    let gmailScopes = scopes.filter { $0.contains("gmail") }
                    let calendarScopes = scopes.filter { $0.contains("calendar") }
                    let chatScopes = scopes.filter { $0.contains("chat") }
                    let driveScopes = scopes.filter { $0.contains("drive") }
                    let otherScopes = scopes.filter { !$0.contains("gmail") && !$0.contains("calendar") && !$0.contains("chat") && !$0.contains("drive") }

                    scopeGroup("Gmail", scopes: gmailScopes, icon: "envelope")
                    scopeGroup("Calendar", scopes: calendarScopes, icon: "calendar")
                    scopeGroup("Chat", scopes: chatScopes, icon: "bubble.left.and.bubble.right")
                    scopeGroup("Drive", scopes: driveScopes, icon: "folder")
                    if !otherScopes.isEmpty {
                        scopeGroup("Other", scopes: otherScopes, icon: "ellipsis.circle")
                    }
                }
            }

            SettingsSection("Credentials") {
                let appCredPath = "~/.boomi-sre/credentials/"
                let hasCredentials = appState.googleCredentials != nil

                if hasCredentials {
                    Label("Credentials loaded from: \(discoveredSource.isEmpty ? appCredPath : discoveredSource)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("No credentials found", systemImage: "xmark.circle")
                        .font(.caption).foregroundStyle(.red)
                }

                Text("Google credentials are managed by the Google Workspace MCP server. Authenticate there first, then import.")
                    .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    setupStep("1", text: "Authenticate through the Google Workspace MCP server (it handles OAuth for you)")
                    setupStep("2", text: "Click \"Import from MCP\" to copy the credential file into \(appCredPath)")
                    setupStep("3", text: "Or manually place a credential JSON (with refresh_token) in \(appCredPath)")
                }

                HStack(spacing: 12) {
                    Button("Import from MCP") { importFromMCP() }
                        .buttonStyle(.borderedProminent)
                    Button("Open Credentials Folder") {
                        NSWorkspace.shared.open(CredentialDiscovery.credentialDir)
                    }
                }

                if !setupMessage.isEmpty {
                    Text(setupMessage)
                        .font(.caption)
                        .foregroundStyle(setupIsError ? .red : .green)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear { discover() }
        .sheet(isPresented: $showGuide) {
            APIKeyGuideView(guide: .google)
                .environmentObject(appState)
        }
    }

    private func discover() {
        if let result = GoogleCredentials.discover() {
            discoveredSource = result.source
            discoveredEmail = result.email
            scopes = result.credentials.scopes ?? []
            appState.googleEmail = result.email
            testConnection()
        } else if let clientSecretsFile = GoogleCredentials.findIncompleteClientSecrets() {
            // Found a client secrets file but no completed credential
            appState.googleAuthStatus = .notConfigured
            discoveredSource = ""
            scopes = []
            setupMessage = "Found \(clientSecretsFile) but it's a client secrets file (no OAuth tokens). Authenticate through the Google Workspace MCP server first to generate tokens, then click Import from MCP."
            setupIsError = true
        } else {
            appState.googleAuthStatus = .notConfigured
            discoveredSource = ""
            scopes = []
        }
    }

    private func testConnection() {
        guard let creds = appState.googleCredentials else {
            appState.googleAuthStatus = .notConfigured
            return
        }
        isTesting = true
        appState.googleAuthStatus = .checking
        Task {
            do {
                let email = try await googleService.checkAuth(credentials: creds)
                await MainActor.run {
                    appState.googleAuthStatus = .authenticated(detail: email)
                    appState.googleEmail = email
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    appState.googleAuthStatus = .error(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func scopeGroup(_ title: String, scopes: [String], icon: String) -> some View {
        DisclosureGroup {
            ForEach(scopes, id: \.self) { scope in
                Text(scope)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .font(.callout)
                Text("(\(scopes.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setupStep(_ num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.caption.bold())
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func importFromMCP() {
        let count = CredentialDiscovery.importGoogleCredentialsFromMCP()
        if count > 0 {
            setupMessage = "Imported \(count) credential file(s) into ~/.boomi-sre/credentials/"
            setupIsError = false
            discover()
        } else {
            setupMessage = "No Google credential files found in MCP directories. Authenticate through the Google Workspace MCP server first."
            setupIsError = true
        }
    }
}

// MARK: - Advanced Settings

private struct AdvancedSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var showFeatureRequest: Bool
    @State private var showResetConfirm = false
    @State private var reimportDone = false
    @State private var reimportCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Advanced").font(.title3.bold())

            // Re-import credentials section
            VStack(alignment: .leading, spacing: 12) {
                Text("Credentials").font(.headline)
                Text("Force re-import all credentials from MCP configuration files (~/.kiro/, ~/.amazonq/, etc.). This overwrites any existing tokens in the app with the latest from your MCP credential files.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        forceReimportCredentials()
                    } label: {
                        Label("Re-import All Credentials from MCP", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    if reimportDone {
                        Label("Imported \(reimportCount) credentials", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))

            Divider()

            // Factory Reset section
            VStack(alignment: .leading, spacing: 12) {
                Text("Danger Zone").font(.headline).foregroundStyle(.red)
                Text("Factory Reset clears all app settings, saved credentials, notifications, incidents, and chat history. Your AWS CLI config, MCP credentials, and Git config are NOT affected.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Factory Reset…", systemImage: "exclamationmark.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.2)))

            Spacer()
        }
        .alert("Factory Reset", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                appState.factoryReset()
            }
        } message: {
            Text("This will reset all app settings, clear notifications, incidents, chat history, and saved credentials. Your AWS config (~/.aws/), MCP credentials (~/.kiro/), and Git config are NOT affected.\n\nThe app will restart with the Onboarding Wizard.")
        }
    }

    private func forceReimportCredentials() {
        let creds = CredentialDiscovery.discover()
        var count = 0
        if let v = creds.atlassianEmail   { appState.jiraEmail = v; count += 1 }
        if let v = creds.atlassianBaseURL { appState.jiraBaseURL = v; count += 1 }
        if let v = creds.jiraToken        { appState.jiraAPIToken = v; count += 1 }
        if let v = creds.confluenceToken  { appState.confluenceAPIToken = v; count += 1 }
        if let v = creds.bitbucketToken   { appState.bitbucketAPIToken = v; count += 1 }
        if let v = creds.githubToken      { appState.githubToken = v; count += 1 }
        if let v = creds.jenkinsURL       { appState.jenkinsURL = v; count += 1 }
        if let v = creds.jenkinsUsername   { appState.jenkinsUsername = v; count += 1 }
        if let v = creds.jenkinsToken     { appState.jenkinsToken = v; count += 1 }
        if let v = creds.grafanaURL       { appState.grafanaURL = v; count += 1 }
        if let v = creds.grafanaToken     { appState.grafanaToken = v; count += 1 }
        appState.saveConfig()
        appState.checkAllServices()
        reimportCount = count
        reimportDone = true
    }
}

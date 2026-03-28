import SwiftUI

/// First-launch onboarding wizard. Shown as a sheet when hasCompletedOnboarding is false.
struct OnboardingWizardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var step = 0
    @State private var discoveryMessage: String?
    @State private var discoveryCount = 0
    @State private var isCheckingServices = false
    @State private var isGeneratingBrief = false
    @State private var briefGenerated = false
    @State private var showAPIKeyGuide: ServiceAPIGuide? = nil

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
                        .animation(.spring(), value: step)
                }
            }
            .frame(height: 4)

            // Content — scrollable so it never pushes the nav bar off screen
            ScrollView {
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: discoverStep
                    case 2: setupKeysStep
                    case 3: connectStep
                    case 4: profileStep
                    case 5: readyStep
                    default: EmptyView()
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation — fixed footer, always visible
            HStack {
                if step > 0 {
                    Button("← Back") { step -= 1 }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Step \(step + 1) of \(totalSteps)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                nextButton
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .frame(width: 620, height: 540)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bonjour")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Boomi SRE")
                .font(.largeTitle.bold())
            Text("Your AI-powered SRE command center. Manage incidents, track tickets, monitor costs, browse services, and get AI briefings — all in one place.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 8) {
                featureRow("ticket", "Jira, Boards, and Filters with AI analysis")
                featureRow("sparkles", "AI Copilot, Executive Assistant, Incident Command")
                featureRow("network", "GitHub, Jenkins, Grafana, and Confluence browsers")
                featureRow("bell", "Smart background notifications")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
            Spacer()
        }
    }

    private var discoverStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 56)).foregroundStyle(Color.accentColor)
            Text("Auto-Discover Credentials")
                .font(.title.bold())
            Text("Boomi SRE scans known credential locations on your Mac:\n~/.kiro/mcp_credentials, ~/.amazonq/, ~/.aws/, ~/.gitconfig")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if let msg = discoveryMessage {
                HStack(spacing: 8) {
                    Image(systemName: discoveryCount > 0 ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(discoveryCount > 0 ? .green : .secondary)
                    Text(msg).font(.callout).textSelection(.enabled)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(discoveryCount > 0 ? Color.green.opacity(0.08) : Color.secondary.opacity(0.08)))
            } else {
                Button {
                    runDiscovery()
                } label: {
                    Label("Scan for Credentials", systemImage: "magnifyingglass")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
            }
            Text("You can always add or update credentials manually in Settings.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var setupKeysStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 56)).foregroundStyle(Color.accentColor)
            Text("Set Up API Keys")
                .font(.title.bold())
            Text("Connect Boomi SRE to your services by adding API tokens. Each service has a step-by-step guide.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                setupKeyRow("Jira & Confluence", "ticket", guide: .jira,
                            hasToken: !appState.jiraAPIToken.isEmpty)
                setupKeyRow("GitHub", "chevron.left.forwardslash.chevron.right", guide: .github,
                            hasToken: !appState.githubToken.isEmpty)
                setupKeyRow("Jenkins", "hammer", guide: .jenkins(jenkinsURL: appState.jenkinsURL),
                            hasToken: !appState.jenkinsToken.isEmpty)
                setupKeyRow("Grafana", "chart.line.uptrend.xyaxis", guide: .grafana(grafanaURL: appState.grafanaURL),
                            hasToken: !appState.grafanaToken.isEmpty)
                setupKeyRow("Bitbucket", "externaldrive.connected.to.line.below", guide: .bitbucket,
                            hasToken: !appState.bitbucketAPIToken.isEmpty)
                setupKeyRow("Google Workspace", "envelope", guide: .google,
                            hasToken: appState.googleCredentials != nil)
            }

            Text("You can skip any service and configure it later in Settings (⌘,).")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .sheet(item: $showAPIKeyGuide) { guide in
            APIKeyGuideView(guide: guide)
                .environmentObject(appState)
        }
    }

    private func setupKeyRow(_ name: String, _ icon: String, guide: ServiceAPIGuide, hasToken: Bool) -> some View {
        Button {
            showAPIKeyGuide = guide
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(name).font(.callout)
                Spacer()
                Image(systemName: hasToken ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(hasToken ? .green : .accentColor)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var connectStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                .font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text("Test Service Connections")
                .font(.title.bold())

            if isCheckingServices {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.9)
                    Text("Checking all services…").font(.callout).foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                serviceRow("AWS SSO",    "cloud",         appState.awsAuthStatus)
                serviceRow("Jira",       "ticket",        appState.jiraAuthStatus)
                serviceRow("GitHub",     "chevron.left.forwardslash.chevron.right", appState.githubAuthStatus)
                serviceRow("Jenkins",    "hammer",        appState.jenkinsAuthStatus)
                serviceRow("Grafana",    "chart.bar",     appState.grafanaAuthStatus)
                serviceRow("Confluence", "doc.richtext",  appState.confluenceAuthStatus)
                serviceRow("Google",     "envelope",      appState.googleAuthStatus)
                serviceRow("Bitbucket",  "externaldrive.connected.to.line.below", appState.bitbucketAuthStatus)
            }

            Text("Unconfigured services can be set up later in Settings (⌘,).")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var profileStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 56)).foregroundStyle(Color.accentColor)
            Text("Set Up Your Profile")
                .font(.title.bold())
            Text("Tell us about yourself so AI responses are tailored to your experience level and role.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: 14) {
                // Name (pre-populated from discovery)
                HStack {
                    Text("Name").font(.subheadline).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    TextField("Your name", text: Binding(
                        get: { appState.userProfile.displayName },
                        set: { appState.userProfile.displayName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Role
                HStack {
                    Text("Role").font(.subheadline).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { appState.userProfile.role },
                        set: { appState.userProfile.role = $0 }
                    )) {
                        ForEach(SRERole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                }

                // Experience Level
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Level").font(.subheadline).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { appState.userProfile.experienceLevel },
                            set: { appState.userProfile.experienceLevel = $0 }
                        )) {
                            ForEach(ExperienceLevel.allCases, id: \.self) { lvl in
                                Text(lvl.displayName).tag(lvl)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200, alignment: .leading)
                    }
                    HStack {
                        Spacer().frame(width: 100)
                        Text(appState.userProfile.experienceLevel.analysisDepthHint)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Team (auto-derived from product selection — shown as read-only hint)
                if !appState.userProfile.myProducts.isEmpty {
                    HStack {
                        Text("Team").font(.subheadline).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                        Text(appState.products.filter { appState.userProfile.myProducts.contains($0.id) && $0.id != "all" }
                            .map(\.shortName).joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.primary)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
            .frame(maxWidth: 440)

            Text("You can update this any time in Settings → Profile.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("You're Ready!")
                .font(.largeTitle.bold())
            Text(ClaudeService().isAIAvailable
                 ? "Boomi SRE is set up. Start by opening the AI Copilot (\u{2318}/) or checking your TODO dashboard."
                 : "Boomi SRE is set up. Start by exploring the Dashboard or checking your TODO list.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)

            if briefGenerated {
                Label("Morning brief generated — check Executive Assistant", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else if !appState.googleCredentials.isNil && !isGeneratingBrief {
                Button {
                    generateFirstBrief()
                } label: {
                    Label("Generate First Morning Brief", systemImage: "sun.horizon")
                }
                .buttonStyle(.bordered)
            } else if isGeneratingBrief {
                HStack(spacing: 8) { ProgressView().scaleEffect(0.8); Text("Generating…").font(.callout) }
            }

            VStack(alignment: .leading, spacing: 8) {
                tipRow("⌘/",  "Open AI Copilot")
                tipRow("⌘I",  "Incident Command")
                tipRow("⌘E",  "Executive Assistant")
                tipRow("⌘,",  "Settings")
            }
            .font(.callout)
            .padding(14).background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            Spacer()
        }
    }

    // MARK: - Navigation Button

    private var nextButton: some View {
        Group {
            if step < totalSteps - 1 {
                Button(step == 0 ? "Get Started →" : "Continue →") {
                    if step == 4 {
                        // Save profile when leaving profile step
                        appState.saveConfig()
                    }
                    step += 1
                    if step == 3 {
                        isCheckingServices = true
                        appState.checkAllServices()
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            isCheckingServices = false
                            await appState.discoverProfile()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Start Using Boomi SRE") {
                    appState.hasCompletedOnboarding = true
                    appState.saveConfig()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Helpers

    private func runDiscovery() {
        let creds = CredentialDiscovery.discover()
        appState.importDiscoveredCredentials()
        discoveryCount = creds.sources.count
        if creds.sources.isEmpty {
            discoveryMessage = "No credentials found. Add them manually in Settings."
        } else {
            discoveryMessage = "Found \(creds.sources.count) item(s): \(creds.sources.joined(separator: ", "))"
        }
    }

    private func generateFirstBrief() {
        isGeneratingBrief = true
        let vm = ExecAssistantViewModel()
        let state = appState
        Task {
            await vm.generateMorningBrief(appState: state)
            await MainActor.run {
                isGeneratingBrief = false
                briefGenerated = true
            }
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(text).font(.callout)
        }
    }

    private func tipRow(_ shortcut: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(shortcut)
                .font(.callout.monospaced().bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(description).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func serviceRow(_ name: String, _ icon: String, _ status: AuthStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            Text(name).font(.callout)
            Spacer()
            if case .checking = status {
                ProgressView().scaleEffect(0.6)
            } else {
                Circle().fill(status.color).frame(width: 8, height: 8)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.secondary.opacity(0.06)))
    }
}

private extension Optional {
    var isNil: Bool { self == nil }
}

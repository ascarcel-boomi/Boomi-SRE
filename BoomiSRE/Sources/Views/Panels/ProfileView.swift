import SwiftUI

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRediscovering = false
    @State private var onCallSchedules: [String] = []
    @State private var isLoadingOnCall = false

    private let jsmOpsService = JSMOpsService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                Divider()
                autoDiscoveredSection
                Divider()
                editableFieldsSection
                saveButton
                Divider()
                aiPreferencesSection
                Divider()
                execAssistantSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(spacing: 20) {
            avatarView
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.userProfile.displayName.isEmpty ? "Your Profile" : appState.userProfile.displayName)
                    .font(.title2.bold())
                if !appState.userProfile.email.isEmpty {
                    Text(appState.userProfile.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    roleBadge
                    levelBadge
                }
            }
            Spacer()
        }
    }

    private var avatarView: some View {
        Group {
            if let urlStr = appState.userProfile.avatarURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        avatarFallback
                    default:
                        ProgressView()
                            .frame(width: 72, height: 72)
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }

    private var avatarFallback: some View {
        let initials = appState.userProfile.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
        return ZStack {
            Circle().fill(Color.accentColor.opacity(0.2))
            if initials.isEmpty {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            } else {
                Text(initials)
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var roleBadge: some View {
        Text(appState.userProfile.role.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private var levelBadge: some View {
        let color: Color = {
            switch appState.userProfile.experienceLevel {
            case .junior: return .blue
            case .mid:    return .green
            case .senior: return .orange
            case .lead:   return .purple
            }
        }()
        return Text(appState.userProfile.experienceLevel.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Auto-discovered section

    private var autoDiscoveredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Auto-Discovered", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
                Button {
                    isRediscovering = true
                    Task {
                        await appState.discoverProfile()
                        await MainActor.run { isRediscovering = false }
                    }
                } label: {
                    if isRediscovering {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Re-discover", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRediscovering)
            }

            if let handle = appState.userProfile.githubHandle {
                discoveredRow(icon: "chevron.left.forwardslash.chevron.right",
                              label: "GitHub",
                              value: "@\(handle)",
                              url: URL(string: "https://github.com/\(handle)"))
            } else {
                discoveredRow(icon: "chevron.left.forwardslash.chevron.right",
                              label: "GitHub",
                              value: "Not detected")
            }

            discoveredRow(icon: "ticket",
                          label: "Jira",
                          value: authStatusSummary(appState.jiraAuthStatus))

            // SSO identity
            let ssoEmail = appState.userProfile.oktaEmail ?? appState.jiraEmail
            if !ssoEmail.isEmpty {
                discoveredRow(icon: "key.fill", label: "SSO (Okta)", value: ssoEmail)
            }

            let tzName = appState.userProfile.timeZone
            let tz = TimeZone(identifier: tzName) ?? .current
            let abbr = tz.abbreviation() ?? ""
            discoveredRow(icon: "clock",
                          label: "Time Zone",
                          value: "\(tzName) (\(abbr))")
        }
    }

    private func discoveredRow(icon: String, label: String, value: String, url: URL? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            if let url {
                Link(value, destination: url)
                    .font(.subheadline)
            } else {
                Text(value)
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func authStatusSummary(_ status: AuthStatus) -> String {
        switch status {
        case .authenticated(let detail): return "Connected (\(detail))"
        case .checking: return "Checking..."
        case .notConfigured: return "Not configured"
        case .expired: return "Session expired"
        case .error(let msg): return "Error: \(msg)"
        case .unknown: return "Not checked"
        }
    }

    // MARK: - Editable fields

    private var editableFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Profile Settings", systemImage: "person.crop.circle.badge.gearshape")
                .font(.headline)

            ProfileTextField(label: "Display Name",
                             placeholder: "Your name",
                             text: Binding(
                                get: { appState.userProfile.displayName },
                                set: { appState.userProfile.displayName = $0 }
                             ))

            ProfileTextField(label: "Email",
                             placeholder: "your@email.com",
                             text: Binding(
                                get: { appState.userProfile.email },
                                set: { appState.userProfile.email = $0 }
                             ))

            // Role picker
            HStack(alignment: .top, spacing: 0) {
                Text("Role")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                Picker("", selection: Binding(
                    get: { appState.userProfile.role },
                    set: { appState.userProfile.role = $0 }
                )) {
                    ForEach(SRERole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
            }

            // Experience level picker + hint
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 0) {
                    Text("Experience Level")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { appState.userProfile.experienceLevel },
                        set: { appState.userProfile.experienceLevel = $0 }
                    )) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }
                HStack {
                    Spacer().frame(width: 120)
                    Text(appState.userProfile.experienceLevel.analysisDepthHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // My Team(s)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 0) {
                    Text("My Team(s)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        // All Teams option
                        Toggle(isOn: Binding(
                            get: { appState.userProfile.myProducts.isEmpty ||
                                   appState.userProfile.myProducts.count == appState.products.filter({ $0.id != "all" }).count },
                            set: { on in
                                if on {
                                    appState.userProfile.myProducts = Set(appState.products.filter { $0.id != "all" }.map(\.id))
                                } else {
                                    appState.userProfile.myProducts.removeAll()
                                }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.purple)
                                    .frame(width: 16)
                                Text("All Teams (fully horizontal)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Divider().padding(.vertical, 2)

                        ForEach(appState.products.filter { $0.id != "all" }) { product in
                            let isOn = appState.userProfile.myProducts.contains(product.id)
                            Toggle(isOn: Binding(
                                get: { isOn },
                                set: { on in
                                    if on { appState.userProfile.myProducts.insert(product.id) }
                                    else  { appState.userProfile.myProducts.remove(product.id) }
                                }
                            )) {
                                HStack(spacing: 6) {
                                    Image(systemName: product.icon)
                                        .foregroundStyle(Color(hex: product.color))
                                        .frame(width: 16)
                                    Text(product.name)
                                        .font(.subheadline)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        Text("Your active product filter defaults to these on launch. Change it anytime from the toolbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }

            // On-Call (auto-populated from JSM)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 0) {
                    Text("On-Call")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        if appState.isJiraConfigured {
                            if onCallSchedules.isEmpty && !isLoadingOnCall {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                                    Text("No active on-call schedules found for your account.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Button("Check On-Call") { Task { await loadOnCallInfo() } }
                                    .font(.caption).buttonStyle(.bordered)
                            } else if isLoadingOnCall {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking on-call schedules...").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(onCallSchedules, id: \.self) { schedule in
                                    HStack(spacing: 6) {
                                        Image(systemName: "bell.badge").foregroundStyle(.orange)
                                        Text(schedule).font(.subheadline)
                                    }
                                }
                                Button("Refresh") { Task { await loadOnCallInfo() } }
                                    .font(.caption).buttonStyle(.bordered)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text("Configure Jira in Settings to see on-call schedules.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Notes
            HStack(alignment: .top, spacing: 0) {
                Text("Notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                    .padding(.top, 4)
                TextEditor(text: Binding(
                    get: { appState.userProfile.notes },
                    set: { appState.userProfile.notes = $0 }
                ))
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - On-Call Lookup

    private func loadOnCallInfo() async {
        isLoadingOnCall = true
        defer { isLoadingOnCall = false }
        do {
            let schedules = try await jsmOpsService.listSchedules(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: appState.jiraAPIToken)
            var results: [String] = []
            for schedule in schedules where schedule.enabled {
                let participants = try await jsmOpsService.getOnCall(
                    baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                    apiToken: appState.jiraAPIToken, scheduleId: schedule.id)
                let myAccountId = appState.userProfile.jiraAccountId ?? ""
                let isOnCall = participants.contains { $0.name == myAccountId }
                if isOnCall {
                    results.append("\(schedule.name) — You are currently on call")
                } else if !participants.isEmpty {
                    let names = participants.map(\.name).prefix(3).joined(separator: ", ")
                    results.append("\(schedule.name) — \(names)")
                } else {
                    results.append("\(schedule.name) — No one on call")
                }
            }
            onCallSchedules = results
        } catch {
            onCallSchedules = ["Failed to load: \(error.localizedDescription)"]
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        HStack {
            Spacer()
            Button("Save Profile") {
                // Derive team name from selected products
                let selectedProducts = appState.products.filter {
                    $0.id != "all" && appState.userProfile.myProducts.contains($0.id)
                }
                if selectedProducts.count == appState.products.filter({ $0.id != "all" }).count {
                    appState.userProfile.team = "All Teams (Horizontal)"
                } else if !selectedProducts.isEmpty {
                    appState.userProfile.team = selectedProducts.map(\.shortName).joined(separator: ", ")
                }
                // Seed active product filter from myProducts if not yet set
                if appState.activeProductIds.isEmpty && !appState.userProfile.myProducts.isEmpty {
                    appState.activeProductIds = appState.userProfile.myProducts
                }
                appState.saveConfig()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }

    // MARK: - AI Preferences

    private var aiPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Preferences").font(.headline)

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
                }
            }
        }
    }

    // MARK: - Exec Assistant

    private var execAssistantSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Executive Assistant").font(.headline)

            SettingsSection("Briefing Settings") {
                Toggle("Auto-generate briefings on app launch", isOn: Binding(
                    get: { appState.autoGenerateBriefingsOnLaunch },
                    set: { appState.autoGenerateBriefingsOnLaunch = $0; appState.saveConfig() }
                )).toggleStyle(.switch)

                Text("Enabled briefing types:").font(.subheadline.bold()).padding(.top, 4)

                let allTypes: [(key: String, label: String)] = [
                    ("morningBrief", "Morning Brief"),
                    ("emailTriage", "Email Triage"),
                    ("preMeetingBrief", "Pre-Meeting Brief"),
                    ("actionTracker", "Action Tracker"),
                    ("eodDigest", "EOD Digest"),
                    ("dailyTicketBrief", "Daily Ticket Brief"),
                    ("claudeUsage", "Claude Usage")
                ]
                ForEach(allTypes, id: \.key) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { appState.enabledBriefingTypes.contains(item.key) },
                        set: { on in
                            if on { appState.enabledBriefingTypes.insert(item.key) }
                            else  { appState.enabledBriefingTypes.remove(item.key) }
                            appState.saveConfig()
                        }
                    )).toggleStyle(.switch)
                }
            }
        }
    }
}

// MARK: - Helper: ProfileTextField

private struct ProfileTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
        }
    }
}

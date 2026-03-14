import SwiftUI

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRediscovering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                Divider()
                autoDiscoveredSection
                Divider()
                editableFieldsSection
                saveButton
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
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
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

            ProfileTextField(label: "Team",
                             placeholder: "e.g. CAM SRE, Platform Engineering",
                             text: Binding(
                                get: { appState.userProfile.team },
                                set: { appState.userProfile.team = $0 }
                             ))

            ProfileTextField(label: "On-Call Info",
                             placeholder: "PagerDuty link, Grafana OnCall schedule, etc.",
                             text: Binding(
                                get: { appState.userProfile.onCallInfo },
                                set: { appState.userProfile.onCallInfo = $0 }
                             ))

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

    // MARK: - Save button

    private var saveButton: some View {
        HStack {
            Spacer()
            Button("Save Profile") {
                appState.saveConfig()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
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

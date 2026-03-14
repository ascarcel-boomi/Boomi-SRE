import SwiftUI

struct OnCallView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = OnCallViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-Call")
                        .font(.title2.bold())
                    if let last = vm.lastFetched {
                        Text("Last refreshed: \(last, format: .dateTime)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if vm.isLoadingTeams || vm.isLoadingAlerts {
                    ProgressView().scaleEffect(0.8)
                }
                Button {
                    Task { await vm.load(appState: appState) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoadingTeams || vm.isLoadingAlerts)

                Button {
                    appState.showSettings = true
                    appState.selectedReport = nil
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .help("Configure favorite teams in Settings → JSM")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            // If Jira not configured, prompt to set it up
            if !appState.isJiraConfigured {
                jiraNotConfiguredPrompt
            } else {
                if let error = vm.error {
                    errorBanner(error)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        onCallSection
                        alertsSection
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if vm.teams.isEmpty && appState.isJiraConfigured {
                Task { await vm.load(appState: appState) }
            }
        }
    }

    // MARK: - Jira not configured prompt

    private var jiraNotConfiguredPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "ticket").font(.system(size: 48)).foregroundStyle(Color.accentColor.opacity(0.7))
            Text("Jira Required for On-Call").font(.title3.bold())
            Text("On-Call schedules use your Jira credentials — the same token you use for tickets and boards.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            VStack(alignment: .leading, spacing: 8) {
                Label("Who's currently on call for your schedules", systemImage: "person.crop.circle.badge.clock")
                Label("On-call schedule rotations", systemImage: "calendar.badge.clock")
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
            Button {
                appState.showSettings = true
                appState.selectedSettingsTab = "jira"
            } label: {
                Label("Configure Jira", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(40)
    }

    // MARK: - On-Call Section

    private var onCallSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "phone.badge.waveform").foregroundStyle(Color.accentColor)
                Text("Who's On-Call").font(.headline)
                Spacer()
                if vm.isLoadingOnCall { ProgressView().scaleEffect(0.7) }
            }

            if appState.favoriteJSMTeams.isEmpty {
                noFavoriteTeamsPrompt
            } else if vm.teams.isEmpty && !vm.isLoadingTeams {
                HStack(spacing: 8) {
                    Text("No schedules found. Your API key may be team-scoped — check that the team has schedules configured.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { appState.showSettings = true; appState.selectedSettingsTab = "jsm" } label: {
                        Text("Settings").font(.caption)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                let favTeams = vm.teams.filter { appState.favoriteJSMTeams.contains($0.id) }
                if favTeams.isEmpty {
                    HStack(spacing: 8) {
                        Text("Select your favorite schedules in Settings → JSM Operations to see on-call information.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button { appState.showSettings = true; appState.selectedSettingsTab = "jsm" } label: {
                            Text("Open Settings").font(.caption)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(favTeams) { team in
                            onCallCard(team)
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func onCallCard(_ team: OpsTeam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Team header
            HStack {
                Text(team.name).font(.callout.bold())
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://\(appState.jiraBaseURL.replacingOccurrences(of: "https://", with: ""))/jira/ops/overview")!)
                } label: {
                    Label("JSM", systemImage: "safari").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }

            // Find schedules belonging to this team
            let teamSchedules = vm.allSchedules.filter { $0.teamId == team.id }

            if teamSchedules.isEmpty && vm.isLoadingOnCall {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Loading schedules…").font(.caption).foregroundStyle(.secondary)
                }
            } else if teamSchedules.isEmpty {
                Text("No schedules configured for this team")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(teamSchedules) { schedule in
                    VStack(alignment: .leading, spacing: 4) {
                        // Schedule name as sub-header
                        Text(schedule.name)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        let participants = vm.onCallResults[schedule.id] ?? []
                        if participants.isEmpty && vm.isLoadingOnCall {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Loading…").font(.caption2).foregroundStyle(.tertiary)
                            }
                        } else if participants.isEmpty {
                            Text("No one on call").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array(participants.enumerated()), id: \.offset) { i, p in
                                HStack(spacing: 8) {
                                    Image(systemName: i == 0 ? "person.fill" : "person")
                                        .foregroundStyle(i == 0 ? Color.accentColor : .secondary)
                                        .frame(width: 18)
                                    Text(vm.displayNames[p.name] ?? p.name).font(.callout)
                                    if i == 0 {
                                        Text("Primary")
                                            .font(.caption2).padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let desc = team.description, !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        .task { await vm.loadOnCallForTeam(teamId: team.id, appState: appState) }
    }

    private var noFavoriteTeamsPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3").font(.title2).foregroundStyle(.secondary)
            Text("No favorite teams selected")
                .font(.callout).foregroundStyle(.secondary)
            Text("Go to Settings → JSM Operations to discover and select your teams.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Button("Open JSM Settings") {
                appState.showSettings = true
                appState.selectedReport = nil
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Alerts Section

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.badge").foregroundStyle(.orange)
                Text("Active Alerts").font(.headline)
                Spacer()
                if vm.isLoadingAlerts { ProgressView().scaleEffect(0.7) }
                // Filter chips
                Picker("Filter", selection: $vm.alertFilter) {
                    ForEach(OnCallViewModel.AlertFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }

            if vm.filteredAlerts.isEmpty && !vm.isLoadingAlerts {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("No active alerts").font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Alerts from JSM Operations will appear here when they are available.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(vm.filteredAlerts) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func alertRow(_ alert: OpsAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Priority badge
            Text(alert.priority)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(priorityColor(alert.priority).opacity(0.15)))
                .foregroundStyle(priorityColor(alert.priority))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.message)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(alert.status.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor(alert.status).opacity(0.15)))
                        .foregroundStyle(statusColor(alert.status))
                    if let source = alert.source, !source.isEmpty {
                        Text(source).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(relativeTime(alert.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let tags = alert.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            }
                        }
                    }
                }
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(URL(string: "\(appState.jiraBaseURL.trimSlash)/jira/ops/alerts/\(alert.id)")!)
            } label: {
                Image(systemName: "safari").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Open in JSM")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if message.contains("invalid") || message.contains("expired") || message.contains("permissions") {
                Button {
                    appState.showSettings = true
                    appState.selectedSettingsTab = "jira"
                } label: { Text("Fix in Settings").font(.caption) }
                .buttonStyle(.bordered).controlSize(.small)
            }
            Button { Task { await vm.load(appState: appState) } } label: {
                Text("Retry").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .yellow
        case "P4": return .blue
        default:   return .secondary
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open":   return .red
        case "acked":  return .orange
        case "closed": return .green
        default:       return .secondary
        }
    }

    private func relativeTime(_ isoString: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString.prefix(10).description
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

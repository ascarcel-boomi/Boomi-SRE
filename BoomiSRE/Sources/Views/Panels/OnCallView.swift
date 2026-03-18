import SwiftUI

struct OnCallView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var vm: OnCallViewModel

    // Note sheet
    @State private var selectedAlertForNote: OpsAlert?
    @State private var showNoteSheet = false
    @State private var noteText = ""

    // Bulk selection
    @State private var isSelectMode = false
    @State private var selectedAlertIds: Set<String> = []

    // Close confirmation
    @State private var alertToClose: OpsAlert?
    @State private var showCloseConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-Call").font(.title2.bold())
                    if let last = vm.lastFetched {
                        Text("Last refreshed: \(last, format: .dateTime)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if vm.isLoadingTeams || vm.isLoadingOnCall || vm.isLoadingAlerts {
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
                .help("Map JSM teams to products in Settings → Products & Resources")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

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
            // Only load if never loaded or data is stale (>1 hour old)
            if appState.isJiraConfigured && vm.needsRefresh {
                Task { await vm.load(appState: appState) }
            }
        }
        // Auto-refresh every hour
        .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in
            if appState.isJiraConfigured {
                Task { await vm.load(appState: appState) }
            }
        }
        // Note sheet
        .sheet(isPresented: $showNoteSheet) {
            VStack(spacing: 16) {
                Text("Add Note to Alert").font(.headline)
                if let alert = selectedAlertForNote {
                    Text(alert.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                TextEditor(text: $noteText)
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.2))
                HStack {
                    Button("Cancel") { showNoteSheet = false; noteText = "" }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Add Note") {
                        if let alert = selectedAlertForNote {
                            Task {
                                await vm.addNoteToAlert(alert, note: noteText, appState: appState)
                                showNoteSheet = false; noteText = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20).frame(width: 400)
        }
        // Close confirmation
        .alert("Close Alert?", isPresented: $showCloseConfirm, presenting: alertToClose) { alert in
            Button("Close Alert", role: .destructive) {
                Task { await vm.closeAlert(alert, appState: appState) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { alert in
            Text(alert.message)
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

            let effectiveTeamIds = appState.activeJSMTeamIds.isEmpty
                ? appState.favoriteJSMTeams
                : appState.activeJSMTeamIds

            if effectiveTeamIds.isEmpty {
                noTeamsPrompt
            } else if vm.teams.isEmpty && !vm.isLoadingTeams {
                HStack(spacing: 8) {
                    Text("No schedules found. Check that your teams have schedules configured in JSM.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { appState.showSettings = true; appState.selectedSettingsTab = "products" } label: {
                        Text("Manage Products").font(.caption)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                let activeTeams = vm.teams.filter { effectiveTeamIds.contains($0.id) }
                if activeTeams.isEmpty && !vm.isLoadingTeams {
                    HStack(spacing: 8) {
                        Text("No matching teams found. Map JSM teams to your products in Settings → Products & Resources.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button { appState.showSettings = true; appState.selectedSettingsTab = "products" } label: {
                            Text("Manage Products").font(.caption)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(activeTeams) { team in
                            onCallCard(team)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .animation(.none, value: vm.onCallResults)
                    .animation(.none, value: vm.displayNames)
                    .animation(.none, value: vm.isLoadingOnCall)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func onCallCard(_ team: OpsTeam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            let teamSchedules = vm.allSchedules.filter { $0.teamId == team.id }

            if teamSchedules.isEmpty && vm.isLoadingOnCall {
                // Fixed-height placeholder — spinner is in the section header, not inline
                Color.clear.frame(height: 20)
            } else if teamSchedules.isEmpty {
                Text("No schedules configured for this team")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(teamSchedules) { schedule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.name).font(.caption.bold()).foregroundStyle(.secondary)
                        let participants = vm.onCallResults[schedule.id] ?? []
                        if participants.isEmpty && vm.isLoadingOnCall {
                            // Fixed-height placeholder — no inline spinner that shifts layout
                            Color.clear.frame(height: 20)
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

            Spacer(minLength: 0)  // push content to top, fill remaining height
        }
        .padding(12)
        .frame(minHeight: 120, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }

    private var noTeamsPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3").font(.title2).foregroundStyle(.secondary)
            Text("No on-call teams configured").font(.callout).foregroundStyle(.secondary)
            Text("Map JSM teams to your products in Settings → Products & Resources, or select a product at the top to filter.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Button("Manage Products") {
                appState.showSettings = true; appState.selectedSettingsTab = "products"
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding()
    }

    // MARK: - Alerts Section

    private var alertsSection: some View {
        let displayed = vm.filteredAlerts(userEmail: appState.jiraEmail)
        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Image(systemName: "bell.badge").foregroundStyle(.orange)
                Text("Alerts").font(.headline)
                Spacer()
                if vm.isLoadingAlerts { ProgressView().scaleEffect(0.7) }
                Picker("Filter", selection: $vm.alertFilter) {
                    ForEach(OnCallViewModel.AlertFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 380)
                Button(isSelectMode ? "Done" : "Select") {
                    isSelectMode.toggle()
                    if !isSelectMode { selectedAlertIds.removeAll() }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            // Success/error feedback (Phase 34F)
            if let success = vm.actionSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(success).font(.caption).foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let error = vm.actionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { vm.actionError = nil }.font(.caption).buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Bulk action bar (Phase 34E)
            if isSelectMode && !selectedAlertIds.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedAlertIds.count) selected").font(.callout.bold())
                    Spacer()
                    Button("Select All") {
                        selectedAlertIds = Set(displayed.map(\.id))
                    }.buttonStyle(.bordered).controlSize(.small)
                    Button {
                        let sel = displayed.filter { selectedAlertIds.contains($0.id) }
                        Task { await vm.bulkAcknowledge(alerts: sel, appState: appState) }
                        selectedAlertIds.removeAll()
                    } label: { Label("ACK All", systemImage: "checkmark.circle") }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button {
                        let sel = displayed.filter { selectedAlertIds.contains($0.id) }
                        Task { await vm.bulkClose(alerts: sel, appState: appState) }
                        selectedAlertIds.removeAll()
                    } label: { Label("Close All", systemImage: "xmark.circle") }
                    .buttonStyle(.bordered).controlSize(.small).tint(.red)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if displayed.isEmpty && !vm.isLoadingAlerts {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(vm.alertFilter == .assignedToMe
                         ? "No alerts assigned to you"
                         : "No \(vm.alertFilter == .all ? "" : vm.alertFilter.rawValue.lowercased() + " ")alerts")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(displayed) { alert in
                        alertRow(alert, isSelected: isSelectMode && selectedAlertIds.contains(alert.id))
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func toggleSelection(_ id: String) {
        if selectedAlertIds.contains(id) { selectedAlertIds.remove(id) }
        else { selectedAlertIds.insert(id) }
    }

    private func alertRow(_ alert: OpsAlert, isSelected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                // Selection checkbox (Phase 34E)
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .onTapGesture { toggleSelection(alert.id) }
                }

                Text(alert.priority)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(priorityColor(alert.priority).opacity(0.15)))
                    .foregroundStyle(priorityColor(alert.priority))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.message).font(.callout).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(alert.status.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(statusColor(alert.status).opacity(0.15)))
                            .foregroundStyle(statusColor(alert.status))
                        if alert.acknowledged {
                            Text("ACK").font(.caption2.bold()).foregroundStyle(.orange)
                        }
                        if !alert.source.isEmpty {
                            Text(alert.source).font(.caption2).foregroundStyle(.secondary)
                        }
                        if !alert.integrationType.isEmpty && alert.integrationType != alert.source {
                            Text(alert.integrationType).font(.caption2).foregroundStyle(.tertiary)
                        }
                        if !alert.createdAt.isEmpty {
                            Text(relativeTime(alert.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if !alert.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(alert.tags, id: \.self) { tag in
                                Text(tag).font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            }
                        }
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { if isSelectMode { toggleSelection(alert.id) } }

            // Action buttons (Phase 34C) — hidden in select mode
            if !isSelectMode {
                HStack(spacing: 6) {
                    if alert.status == "open" && !alert.acknowledged {
                        Button {
                            Task { await vm.acknowledgeAlert(alert, appState: appState) }
                        } label: { Label("ACK", systemImage: "checkmark.circle").font(.caption2) }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .disabled(vm.actionInProgress.contains(alert.id))
                    } else if alert.acknowledged && alert.status != "closed" {
                        Button {
                            Task { await vm.unacknowledgeAlert(alert, appState: appState) }
                        } label: { Label("Un-ACK", systemImage: "arrow.uturn.backward.circle").font(.caption2) }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .disabled(vm.actionInProgress.contains(alert.id))
                    }

                    if alert.status != "closed" {
                        Button {
                            alertToClose = alert; showCloseConfirm = true
                        } label: { Label("Close", systemImage: "xmark.circle").font(.caption2) }
                        .buttonStyle(.bordered).controlSize(.mini).tint(.red)
                        .disabled(vm.actionInProgress.contains(alert.id))

                        Menu {
                            Button("30 minutes") { snooze(alert, minutes: 30) }
                            Button("1 hour") { snooze(alert, minutes: 60) }
                            Button("4 hours") { snooze(alert, minutes: 240) }
                            Button("Until tomorrow 9 AM") { snoozeUntilTomorrow9AM(alert) }
                        } label: { Label("Snooze", systemImage: "moon.zzz").font(.caption2) }
                        .menuStyle(.borderlessButton)
                        .disabled(vm.actionInProgress.contains(alert.id))
                    }

                    Button {
                        selectedAlertForNote = alert; showNoteSheet = true
                    } label: { Label("Note", systemImage: "note.text.badge.plus").font(.caption2) }
                    .buttonStyle(.bordered).controlSize(.mini)

                    if vm.actionInProgress.contains(alert.id) {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Snooze helpers

    private func snooze(_ alert: OpsAlert, minutes: Int) {
        let endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        Task { await vm.snoozeAlert(alert, until: endTime, appState: appState) }
    }

    private func snoozeUntilTomorrow9AM(_ alert: OpsAlert) {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.day! += 1; comps.hour = 9; comps.minute = 0
        if let endTime = Calendar.current.date(from: comps) {
            Task { await vm.snoozeAlert(alert, until: endTime, appState: appState) }
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if message.contains("credentials") || message.contains("configured") {
                Button {
                    appState.showSettings = true; appState.selectedSettingsTab = "jira"
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

    // MARK: - Helpers

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red; case "P2": return .orange
        case "P3": return .yellow; case "P4": return .blue
        default: return .secondary
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "open": return .red; case "acked": return .orange
        case "closed": return .green; default: return .secondary
        }
    }

    private func relativeTime(_ isoString: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return String(isoString.prefix(10))
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

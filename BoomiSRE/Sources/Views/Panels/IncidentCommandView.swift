import SwiftUI
import Charts

struct IncidentCommandView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = IncidentViewModel()

    @State private var incidentFilter: IncidentFilter = .active
    @State private var incidentSort: IncidentSort = .created

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if filteredIncidents.isEmpty && !vm.isCreatingNew {
                emptyState
            } else {
                HSplitView {
                    incidentList
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                    incidentDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.activeIncidentCount = vm.activeHighPriorityCount
        }
    }

    // MARK: - Filtered / sorted incident list

    private var filteredIncidents: [Incident] {
        let base: [Incident]
        switch incidentFilter {
        case .active:
            base = vm.incidents.filter { $0.isActive }
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            base = vm.incidents.filter {
                $0.status == .resolved && ($0.resolvedAt ?? Date.distantPast) > cutoff
            }
        case .all:
            base = vm.incidents
        }
        return sortIncidents(base)
    }

    private func sortIncidents(_ list: [Incident]) -> [Incident] {
        switch incidentSort {
        case .created:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .severity:
            let order: [IncidentSeverity] = [.p1, .p2, .p3, .p4]
            return list.sorted {
                let ia = order.firstIndex(of: $0.severity) ?? 99
                let ib = order.firstIndex(of: $1.severity) ?? 99
                return ia < ib
            }
        case .duration:
            return list.sorted {
                let da = ($0.resolvedAt ?? Date()).timeIntervalSince($0.createdAt)
                let db = ($1.resolvedAt ?? Date()).timeIntervalSince($1.createdAt)
                return da > db
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Incident Command", systemImage: "exclamationmark.shield.fill")
                    .font(.title3.bold())
                    .foregroundStyle(vm.activeHighPriorityCount > 0 ? .red : .primary)

                if vm.activeHighPriorityCount > 0 {
                    Text("\(vm.activeHighPriorityCount) active")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red).clipShape(Capsule())
                } else if vm.activeIncidents.isEmpty && !vm.incidents.isEmpty {
                    Label("All clear", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }

                Spacer()

                Button {
                    vm.isCreatingNew = true
                } label: {
                    Label("Declare Incident", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            HStack(spacing: 12) {
                Picker("Filter", selection: $incidentFilter) {
                    ForEach(IncidentFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Menu {
                    ForEach(IncidentSort.allCases, id: \.self) { sort in
                        Button {
                            incidentSort = sort
                        } label: {
                            HStack {
                                Text(sort.rawValue)
                                if incidentSort == sort {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort: \(incidentSort.rawValue)", systemImage: "arrow.up.arrow.down")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 160)

                Spacer()
            }

            // Timeline chart — shown for recent/all when there are incidents
            if incidentFilter != .active && !vm.incidents.isEmpty {
                incidentTimelineChart
                    .frame(height: 80)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Timeline Chart

    private var incidentTimelineChart: some View {
        let weekData = buildWeekData()
        return Chart(weekData, id: \.week) { entry in
            BarMark(
                x: .value("Week", entry.week),
                y: .value("Count", entry.p1Count)
            )
            .foregroundStyle(Color.red)
            .position(by: .value("Severity", "P1"))

            BarMark(
                x: .value("Week", entry.week),
                y: .value("Count", entry.p2Count)
            )
            .foregroundStyle(Color.orange)
            .position(by: .value("Severity", "P2"))

            BarMark(
                x: .value("Week", entry.week),
                y: .value("Count", entry.p3Count)
            )
            .foregroundStyle(Color.yellow)
            .position(by: .value("Severity", "P3"))

            BarMark(
                x: .value("Week", entry.week),
                y: .value("Count", entry.p4Count)
            )
            .foregroundStyle(Color.blue)
            .position(by: .value("Severity", "P4"))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel()
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().font(.system(size: 9))
            }
        }
    }

    private struct WeekBucket {
        let week: String
        let p1Count: Int
        let p2Count: Int
        let p3Count: Int
        let p4Count: Int
    }

    private func buildWeekData() -> [WeekBucket] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [WeekBucket] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        for weekOffset in stride(from: -11, through: 0, by: 1) {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: now),
                  let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) else { continue }
            let label = fmt.string(from: weekStart)
            let inWeek = vm.incidents.filter { $0.createdAt >= weekStart && $0.createdAt < weekEnd }
            buckets.append(WeekBucket(
                week: label,
                p1Count: inWeek.filter { $0.severity == .p1 }.count,
                p2Count: inWeek.filter { $0.severity == .p2 }.count,
                p3Count: inWeek.filter { $0.severity == .p3 }.count,
                p4Count: inWeek.filter { $0.severity == .p4 }.count
            ))
        }
        return buckets
    }

    // MARK: - Empty State (filter-aware)

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            switch incidentFilter {
            case .active:
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56)).foregroundStyle(.green)
                Text("No Active Incidents").font(.title2.bold())
                Text("All systems operational. Declare an incident when an issue is detected.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 400)
                Button {
                    vm.isCreatingNew = true
                } label: {
                    Label("Declare Incident", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).tint(.red)
            case .recent:
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 56)).foregroundStyle(.secondary)
                Text("No Recent Incidents").font(.title2.bold())
                Text("No resolved incidents in the last 30 days.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 400)
            case .all:
                Image(systemName: "tray")
                    .font(.system(size: 56)).foregroundStyle(.secondary)
                Text("No Incidents Recorded").font(.title2.bold())
                Text("No incidents recorded yet. Declare an incident when an issue is detected.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 400)
                Button {
                    vm.isCreatingNew = true
                } label: {
                    Label("Declare Incident", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).tint(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $vm.isCreatingNew) {
            newIncidentSheet
        }
    }

    // MARK: - Incident List

    private var incidentList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredIncidents) { incident in
                        incidentRow(incident, isSelected: vm.selectedIncident?.id == incident.id)
                            .onTapGesture { vm.selectedIncident = incident; vm.aiOutput = nil }
                    }
                }
            }

            Spacer(minLength: 0)

            Divider()
            Button {
                vm.isCreatingNew = true
            } label: {
                Label("Declare Incident", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .sheet(isPresented: $vm.isCreatingNew) {
            newIncidentSheet
        }
    }

    private func incidentRow(_ incident: Incident, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: incident.severity.icon)
                .foregroundStyle(incident.severity.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(incident.title)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(incident.severity.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(incident.severity.color.opacity(0.15))
                        .clipShape(Capsule())
                    Text(incident.status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(incident.status.color)
                    Text(incident.elapsedString)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Incident Detail

    @ViewBuilder
    private var incidentDetail: some View {
        if let incident = vm.selectedIncident {
            HSplitView {
                // Left: timeline + actions
                leftPanel(incident)
                    .frame(minWidth: 300)
                // Right: AI + metadata
                rightPanel(incident)
                    .frame(minWidth: 280, maxWidth: 420)
            }
        } else if vm.isCreatingNew {
            Color.clear // handled by sheet
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Select an incident to view details")
                    .font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Left Panel (Timeline + Actions)

    private func leftPanel(_ incident: Incident) -> some View {
        VStack(spacing: 0) {
            // Incident header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(incident.title).font(.title3.bold()).lineLimit(2)
                    HStack(spacing: 8) {
                        severityBadge(incident.severity)
                        statusBadge(incident.status)
                        Label(incident.elapsedString, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let key = incident.jiraTicketKey, let url = URL(string: "https://boomii.atlassian.net/browse/\(key)") {
                        Link("\(key) ↗", destination: url).font(.caption)
                    }
                }
                Spacer()
                Menu {
                    ForEach(IncidentStatus.allCases, id: \.self) { status in
                        Button {
                            vm.updateStatus(status, appState: appState)
                        } label: {
                            Label(status.rawValue, systemImage: status.icon)
                        }
                        .disabled(incident.status == status)
                    }
                    Divider()
                    Button(role: .destructive) {
                        vm.deleteIncident(id: incident.id, appState: appState)
                    } label: {
                        Label("Delete Incident", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(16)

            Divider()

            // Timeline
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(incident.timeline) { entry in
                        timelineRow(entry)
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            Divider()

            // Add timeline entry
            addEntryBar(incident)
        }
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline line + icon
            VStack(spacing: 0) {
                Image(systemName: entry.sourceIcon)
                    .font(.caption)
                    .foregroundStyle(entry.sourceColor)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.source.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(entry.sourceColor)
                    Text(entry.timestamp, style: .time)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(renderedMarkdown(entry.content))
                    .font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
            }
        }
    }

    private func addEntryBar(_ incident: Incident) -> some View {
        HStack(spacing: 8) {
            TextField("Add timeline entry…", text: $vm.entryInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit {
                    if !vm.entryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        vm.addTimelineEntry(appState: appState)
                    }
                }
            Button {
                vm.addTimelineEntry(appState: appState)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
                    .foregroundStyle(vm.entryInput.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(vm.entryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Right Panel (AI + Metadata + Actions)

    private func rightPanel(_ incident: Incident) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // AI action buttons
                aiActionsSection(incident)

                // Metadata
                metadataSection(incident)

                // Jira linking
                jiraSection(incident)
            }
            .padding(16)
        }
    }

    private func aiActionsSection(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI Assistant", systemImage: "sparkles").font(.headline).foregroundStyle(.purple)
                Spacer()
                if vm.isAnalyzing { ProgressView().scaleEffect(0.8) }
                if vm.aiOutput != nil {
                    Button { vm.aiOutput = nil; vm.aiOutputLabel = "" } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }

            // 2×2 button grid
            let actions: [(String, String, () async -> Void)] = [
                ("Analyze Incident",   "magnifyingglass",     { await vm.analyzeIncident() }),
                ("Draft Status Update","megaphone",           { await vm.draftStatusUpdate() }),
                ("Draft Postmortem",   "doc.text",            { await vm.draftPostmortem() }),
                ("Suggest Remediation","wrench.and.screwdriver", { await vm.suggestRemediation() }),
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button {
                        Task { await action.2() }
                    } label: {
                        Label(action.0, systemImage: action.1)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isAnalyzing)
                }
            }

            if let err = vm.aiError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            if let output = vm.aiOutput {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(vm.aiOutputLabel)
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy")
                    }
                    Text(renderedMarkdown(output))
                        .textSelection(.enabled)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.purple.opacity(0.2)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func metadataSection(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Incident Details").font(.subheadline.bold())

            metaRow("Created", incident.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let resolved = incident.resolvedAt {
                metaRow("Resolved", resolved.formatted(date: .abbreviated, time: .shortened))
            }
            metaRow("Duration", incident.elapsedString)
            metaRow("Severity", incident.severity.label)
            metaRow("Status", incident.status.rawValue)
            if !incident.affectedServices.isEmpty {
                metaRow("Affected", incident.affectedServices.joined(separator: ", "))
            }
            metaRow("Timeline entries", "\(incident.timeline.count)")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func jiraSection(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jira").font(.subheadline.bold())

            if let key = incident.jiraTicketKey {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill").foregroundStyle(.blue)
                    if let url = URL(string: "https://boomii.atlassian.net/browse/\(key)") {
                        Link(key, destination: url).font(.callout)
                    }
                    Spacer()
                    Button {
                        if let id = incident.id as UUID?,
                           let idx = vm.incidents.firstIndex(where: { $0.id == id }) {
                            vm.incidents[idx].jiraTicketKey = nil
                            vm.selectedIncident = vm.incidents[idx]
                        }
                    } label: { Image(systemName: "xmark.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Link ticket key (e.g. CAMSRE-123)", text: $vm.jiraKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { vm.linkJiraTicket(appState: appState) }
                    Button("Link") { vm.linkJiraTicket(appState: appState) }
                        .buttonStyle(.bordered)
                        .disabled(vm.jiraKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if appState.isJiraConfigured {
                    Button {
                        Task { await vm.createJiraTicket(appState: appState) }
                    } label: {
                        if vm.isLinkingJira {
                            Label("Creating…", systemImage: "ticket")
                        } else {
                            Label("Create New Jira Ticket", systemImage: "ticket.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isLinkingJira)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    // MARK: - New Incident Sheet

    private var newIncidentSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Declare Incident", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.red)
                Spacer()
                Button("Cancel") { vm.isCreatingNew = false }
                    .keyboardShortcut(.escape)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Incident Title").font(.subheadline.bold())
                TextField("Describe what is happening…", text: $vm.newTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Severity").font(.subheadline.bold())
                Picker("Severity", selection: $vm.newSeverity) {
                    ForEach(IncidentSeverity.allCases, id: \.self) { sev in
                        HStack {
                            Image(systemName: sev.icon).foregroundStyle(sev.color)
                            Text(sev.label)
                        }.tag(sev)
                    }
                }
                .pickerStyle(.segmented)
                Text(severityGuide(vm.newSeverity))
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Affected Services (comma-separated)").font(.subheadline.bold())
                TextField("e.g. API Gateway, Auth Service, MFT", text: $vm.newAffectedServices)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Declare Incident") {
                    vm.createIncident(appState: appState)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(vm.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(minWidth: 500)
    }

    // MARK: - Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
            Text(value).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func severityBadge(_ sev: IncidentSeverity) -> some View {
        Label(sev.label, systemImage: sev.icon)
            .font(.caption.bold())
            .foregroundStyle(sev.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(sev.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusBadge(_ status: IncidentStatus) -> some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func renderedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }

    private func severityGuide(_ sev: IncidentSeverity) -> String {
        switch sev {
        case .p1: return "P1 — Customer-facing outage, data loss, or complete service failure. Page immediately."
        case .p2: return "P2 — Significant degradation affecting multiple customers. Respond within 15 minutes."
        case .p3: return "P3 — Partial degradation, limited customer impact. Respond within 1 hour."
        case .p4: return "P4 — Minor issue, minimal impact. Address during business hours."
        }
    }
}

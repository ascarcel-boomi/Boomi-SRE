import SwiftUI
import Charts

struct IncidentCommandView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = IncidentViewModel()

    @State private var incidentSort: IncidentSort = .created

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if !appState.isJiraConfigured {
                emptyJiraNotConfigured
            } else if vm.isLoading && vm.incidents.isEmpty {
                loadingState
            } else if vm.filteredIncidents.isEmpty {
                emptyState
            } else {
                HSplitView {
                    incidentList
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)
                    incidentDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.configure(with: appState.userProfile)
            Task { await vm.fetchIncidents(appState: appState) }
        }
        .onChange(of: vm.incidentFilter) {
            Task { await vm.fetchIncidents(appState: appState) }
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
                }

                if let fetched = vm.lastFetched {
                    Text("Updated \(fetched, style: .relative) ago")
                        .font(.caption).foregroundStyle(.tertiary)
                }

                Spacer()

                if vm.isLoading {
                    ProgressView().scaleEffect(0.75)
                }

                Button {
                    Task { await vm.fetchIncidents(appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh incidents from Jira")

                Button {
                    if let url = URL(string: "\(appState.jiraBaseURL)/secure/CreateIssue!default.jspa") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Create in Jira", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if let err = vm.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(err).font(.callout).foregroundStyle(.red)
                    Spacer()
                    Button {
                        Task { await vm.fetchIncidents(appState: appState) }
                    } label: { Text("Retry") }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Picker("Filter", selection: $vm.incidentFilter) {
                    ForEach(IncidentFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                TextField("Search incidents…", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Menu {
                    ForEach(IncidentSort.allCases, id: \.self) { sort in
                        Button {
                            incidentSort = sort
                        } label: {
                            HStack {
                                Text(sort.rawValue)
                                if incidentSort == sort { Image(systemName: "checkmark") }
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

            // Product element pills
            if !appState.favoriteProductElements.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
                        ForEach(appState.favoriteProductElements, id: \.self) { element in
                            Text(element)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(height: 28)
            }

            // Timeline chart for non-active filters
            if vm.incidentFilter != .active && !vm.incidents.isEmpty {
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
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p1Count))
                .foregroundStyle(Color.red).position(by: .value("Severity", "P1"))
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p2Count))
                .foregroundStyle(Color.orange).position(by: .value("Severity", "P2"))
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p3Count))
                .foregroundStyle(Color.yellow).position(by: .value("Severity", "P3"))
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p4Count))
                .foregroundStyle(Color.blue).position(by: .value("Severity", "P4"))
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel().font(.system(size: 9)) } }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().font(.system(size: 9)) } }
    }

    private struct WeekBucket {
        let week: String; let p1Count: Int; let p2Count: Int; let p3Count: Int; let p4Count: Int
    }

    private func buildWeekData() -> [WeekBucket] {
        let cal = Calendar.current
        let now = Date()
        return stride(from: -11, through: 0, by: 1).compactMap { offset in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: offset, to: now),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
            let inWeek = vm.incidents.filter { $0.createdAt >= weekStart && $0.createdAt < weekEnd }
            return WeekBucket(week: Formatters.monthDay.string(from: weekStart),
                p1Count: inWeek.filter { $0.severity == .p1 }.count,
                p2Count: inWeek.filter { $0.severity == .p2 }.count,
                p3Count: inWeek.filter { $0.severity == .p3 }.count,
                p4Count: inWeek.filter { $0.severity == .p4 }.count)
        }
    }

    // MARK: - Empty / Loading States

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.2)
            Text("Loading incidents from Jira…")
                .font(.body).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyJiraNotConfigured: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.shield").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Jira Not Configured").font(.title2.bold())
            Text("Configure Jira in Settings to view incidents.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            switch vm.incidentFilter {
            case .active:
                Image(systemName: "checkmark.shield.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("No Active Incidents").font(.title2.bold())
                if appState.favoriteProductElements.isEmpty {
                    Text("Select product elements in Settings → Incidents to see relevant incidents.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                } else {
                    Text("All clear. No active incidents for your product elements.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                }
            case .recent:
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 56)).foregroundStyle(.secondary)
                Text("No Recent Incidents").font(.title2.bold())
                Text("No incidents in the last 30 days.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            case .all:
                Image(systemName: "tray").font(.system(size: 56)).foregroundStyle(.secondary)
                Text("No Incidents Found").font(.title2.bold())
                Text("No incidents found in the last 90 days matching your filters.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Incident List

    private var incidentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedIncidents) { incident in
                    incidentRow(incident, isSelected: vm.selectedIncident?.id == incident.id)
                        .onTapGesture {
                            vm.selectedIncident = incident
                            vm.aiOutput = nil
                            vm.selectedIncidentComments = []
                            Task { await vm.loadComments(for: incident, appState: appState) }
                        }
                }
            }
        }
    }

    private var sortedIncidents: [Incident] {
        let severityOrder: [IncidentSeverity] = [.p1, .p2, .p3, .p4]
        return vm.filteredIncidents.sorted { a, b in
            switch incidentSort {
            case .created:  return a.createdAt > b.createdAt
            case .severity:
                let ia = severityOrder.firstIndex(of: a.severity) ?? 99
                let ib = severityOrder.firstIndex(of: b.severity) ?? 99
                return ia < ib
            case .duration:
                let da = (a.resolvedAt ?? Date()).timeIntervalSince(a.createdAt)
                let db = (b.resolvedAt ?? Date()).timeIntervalSince(b.createdAt)
                return da > db
            }
        }
    }

    private func incidentRow(_ incident: Incident, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            // Severity badge
            Text(incident.severity.label)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(incident.severity.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                // Ticket key
                if let key = incident.jiraTicketKey {
                    Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                // Title
                Text(incident.title)
                    .font(.callout)
                    .lineLimit(2)
                // Status + time
                HStack(spacing: 6) {
                    Text(incident.status.rawValue)
                        .font(.caption2).foregroundStyle(incident.status.color)
                    Text("·")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(incident.createdAt, style: .relative)
                        .font(.caption2).foregroundStyle(.tertiary)
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
                leftPanel(incident)
                    .frame(minWidth: 300)
                rightPanel(incident)
                    .frame(minWidth: 280, maxWidth: 420)
            }
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

    // MARK: - Left Panel (Timeline + Comments)

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
                    if let key = incident.jiraTicketKey {
                        HStack(spacing: 10) {
                            if let url = URL(string: "\(appState.jiraBaseURL)/browse/\(key)") {
                                Link("Open in Jira ↗", destination: url).font(.caption)
                            }
                            Button("View Full Ticket") {
                                appState.selectedTicketKey = key
                            }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        }
                    }
                }
                Spacer()
            }
            .padding(16)

            Divider()

            // Comments timeline
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if vm.isLoadingComments {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Loading comments…").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(16)
                    } else if vm.selectedIncidentComments.isEmpty {
                        Text("No comments on this incident yet.")
                            .font(.callout).foregroundStyle(.secondary).padding(16)
                    } else {
                        ForEach(vm.selectedIncidentComments) { comment in
                            commentRow(comment)
                        }
                    }
                    Color.clear.frame(height: 80)
                }
            }

            Divider()

            // Post comment bar
            postCommentBar(incident)
        }
    }

    private func commentRow(_ comment: JiraComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.authorName)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text(comment.created.prefix(16).replacingOccurrences(of: "T", with: " "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Text(comment.bodyText)
                .font(.callout).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func postCommentBar(_ incident: Incident) -> some View {
        HStack(spacing: 8) {
            TextField("Post a comment…", text: $vm.commentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit {
                    if !vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { await vm.postComment(appState: appState) }
                    }
                }
            if vm.isPostingComment {
                ProgressView().scaleEffect(0.75)
            } else {
                Button {
                    Task { await vm.postComment(appState: appState) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(vm.commentInput.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Right Panel (AI + Metadata)

    private func rightPanel(_ incident: Incident) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                aiActionsSection(incident)
                metadataSection(incident)
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

            let actions: [(String, String, () async -> Void)] = [
                ("Analyze Incident",      "magnifyingglass",        { await vm.analyzeIncident() }),
                ("Draft Status Update",   "megaphone",              { await vm.draftStatusUpdate() }),
                ("Draft Postmortem",      "doc.text",               { await vm.draftPostmortem() }),
                ("Suggest Remediation",   "wrench.and.screwdriver", { await vm.suggestRemediation() }),
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button { Task { await action.2() } } label: {
                        Label(action.0, systemImage: action.1)
                            .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 8)
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
                        Text(vm.aiOutputLabel).font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy")
                    }
                    Text(renderedMarkdown(output))
                        .textSelection(.enabled).font(.callout)
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
            metaRow("Jira Key", incident.jiraTicketKey ?? "—")
            metaRow("Severity", incident.severity.label)
            metaRow("Status", incident.status.rawValue)
            metaRow("Duration", incident.elapsedString)
            metaRow("Created", incident.createdAt.formatted(date: .abbreviated, time: .shortened))
            if !incident.affectedServices.isEmpty {
                metaRow("Product Elements", incident.affectedServices.joined(separator: ", "))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    // MARK: - Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
            Text(value).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func severityBadge(_ sev: IncidentSeverity) -> some View {
        Label(sev.label, systemImage: sev.icon)
            .font(.caption.bold()).foregroundStyle(sev.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(sev.color.opacity(0.12)).clipShape(Capsule())
    }

    private func statusBadge(_ status: IncidentStatus) -> some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.caption).foregroundStyle(status.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status.color.opacity(0.12)).clipShape(Capsule())
    }

    private func renderedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }
}

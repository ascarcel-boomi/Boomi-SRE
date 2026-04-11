import SwiftUI
import Charts

struct IncidentCommandView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = IncidentViewModel()

    @State private var incidentSort: IncidentSort = .created
    @State private var descriptionPaneHeight: CGFloat = 200
    @State private var selectedChartWeek: String?  // tapped bar chart week label
    @State private var assigneeSearchText: String = ""
    @State private var isEditingAssignee = false
    private static let minDescHeight: CGFloat = 60
    private static let maxDescHeight: CGFloat = 600

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
                        .splitGrip()
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
            selectedChartWeek = nil
            Task { await vm.fetchIncidents(appState: appState) }
        }
        .onChange(of: appState.activeProductIds) {
            if appState.isJiraConfigured {
                Task { await vm.fetchIncidents(appState: appState) }
            }
        }
        .onChange(of: appState.refreshTrigger) {
            if appState.isJiraConfigured {
                Task { await vm.fetchIncidents(appState: appState) }
            }
        }
        .onChange(of: vm.selectedIncident?.jiraTicketKey) {
            assigneeSearchText = ""
            isEditingAssignee = false
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
                .accessibilityLabel("Refresh incidents")

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
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            }

            HStack(spacing: 8) {
                Text("Filter")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Picker("Filter", selection: $vm.incidentFilter) {
                    ForEach(IncidentFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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

            // Scope toggle + product element pills
            HStack(spacing: 8) {
                Text("Scope")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Picker("Scope", selection: Binding(
                    get: { appState.showAllIncidents ? "all" : "filtered" },
                    set: { val in
                        appState.showAllIncidents = (val == "all")
                        appState.saveConfig()
                        Task { await vm.fetchIncidents(appState: appState) }
                    }
                )) {
                    Text("My Teams").tag("filtered")
                    Text("All Incidents").tag("all")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                if !appState.showAllIncidents {
                    let activeElements = appState.activeIncidentProductElements.isEmpty
                        ? (appState.selectedProduct?.incidentProductElements ?? appState.favoriteProductElements)
                        : appState.activeIncidentProductElements
                    if !activeElements.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
                                ForEach(activeElements, id: \.self) { element in
                                    Text(element)
                                        .font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .frame(height: 28)
                    } else {
                        Label("No product elements configured", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Spacer()
            }

            // Timeline chart for non-active filters
            if vm.incidentFilter != .active && !vm.incidents.isEmpty {
                HStack(spacing: 0) {
                    incidentTimelineChart
                    if selectedChartWeek != nil {
                        Button { selectedChartWeek = nil } label: {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                    }
                }
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
            let dimmed = selectedChartWeek != nil && selectedChartWeek != entry.week
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p1Count))
                .foregroundStyle(Color.red.opacity(dimmed ? 0.2 : 1)).position(by: .value("Severity", "P1"))
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p2Count))
                .foregroundStyle(Color.orange.opacity(dimmed ? 0.2 : 1)).position(by: .value("Severity", "P2"))
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p3Count))
                .foregroundStyle(Color.yellow.opacity(dimmed ? 0.2 : 1)).position(by: .value("Severity", "P3"))
            BarMark(x: .value("Week", entry.week), y: .value("Count", entry.p4Count))
                .foregroundStyle(Color.blue.opacity(dimmed ? 0.2 : 1)).position(by: .value("Severity", "P4"))
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel().font(.system(size: 9)) } }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().font(.system(size: 9)) } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        if let week: String = proxy.value(atX: location.x) {
                            selectedChartWeek = (selectedChartWeek == week) ? nil : week
                        }
                    }
            }
        }
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
                let hasElements = appState.selectedProduct?.incidentProductElements.isEmpty == false || !appState.favoriteProductElements.isEmpty
                if !hasElements {
                    Text("Select a product at the top to filter incidents, or map product elements in Settings → Products & Resources.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                } else {
                    Text("All clear. No active incidents for your product.")
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
                            vm.selectIncident(incident, appState: appState)
                        }
                }
            }
        }
    }

    private var sortedIncidents: [Incident] {
        let severityOrder: [IncidentSeverity] = [.p1, .p2, .p3, .p4]
        let base: [Incident]
        if let week = selectedChartWeek {
            // Filter to incidents created in the selected chart week
            let cal = Calendar.current
            let now = Date()
            let weekStarts = stride(from: -11, through: 0, by: 1).compactMap { offset -> (String, Date, Date)? in
                guard let ws = cal.date(byAdding: .weekOfYear, value: offset, to: now),
                      let we = cal.date(byAdding: .day, value: 7, to: ws) else { return nil }
                return (Formatters.monthDay.string(from: ws), ws, we)
            }
            if let match = weekStarts.first(where: { $0.0 == week }) {
                base = vm.filteredIncidents.filter { $0.createdAt >= match.1 && $0.createdAt < match.2 }
            } else {
                base = vm.filteredIncidents
            }
        } else {
            base = vm.filteredIncidents
        }
        return base.sorted { a, b in
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
                    .splitGrip()
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
                                appState.pushNavigation()
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

            // Top: Description (rich Markdown from Jira ADF)
            if !incident.description.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    MarkdownView(markdown: incident.description, appTheme: appState.appTheme)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                .frame(height: descriptionPaneHeight)

                // Drag handle
                descriptionResizeHandle
            }

            // Bottom: Comments timeline
            if vm.isLoadingComments {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading comments…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(16)
            } else if vm.selectedIncidentComments.isEmpty {
                Text("No comments on this incident yet.")
                    .font(.callout).foregroundStyle(.secondary).padding(16)
                Spacer()
            } else {
                MarkdownView(markdown: commentsAsMarkdown, appTheme: appState.appTheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 4)
            }

            Divider()

            // Post comment bar
            postCommentBar(incident)
        }
    }

    // MARK: - Resize Handle

    private var descriptionResizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 5)
            }
            .frame(height: 9)
            .contentShape(Rectangle())
            .cursor(.resizeUpDown)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newHeight = descriptionPaneHeight + value.translation.height
                        descriptionPaneHeight = min(max(newHeight, Self.minDescHeight), Self.maxDescHeight)
                    }
            )
    }

    /// Combine all comments into a single markdown document for rich rendering.
    private var commentsAsMarkdown: String {
        vm.selectedIncidentComments.map { comment in
            let date = comment.created.prefix(16).replacingOccurrences(of: "T", with: " ")
            return "**\(comment.authorName)**  \u{2022}  \(date)\n\n\(comment.bodyMarkdown)\n\n---"
        }.joined(separator: "\n\n")
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
                if !incident.extraFields.isEmpty {
                    extraFieldsSection(incident)
                }
                if !incident.slaFields.isEmpty {
                    slaSection(incident)
                }
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
                    MarkdownView(markdown: output)
                        .frame(minHeight: 200)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.purple.opacity(0.2)))
            }

            if !vm.suggestedFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Suggested Fields", systemImage: "wand.and.stars")
                            .font(.caption.bold()).foregroundStyle(.purple)
                        Spacer()
                        if vm.suggestedFields.contains(where: { !$0.applied }) {
                            Button {
                                Task { await vm.applyAllSuggestedFields(appState: appState) }
                            } label: {
                                Label("Apply All", systemImage: "checkmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                    }
                    ForEach(vm.suggestedFields) { field in
                        HStack {
                            Text(field.fieldName).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .trailing)
                            Text(field.fieldValue).font(.caption.bold())
                            Spacer()
                            if field.applied {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green).font(.caption)
                            } else {
                                Button {
                                    Task { await vm.applySuggestedField(field, appState: appState) }
                                } label: {
                                    Text("Apply").font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.15)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func metadataSection(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Incident Details").font(.subheadline.bold())

            // Read-only fields
            metaRow("Jira Key", incident.jiraTicketKey ?? "—")
            metaRow("Duration", incident.elapsedString)
            metaRow("Created", incident.createdAt.formatted(date: .abbreviated, time: .shortened))
            if !incident.reporterName.isEmpty {
                metaRow("Reporter", incident.reporterName)
            }

            Divider()

            // Editable: Product Element
            if !appState.availableProductElements.isEmpty, let key = incident.jiraTicketKey {
                HStack(alignment: .top) {
                    Text("Product Element").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    Picker("", selection: Binding(
                        get: { incident.affectedServices.first ?? "" },
                        set: { newValue in
                            Task { await vm.updateProductElement(newValue, for: key, appState: appState) }
                        }
                    )) {
                        Text("Unset").tag("")
                        ForEach(appState.availableProductElements, id: \.self) { element in
                            Text(element).tag(element)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if appState.incidentProductElementFieldId.isEmpty {
                HStack(alignment: .top) {
                    Text("Product Element").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    Text("Discover in Settings")
                        .font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Editable: Priority
            if let key = incident.jiraTicketKey {
                HStack(alignment: .top) {
                    Text("Priority").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    Picker("", selection: Binding(
                        get: { priorityNameFromSeverity(incident.severity) },
                        set: { newValue in
                            Task { await vm.updatePriority(newValue, for: key, appState: appState) }
                        }
                    )) {
                        ForEach(["Highest", "Critical", "High", "Medium", "Low", "Lowest"], id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Editable: Assignee
            if let key = incident.jiraTicketKey {
                HStack(alignment: .top) {
                    Text("Assignee").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        if isEditingAssignee {
                            TextField("Search users…", text: $assigneeSearchText)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onChange(of: assigneeSearchText) {
                                    Task {
                                        let results = await vm.searchAssignableUsers(query: assigneeSearchText, appState: appState)
                                        withAnimation(.none) { vm.assigneeSearchResults = results }
                                    }
                                }
                            if !vm.assigneeSearchResults.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(vm.assigneeSearchResults) { user in
                                        Button {
                                            Task {
                                                await vm.updateAssignee(user, for: key, appState: appState)
                                                isEditingAssignee = false
                                                assigneeSearchText = ""
                                                vm.assigneeSearchResults = []
                                            }
                                        } label: {
                                            Text(user.displayName)
                                                .font(.caption)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 3)
                                                .padding(.horizontal, 6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                            }
                            Button("Cancel") {
                                isEditingAssignee = false
                                assigneeSearchText = ""
                                vm.assigneeSearchResults = []
                            }
                            .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 6) {
                                Text(incident.assigneeName.isEmpty ? "Unassigned" : incident.assigneeName)
                                    .font(.caption)
                                Button { isEditingAssignee = true } label: {
                                    Image(systemName: "pencil.circle").font(.caption)
                                }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Status (read-only display)
            metaRow("Status", incident.status.rawValue)

            // Transitions
            if let key = incident.jiraTicketKey, !vm.detailTransitions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions").font(.caption.bold()).foregroundStyle(.secondary)
                    if vm.isTransitioning {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Transitioning…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(vm.detailTransitions) { transition in
                            Button {
                                Task { await vm.applyTransition(transition, for: key, appState: appState) }
                            } label: {
                                Text(transition.name)
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(transitionColor(transition.toCategory))
                        }
                    }
                }
            }

            // Feedback toasts
            if let feedback = vm.fieldUpdateFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedback.hasPrefix("Failed") ? .red : .green)
            }
            if let feedback = vm.transitionFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedback.hasPrefix("Failed") ? .red : .green)
            }

            // Loading indicator for field updates
            if vm.isUpdatingField {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Updating…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func extraFieldsSection(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Incident Info").font(.subheadline.bold())
            ForEach(incident.extraFields) { field in
                let lowerLabel = field.label.lowercased()
                if lowerLabel.contains("google meet") && !field.value.isEmpty {
                    // Google Meet — styled like Calendar screen
                    HStack(alignment: .top) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        if let url = URL(string: field.value) {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Label("Join Google Meet", systemImage: "arrow.up.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        } else {
                            Text(field.value).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if lowerLabel.contains("slack") && !field.value.isEmpty {
                    // Slack Channel — clickable link
                    HStack(alignment: .top) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        if let url = URL(string: field.value) {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Label(url.lastPathComponent.isEmpty ? "Open in Slack" : url.lastPathComponent,
                                      systemImage: "number")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.purple)
                        } else {
                            Text(field.value).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if field.value.hasPrefix("http://") || field.value.hasPrefix("https://") {
                    HStack(alignment: .top) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        if let url = URL(string: field.value) {
                            Link(field.value, destination: url)
                                .font(.caption)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    metaRow(field.label, field.value)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func slaSection(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SLAs").font(.subheadline.bold())
            ForEach(incident.slaFields) { sla in
                HStack(alignment: .top) {
                    Text(sla.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sla.elapsed)
                            .font(.caption)
                            .textSelection(.enabled)
                        if sla.breached {
                            Label("Breached", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private func transitionColor(_ category: String) -> Color {
        switch category {
        case "In Progress": return .blue
        case "Done": return .green
        default: return .orange
        }
    }

    private func priorityNameFromSeverity(_ severity: IncidentSeverity) -> String {
        switch severity {
        case .p1: return "Highest"
        case .p2: return "High"
        case .p3: return "Medium"
        case .p4: return "Low"
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

}

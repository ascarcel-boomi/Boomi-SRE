import SwiftUI

struct TodoDashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = TodoDashboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            spSummaryBar
            Divider()
            filterBar
            Divider()

            if let error = viewModel.error {
                errorBanner(error)
            } else if viewModel.items.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                if !viewModel.filteredChartSections.isEmpty {
                    chartRow
                    Divider()
                }
                HSplitView {
                    ticketList
                        .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)
                        .splitGrip()
                    ticketDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if viewModel.items.isEmpty {
                Task { await viewModel.refresh(appState: appState) }
            }
        }
        .onChange(of: appState.activeProductIds) {
            if let last = viewModel.lastRefreshed, Date().timeIntervalSince(last) < 30 { return }
            Task { await viewModel.refresh(appState: appState) }
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("My Tickets")
                    .font(.title2.bold())
                if let last = viewModel.lastRefreshed {
                    Text("Last refreshed: \(last, format: .dateTime)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView().scaleEffect(0.8)
            }
            Button {
                Task { await viewModel.refresh(appState: appState) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, DesignTokens.panelPadding)
        .padding(.vertical, 12)
    }

    // MARK: - SP Summary bar

    private var spSummaryBar: some View {
        let s = viewModel.spSummary
        return HStack(spacing: 20) {
            spStatPill(
                label: "Completed",
                value: s.completedPoints,
                of: s.committedPoints,
                color: .green
            )
            Divider().frame(height: 24)
            spStatPill(
                label: "Committed (Sprint)",
                value: s.committedPoints,
                of: nil,
                color: .blue
            )
            Divider().frame(height: 24)
            spStatPill(
                label: "Planned",
                value: s.plannedPoints,
                of: nil,
                color: .orange
            )
            Divider().frame(height: 24)
            spStatPill(
                label: "Unplanned",
                value: s.unplannedPoints,
                of: nil,
                color: .gray
            )
            Spacer()
        }
        .padding(.horizontal, DesignTokens.panelPadding)
        .padding(.vertical, 8)
    }

    private func spStatPill(label: String, value: Double, of total: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                let display = value == Double(Int(value)) ? "\(Int(value))" : String(format: "%.1f", value)
                Text(display)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(value > 0 ? color : .secondary)
                if let total, total > 0 {
                    Text("/ \(total == Double(Int(total)) ? "\(Int(total))" : String(format: "%.1f", total))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("SP")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart row

    private var chartRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.filteredChartSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ReportChartView(section: section)
                            .frame(width: 340, height: 220)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, DesignTokens.panelPadding)
            .padding(.vertical, 8)
        }
        .frame(height: 270)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Label("Filter:", systemImage: "line.3.horizontal.decrease")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Status", selection: $viewModel.statusFilter) {
                ForEach(TicketStatusFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 130)

            Picker("Priority", selection: $viewModel.priorityFilter) {
                ForEach(TicketPriorityFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 130)

            if viewModel.statusFilter != .all || viewModel.priorityFilter != .all {
                Button("Clear") {
                    viewModel.statusFilter = .all
                    viewModel.priorityFilter = .all
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
            }

            Spacer()

            Text("\(viewModel.filteredItems.count) of \(viewModel.items.count) tickets")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.panelPadding)
        .padding(.vertical, 8)
    }

    // MARK: - Ticket list (left pane)

    private var ticketList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.groupedItems, id: \.0) { (category, items) in
                    categoryHeader(category, count: items.count)
                    ForEach(items) { item in
                        ticketRow(item)
                            .onTapGesture {
                                viewModel.selectItem(item, appState: appState)
                            }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func categoryHeader(_ category: TodoCategory, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorFor(category))
                .frame(width: 8, height: 8)
            Text(category.rawValue)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func ticketRow(_ item: TodoItem) -> some View {
        let isSelected = viewModel.selectedItem?.id == item.id
        return HStack(spacing: 10) {
            // Priority indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor(item.priority))
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.key)
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.blue)
                    Spacer(minLength: 0)
                    PillBadge(text: item.status, color: statusColor(item.statusCategoryName))
                }
                Text(item.summary)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let sprint = item.sprint {
                        CompactBadge(text: sprint.name, color: .blue)
                    }
                    if let due = item.dueDate {
                        let isOverdue = due < Date()
                        Text(due, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                    }
                    Spacer(minLength: 0)
                    Text(item.assignee == "Unassigned" ? "" : item.assignee)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Ticket detail (right pane)

    @ViewBuilder
    private var ticketDetail: some View {
        if let item = viewModel.selectedItem {
            VStack(spacing: 0) {
                detailHeader(item)
                Divider()
                HSplitView {
                    detailMainContent(item)
                        .frame(minWidth: 280)
                        .splitGrip()
                    detailSidebar(item)
                        .frame(minWidth: 220, maxWidth: 300)
                }
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "ticket")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Select a ticket to view details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Detail header

    private func detailHeader(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.key)
                        .font(.callout.monospaced().bold())
                        .foregroundStyle(.blue)
                    PillBadge(text: item.status, color: statusColor(item.statusCategoryName), bold: true)
                    PillBadge(text: item.priority, color: priorityColor(item.priority))
                    if viewModel.isLoadingDetail {
                        ProgressView().scaleEffect(0.65)
                    }
                }
                Text(item.summary)
                    .font(.title3.bold())
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    if let url = URL(string: "\(appState.jiraBaseURL)/browse/\(item.key)") {
                        Link("Open in Jira ↗", destination: url)
                            .font(.caption)
                    }
                    if let sprint = item.sprint {
                        Label(sprint.name, systemImage: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let due = item.dueDate {
                        let isOverdue = due < Date()
                        Text(due, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                viewModel.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Detail main content (description + comments)

    private func detailMainContent(_ item: TodoItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    descriptionSection

                    // Last 3 comments
                    commentsSection

                    Color.clear.frame(height: 60)
                }
                .padding(DesignTokens.cardPadding)
            }

            Divider()

            // Comment input
            commentInputBar(item)
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderLabel(title: "Description", icon: "doc.text")
            if let detail = viewModel.detailIssue {
                let descriptionText = extractDescriptionText(from: detail.raw)
                if descriptionText.isEmpty {
                    Text("No description.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownView(markdown: descriptionText, appTheme: appState.appTheme)
                        .frame(minHeight: 80, maxHeight: 300)
                        .cardStyle()
                }
            } else if viewModel.isLoadingDetail {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let err = viewModel.detailError {
                Text(err).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderLabel(
                title: "Comments (\(viewModel.detailComments.count))",
                icon: "bubble.left.and.bubble.right"
            )
            if viewModel.detailComments.isEmpty && !viewModel.isLoadingDetail {
                Text("No comments yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                // Show last 3 comments
                ForEach(viewModel.detailComments.suffix(3)) { comment in
                    commentRow(comment)
                }
                if viewModel.detailComments.count > 3 {
                    Text("\(viewModel.detailComments.count - 3) earlier comments not shown.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func commentRow(_ comment: JiraComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.authorName)
                    .font(.caption.bold())
                Spacer()
                Text(comment.created.prefix(16).replacingOccurrences(of: "T", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(comment.bodyText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(borderColor: .secondary)
    }

    private func commentInputBar(_ item: TodoItem) -> some View {
        VStack(spacing: 6) {
            if let feedback = viewModel.transitionFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                TextField("Post a comment…", text: $viewModel.commentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                    .onSubmit {
                        let trimmed = viewModel.commentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            Task { await viewModel.postComment(appState: appState) }
                        }
                    }
                if viewModel.isPostingComment {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Button {
                        Task { await viewModel.postComment(appState: appState) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                viewModel.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary : Color.accentColor
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Detail sidebar (transitions + metadata)

    private func detailSidebar(_ item: TodoItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status transitions
                transitionsSection(item)

                // Metadata
                metadataSection(item)
            }
            .padding(DesignTokens.cardPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func transitionsSection(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderLabel(title: "Move To", icon: "arrow.triangle.2.circlepath")

            if viewModel.isTransitioning {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Transitioning…").font(.caption).foregroundStyle(.secondary)
                }
            } else if viewModel.detailTransitions.isEmpty && !viewModel.isLoadingDetail {
                Text("No transitions available.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.detailTransitions) { transition in
                        Button {
                            Task { await viewModel.applyTransition(transition, appState: appState) }
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

            if let err = viewModel.detailError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderLabel(title: "Details", icon: "info.circle")
            metaRow("Type", value: item.issueType)
            metaRow("Assignee", value: item.assignee)
            if let detail = viewModel.detailIssue,
               let reporter = (detail.raw["fields"] as? [String: Any])
                   .flatMap({ ($0["reporter"] as? [String: Any])?["displayName"] as? String }) {
                metaRow("Reporter", value: reporter)
            }
            metaRow("Priority", value: item.priority)
            if let sprint = item.sprint {
                metaRow("Sprint", value: sprint.name)
            }
            if let due = item.dueDate {
                let isOverdue = due < Date()
                HStack {
                    Text("Due").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Text(due, format: .dateTime.month().day().year())
                        .font(.caption.bold())
                        .foregroundStyle(isOverdue ? .red : .primary)
                }
            }
            if let updated = item.updated {
                metaRow("Updated", value: updated.formatted(.relative(presentation: .named)))
            }
            if !item.labels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Labels").font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 4) {
                        ForEach(item.labels, id: \.self) { label in
                            CompactBadge(text: label, color: .secondary)
                        }
                    }
                }
            }
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty / Error states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if appState.isJiraConfigured {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: DesignTokens.emptyIconSize))
                    .foregroundStyle(.green)
                Text("No tickets assigned to you — all clear!")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Click Refresh to check again")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "ticket")
                    .font(.system(size: DesignTokens.emptyIconSize))
                    .foregroundStyle(.secondary)
                Text("Configure Jira in Settings to see your tickets")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    appState.showSettings = true
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DesignTokens.emptyIconSize))
                .foregroundStyle(.red)
            Text("Failed to load tickets")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: 500)
            Button("Retry") {
                Task { await viewModel.refresh(appState: appState) }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func colorFor(_ cat: TodoCategory) -> Color {
        switch cat {
        case .overdue: return .red
        case .inProgress: return .blue
        case .sprintToDo: return .orange
        case .unplanned: return .gray
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "highest": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .blue
        case "lowest": return .gray
        default: return .secondary
        }
    }

    private func statusColor(_ categoryName: String) -> Color {
        switch categoryName {
        case "In Progress": return .blue
        case "To Do": return .orange
        case "Done": return .green
        default: return .secondary
        }
    }

    private func transitionColor(_ category: String) -> Color {
        switch category {
        case "In Progress": return .blue
        case "Done": return .green
        default: return .orange
        }
    }

    /// Extract description plain text from raw Jira issue JSON.
    private func extractDescriptionText(from raw: [String: Any]) -> String {
        guard let fields = raw["fields"] as? [String: Any],
              let description = fields["description"] else { return "" }

        // ADF description: try to extract text nodes
        if let descDict = description as? [String: Any] {
            return extractADFText(descDict)
        }
        // Fallback: string description
        if let descStr = description as? String { return descStr }
        return ""
    }

    private func extractADFText(_ node: [String: Any]) -> String {
        if node["type"] as? String == "text" {
            return node["text"] as? String ?? ""
        }
        guard let children = node["content"] as? [[String: Any]] else { return "" }
        let nodeType = node["type"] as? String ?? ""
        let parts = children.compactMap { child -> String? in
            let t = extractADFText(child)
            return t.isEmpty ? nil : t
        }
        if nodeType == "paragraph" {
            return parts.joined(separator: " ") + "\n"
        }
        if nodeType == "heading" {
            let level = node["attrs"] as? [String: Any]
            let l = level?["level"] as? Int ?? 2
            let prefix = String(repeating: "#", count: l) + " "
            return prefix + parts.joined(separator: " ") + "\n"
        }
        if nodeType == "bulletList" || nodeType == "orderedList" {
            return parts.joined(separator: "")
        }
        if nodeType == "listItem" {
            return "- " + parts.joined(separator: " ") + "\n"
        }
        if nodeType == "codeBlock" {
            return "```\n" + parts.joined(separator: "\n") + "\n```\n"
        }
        if nodeType == "blockquote" {
            return parts.map { "> " + $0 }.joined(separator: "\n") + "\n"
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - FlowLayout for wrapping chips

/// Simple wrapping layout for transition buttons and label chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > containerWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: containerWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

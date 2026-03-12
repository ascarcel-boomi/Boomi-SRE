import SwiftUI

/// Full ticket detail view with actions — shown when clicking a ticket key.
struct TicketDetailView: View {
    let ticketKey: String
    let onDismiss: () -> Void

    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = TicketDetailViewModel()
    @State private var commentText = ""
    @State private var isAddingComment = false
    @State private var showAssignSearch = false
    @State private var assignSearchQuery = ""
    @State private var assignSearchResults: [JiraAssignableUser] = []

    private let jiraService = JiraService()

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { onDismiss() } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.plain)

                Spacer()

                if let issue = viewModel.issue {
                    Link(destination: URL(string: "\(appState.jiraBaseURL)/browse/\(ticketKey)")!) {
                        Label("Open in Jira", systemImage: "safari")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            if viewModel.isLoading && viewModel.issue == nil {
                VStack { Spacer(); ProgressView("Loading \(ticketKey)..."); Spacer() }
            } else if let issue = viewModel.issue {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ticketHeader(issue)
                        actionBar(issue)
                        messageBanner
                        descriptionSection
                        commentsSection
                        addCommentSection
                    }
                    .padding(20)
                }
            } else if let msg = viewModel.actionMessage {
                VStack { Spacer(); Text(msg).foregroundStyle(.red).textSelection(.enabled); Spacer() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            Task { await viewModel.load(key: ticketKey, appState: appState) }
        }
    }

    // MARK: - Header

    private func ticketHeader(_ issue: JiraIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(issue.key)
                            .font(.title2.bold().monospaced())
                        Text(issue.fields.issuetype?.name ?? "")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                    }
                    Text(issue.fields.summary ?? "")
                        .font(.title3)
                }
                Spacer()
            }

            // Metadata row
            HStack(spacing: 16) {
                metadataChip(label: "Status", value: issue.fields.status?.name ?? "?",
                             color: statusColor(issue.fields.status?.statusCategory?.name ?? ""))
                metadataChip(label: "Priority", value: issue.fields.priority?.name ?? "?",
                             color: priorityColor(issue.fields.priority?.name ?? ""))
                metadataChip(label: "Assignee", value: viewModel.assigneeName, color: .secondary)

                if let due = issue.fields.duedate {
                    metadataChip(label: "Due", value: due, color: .secondary)
                }

                if let labels = issue.fields.labels, !labels.isEmpty {
                    metadataChip(label: "Labels", value: labels.joined(separator: ", "), color: .secondary)
                }
            }
        }
    }

    private func metadataChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout.bold()).foregroundStyle(color)
        }
    }

    // MARK: - Actions

    private func actionBar(_ issue: JiraIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 8) {
                // Status transitions
                ForEach(viewModel.transitions) { t in
                    Button {
                        Task { await viewModel.transition(to: t, key: ticketKey, appState: appState) }
                    } label: {
                        Label(t.name, systemImage: transitionIcon(t))
                    }
                    .buttonStyle(.bordered)
                    .tint(transitionColor(t))
                }

                Divider().frame(height: 24)

                // Assign to me
                Button {
                    Task { await viewModel.assignToMe(key: ticketKey, appState: appState) }
                } label: {
                    Label("Assign to Me", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)

                // Assign to someone else
                Button {
                    showAssignSearch.toggle()
                } label: {
                    Label("Assign...", systemImage: "person.2")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showAssignSearch) {
                    assignSearchPopover
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private var assignSearchPopover: some View {
        VStack(spacing: 8) {
            TextField("Search users...", text: $assignSearchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { searchUsers() }

            if assignSearchResults.isEmpty {
                Text("Type a name and press Enter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(assignSearchResults) { user in
                    Button {
                        Task {
                            await viewModel.assign(accountId: user.accountId, key: ticketKey, appState: appState)
                            showAssignSearch = false
                        }
                    } label: {
                        Text(user.displayName)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }

    private func searchUsers() {
        let query = assignSearchQuery
        Task {
            assignSearchResults = (try? await jiraService.searchUsers(
                baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                apiToken: appState.jiraAPIToken, query: query)) ?? []
        }
    }

    // MARK: - Message

    @ViewBuilder
    private var messageBanner: some View {
        if let msg = viewModel.actionMessage {
            HStack {
                Image(systemName: viewModel.actionIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                Text(msg)
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(viewModel.actionIsError ? .red : .green)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill((viewModel.actionIsError ? Color.red : Color.green).opacity(0.1)))
        }
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionSection: some View {
        if !viewModel.description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                Text(viewModel.description)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comments (\(viewModel.comments.count))")
                .font(.headline)

            if viewModel.comments.isEmpty {
                Text("No comments yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(viewModel.comments.enumerated()), id: \.offset) { _, comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.author).font(.callout.bold())
                            Spacer()
                            Text(comment.created).font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(comment.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    // MARK: - Add Comment

    private var addCommentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Comment")
                .font(.headline)

            TextEditor(text: $commentText)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 150)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button {
                    guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    isAddingComment = true
                    let text = commentText
                    commentText = ""
                    Task {
                        await viewModel.addComment(text: text, key: ticketKey, appState: appState)
                        isAddingComment = false
                    }
                } label: {
                    Label("Post Comment", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingComment)

                if isAddingComment {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    // MARK: - Helpers

    private func transitionIcon(_ t: JiraTransition) -> String {
        switch t.toCategory {
        case "In Progress": return "play.circle"
        case "Done": return "checkmark.circle"
        case "To Do": return "circle"
        default: return "arrow.right.circle"
        }
    }

    private func transitionColor(_ t: JiraTransition) -> Color {
        switch t.toCategory {
        case "In Progress": return .blue
        case "Done": return .green
        case "To Do": return .orange
        default: return .secondary
        }
    }

    private func statusColor(_ name: String) -> Color {
        switch name {
        case "In Progress": return .blue
        case "To Do": return .orange
        case "Done": return .green
        default: return .secondary
        }
    }

    private func priorityColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "highest": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .blue
        case "lowest": return .gray
        default: return .secondary
        }
    }
}

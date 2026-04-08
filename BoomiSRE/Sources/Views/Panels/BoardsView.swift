import SwiftUI

struct BoardsView: View {
    @EnvironmentObject var appState: AppState
    @State private var viewModel = BoardsViewModel()
    @State private var myTicketsOnly = true
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        HSplitView {
            // Left: project/board tree
            VStack(spacing: 0) {
                HStack {
                    Text("Boards")
                        .font(.headline)
                    Spacer()
                    if viewModel.isLoadingProjects {
                        ProgressView().scaleEffect(0.7)
                    }
                    Button {
                        Task { await viewModel.loadProjects(appState: appState) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh boards")
                }
                .padding(12)

                Divider()

                if viewModel.projects.isEmpty && !viewModel.isLoadingProjects {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "rectangle.on.rectangle.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No boards found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Boards are loaded from your recent Jira projects")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    List(selection: $viewModel.selectedBoard) {
                        ForEach(viewModel.projects) { project in
                            Section(isExpanded: sectionBinding(project.key)) {
                                ForEach(Array(project.boards.enumerated()), id: \.element.id) { idx, board in
                                    HStack(spacing: 8) {
                                        Image(systemName: board.type == "scrum" ? "arrow.triangle.2.circlepath" : "rectangle.split.3x3")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(board.name)
                                                .font(.callout)
                                            Text(board.type.capitalized)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .tag(board)
                                    .listRowBackground(idx.isMultiple(of: 2)
                                        ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                        : Color.clear)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "rectangle.on.rectangle")
                                        .foregroundStyle(.secondary)
                                    Text("\(project.key): \(project.name)")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text("\(project.boards.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleSection(project.key) }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 350)
            .splitGrip()

            // Right: board content
            VStack(spacing: 0) {
                if let board = viewModel.selectedBoard {
                    // Board header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Image(systemName: board.type == "scrum" ? "arrow.triangle.2.circlepath" : "rectangle.split.3x3")
                                    .foregroundStyle(board.type == "scrum" ? .blue : .orange)
                                Text(board.name)
                                    .font(.title2.bold())
                            }
                            Text("\(board.projectKey) \u{2022} \(board.type.capitalized) board")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Toggle("My tickets only", isOn: $myTicketsOnly)
                            .toggleStyle(.switch)

                        // AI buttons
                        Menu {
                            Button {
                                Task { await viewModel.analyzeSprintHealth(appState: appState) }
                            } label: {
                                Label("Sprint Health Check", systemImage: "heart.text.square")
                            }
                            Button {
                                Task { await viewModel.generateSprintReport(appState: appState) }
                            } label: {
                                Label("Generate Sprint Report", systemImage: "doc.text")
                            }
                            if viewModel.sprintAnalysis != nil {
                                Divider()
                                Button(role: .destructive) {
                                    viewModel.sprintAnalysis = nil
                                } label: {
                                    Label("Clear Analysis", systemImage: "xmark.circle")
                                }
                            }
                        } label: {
                            if viewModel.isAnalyzingBoard {
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Label("AI", systemImage: "sparkles")
                            }
                        }
                        .disabled(viewModel.boardIssues.isEmpty || viewModel.isAnalyzingBoard)

                        if viewModel.isLoadingBoard {
                            ProgressView().scaleEffect(0.8)
                        }

                        Text("\(viewModel.boardIssues.count) issues")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Link(destination: URL(string: board.boardURL + (myTicketsOnly ? "?assignee=\(viewModel.myAccountId)" : ""))!) {
                            Label("Open in Jira", systemImage: "safari")
                        }
                    }
                    .padding(16)

                    Divider()

                    // Issues
                    if viewModel.boardIssues.isEmpty && !viewModel.isLoadingBoard {
                        VStack(spacing: 8) {
                            Spacer()
                            Text("No issues found")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        // Chart summary + AI analysis
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                boardCharts

                                // AI analysis panel
                                if let err = viewModel.boardAIError {
                                    Label(err, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.red)
                                        .padding(.horizontal, 4)
                                }
                                if let analysis = viewModel.sprintAnalysis {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label("AI Analysis", systemImage: "sparkles")
                                                .font(.headline).foregroundStyle(.purple)
                                            Spacer()
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(analysis, forType: .string)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.plain).foregroundStyle(.secondary)
                                            .help("Copy to clipboard")
                                            .accessibilityLabel("Copy analysis to clipboard")
                                        }
                                        InlineMarkdownText(text: analysis)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.2)))
                                }

                                JiraIssueTableView(issues: viewModel.boardIssues, baseURL: appState.jiraBaseURL)
                            }
                            .padding(16)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Select a board from the left")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if viewModel.projects.isEmpty {
                Task { await viewModel.loadProjects(appState: appState) }
            }
        }
        .onChange(of: viewModel.selectedBoard) {
            if viewModel.selectedBoard != nil {
                Task { await viewModel.loadBoard(viewModel.selectedBoard!, myTicketsOnly: myTicketsOnly, appState: appState) }
            }
        }
        .onChange(of: myTicketsOnly) {
            if let board = viewModel.selectedBoard {
                Task { await viewModel.loadBoard(board, myTicketsOnly: myTicketsOnly, appState: appState) }
            }
        }
    }

    // MARK: - Helpers

    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(key) },
            set: { if $0 { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
        )
    }

    private func toggleSection(_ key: String) {
        withAnimation { if collapsedSections.contains(key) { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
    }

    // MARK: - Charts

    private var boardCharts: some View {
        HStack(spacing: 16) {
            // Status distribution
            let byStatus = Dictionary(grouping: viewModel.boardIssues, by: { $0.fields.status?.name ?? "?" })
            if byStatus.count > 1 {
                let rows = byStatus.map { ResultRow(label: $0.key, value: Double($0.value.count)) }
                    .sorted { $0.value > $1.value }
                VStack(alignment: .leading) {
                    Text("By Status").font(.headline)
                    ReportChartView(section: ResultSection(title: "Status", rows: rows, chartHint: .pie))
                        .frame(minHeight: 200)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            }

            // Priority distribution
            let byPriority = Dictionary(grouping: viewModel.boardIssues, by: { $0.fields.priority?.name ?? "?" })
            if byPriority.count > 1 {
                let rows = byPriority.map { ResultRow(label: $0.key, value: Double($0.value.count)) }
                    .sorted { $0.value > $1.value }
                VStack(alignment: .leading) {
                    Text("By Priority").font(.headline)
                    ReportChartView(section: ResultSection(title: "Priority", rows: rows, chartHint: .bar))
                        .frame(minHeight: 200)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            }
        }
    }
}

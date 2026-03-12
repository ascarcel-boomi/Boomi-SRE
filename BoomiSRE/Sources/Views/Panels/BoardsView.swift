import SwiftUI

struct BoardsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = BoardsViewModel()
    @State private var myTicketsOnly = true

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
                            Section {
                                ForEach(project.boards) { board in
                                    HStack(spacing: 8) {
                                        Image(systemName: board.type == "scrum" ? "arrow.triangle.2.circlepath" : "rectangle.split.3x3")
                                            .foregroundStyle(board.type == "scrum" ? .blue : .orange)
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
                                }
                            } header: {
                                Text("\(project.key): \(project.name)")
                                    .font(.caption.bold())
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 350)

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
                        // Chart summary
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                boardCharts
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

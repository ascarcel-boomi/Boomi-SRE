import SwiftUI

struct SavedFiltersView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SavedFiltersViewModel()

    var body: some View {
        HSplitView {
            // Left: filter list
            VStack(spacing: 0) {
                HStack {
                    Text("Filters")
                        .font(.headline)
                    Spacer()
                    if viewModel.isLoadingFilters {
                        ProgressView().scaleEffect(0.7)
                    }
                    Button {
                        Task { await viewModel.loadFilters(appState: appState) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)

                Divider()

                if viewModel.filters.isEmpty && !viewModel.isLoadingFilters {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No favourite filters found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Star a filter in Jira to see it here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else {
                    List(viewModel.filters, selection: $viewModel.selectedFilter) { filter in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(filter.name)
                                .font(.body)
                            Text(filter.jql)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                        .tag(filter)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 350)

            // Right: results
            VStack(spacing: 0) {
                if let filter = viewModel.selectedFilter {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text(filter.name)
                                .font(.title2.bold())
                            Text(filter.jql)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        if viewModel.isLoadingResults {
                            ProgressView().scaleEffect(0.8)
                        }
                        if let result = viewModel.filterResults {
                            Text("\(result.issueCount) issues")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        // AI button
                        if viewModel.filterResults != nil {
                            Button {
                                Task { await viewModel.explainResults(appState: appState) }
                            } label: {
                                if viewModel.isAnalyzingFilter {
                                    Label("Analyzing…", systemImage: "sparkles")
                                } else {
                                    Label("Explain Results", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isAnalyzingFilter)
                        }
                    }
                    .padding(16)

                    Divider()

                    if let results = viewModel.filterResults {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // AI analysis panel
                                if let err = viewModel.filterAnalysisError {
                                    Label(err, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.red)
                                }
                                if let analysis = viewModel.filterAnalysis {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label("AI Insights", systemImage: "sparkles")
                                                .font(.headline).foregroundStyle(.purple)
                                            Spacer()
                                            Button { viewModel.filterAnalysis = nil } label: {
                                                Image(systemName: "xmark.circle")
                                            }
                                            .buttonStyle(.plain).foregroundStyle(.secondary)
                                        }
                                        Text(filterAnalysisAttributed(analysis))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.2)))
                                }

                                // Charts
                                if !viewModel.chartSections.isEmpty {
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                        ForEach(viewModel.chartSections) { section in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(section.title).font(.headline)
                                                ReportChartView(section: section)
                                                    .frame(minHeight: 200)
                                            }
                                            .padding()
                                            .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                                        }
                                    }
                                }

                                // Issue table
                                JiraIssueTableView(issues: results.issues, baseURL: appState.jiraBaseURL)
                            }
                            .padding(16)
                        }
                    } else if viewModel.error != nil {
                        VStack {
                            Spacer()
                            Text(viewModel.error ?? "")
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            Spacer()
                        }
                    } else {
                        Spacer()
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Select a filter from the left to view results")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if viewModel.filters.isEmpty {
                Task { await viewModel.loadFilters(appState: appState) }
            }
        }
        .onChange(of: viewModel.selectedFilter) {
            if let filter = viewModel.selectedFilter {
                viewModel.filterAnalysis = nil
                Task { await viewModel.runFilter(filter, appState: appState) }
            }
        }
    }

    private func filterAnalysisAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
             options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }
}

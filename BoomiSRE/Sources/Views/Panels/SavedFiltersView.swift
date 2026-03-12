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
                        if let total = viewModel.filterResults?.total {
                            Text("\(total) issues")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)

                    Divider()

                    if let results = viewModel.filterResults {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
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
                Task { await viewModel.runFilter(filter, appState: appState) }
            }
        }
    }
}

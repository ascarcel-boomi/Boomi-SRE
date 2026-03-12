import SwiftUI

struct TodoDashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = TodoDashboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My TODO")
                        .font(.title2.bold())
                    if let last = viewModel.lastRefreshed {
                        Text("Last refreshed: \(last, format: .dateTime)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Button {
                    Task { await viewModel.refresh(appState: appState) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if let error = viewModel.error {
                errorBanner(error)
            } else if viewModel.items.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Summary cards
                        summaryCards

                        // Charts
                        if !viewModel.items.isEmpty {
                            chartRow
                        }

                        // Issue list by category
                        ForEach(viewModel.groupedItems, id: \.0) { (category, items) in
                            categorySection(category, items: items)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if viewModel.items.isEmpty {
                Task { await viewModel.refresh(appState: appState) }
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            ForEach(TodoCategory.allCases) { cat in
                let count = viewModel.categoryCounts[cat] ?? 0
                statCard(cat.rawValue, count: count, color: colorFor(cat))
            }
        }
    }

    private func statCard(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? color : .secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3)))
    }

    // MARK: - Charts

    private var chartRow: some View {
        HStack(spacing: 16) {
            ForEach(viewModel.chartSections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                    ReportChartView(section: section)
                        .frame(minHeight: 200)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            }
        }
    }

    // MARK: - Category sections

    private func categorySection(_ category: TodoCategory, items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(colorFor(category)).frame(width: 10, height: 10)
                Text(category.rawValue)
                    .font(.headline)
                Text("(\(items.count))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(items) { item in
                    todoItemRow(item)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func todoItemRow(_ item: TodoItem) -> some View {
        HStack(spacing: 10) {
            // Priority indicator
            Circle()
                .fill(priorityColor(item.priority))
                .frame(width: 8, height: 8)

            // Issue key (clickable link)
            Link(item.key, destination: item.url)
                .font(.body.monospaced().bold())
                .frame(width: 120, alignment: .leading)

            // Summary
            Text(item.summary)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Sprint name
            if let sprint = item.sprint {
                Text(sprint.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.blue.opacity(0.15)))
            }

            // Status badge
            Text(item.status)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(statusColor(item.statusCategoryName).opacity(0.15)))
                .foregroundStyle(statusColor(item.statusCategoryName))

            // Due date
            if let due = item.dueDate {
                let isOverdue = due < Date()
                Text(due, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }

            // Priority label
            Text(item.priority)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No open tickets assigned to you")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click Refresh to check again")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Failed to load TODO list")
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
}

import SwiftUI
import Charts

struct VelocityView: View {
    @State private var vm = VelocityViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if vm.isLoading {
                    ProgressView("Loading sprint velocity…")
                        .frame(maxWidth: .infinity).padding()
                } else if let err = vm.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.callout)
                        .padding()
                } else if vm.sprints.isEmpty {
                    Text("No sprint data found. Make sure Jira is configured and the project has Scrum boards.")
                        .font(.callout).foregroundStyle(.secondary).padding()
                } else {
                    velocityChart
                    sprintTable
                }
            }
            .padding(20)
        }
        .task { await vm.loadVelocity(appState: appState) }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sprint Velocity").font(.title2.bold())
                if !vm.selectedBoardName.isEmpty {
                    Text("Board: \(vm.selectedBoardName)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await vm.loadVelocity(appState: appState) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(vm.isLoading)
        }
    }

    // MARK: Chart

    private var velocityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Committed vs Completed (Story Points)").font(.headline)
            Chart {
                ForEach(vm.sprints) { sprint in
                    BarMark(
                        x: .value("Sprint", sprintShortName(sprint.name)),
                        y: .value("Points", sprint.committed)
                    )
                    .foregroundStyle(Color.blue.opacity(0.4))
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", sprint.committed))
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    BarMark(
                        x: .value("Sprint", sprintShortName(sprint.name)),
                        y: .value("Points", sprint.completed)
                    )
                    .foregroundStyle(Color.green.opacity(0.75))
                }
            }
            .chartLegend(position: .topTrailing) {
                HStack(spacing: 12) {
                    legendItem("Committed", color: .blue.opacity(0.4))
                    legendItem("Completed", color: .green.opacity(0.75))
                }
            }
            .frame(height: 220)
            .padding(.top, 4)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12)
            Text(label).font(.caption2)
        }
    }

    // MARK: Table

    private var sprintTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sprint Detail").font(.headline)
            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("Sprint").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Committed").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                    Text("Completed").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                    Text("Rate").font(.caption.bold()).frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))

                Divider()

                ForEach(vm.sprints) { sprint in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sprint.name).font(.callout).lineLimit(1)
                            if let start = sprint.startDate {
                                Text(formatSprintDate(start)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.0f", sprint.committed))
                            .font(.callout).frame(width: 80, alignment: .trailing)

                        Text(String(format: "%.0f", sprint.completed))
                            .font(.callout).frame(width: 80, alignment: .trailing)
                            .foregroundStyle(sprint.completionRate >= 0.8 ? .green : sprint.completionRate >= 0.5 ? .yellow : .red)

                        Text(String(format: "%.0f%%", sprint.completionRate * 100))
                            .font(.callout.bold()).frame(width: 60, alignment: .trailing)
                            .foregroundStyle(sprint.completionRate >= 0.8 ? .green : sprint.completionRate >= 0.5 ? .yellow : .red)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)

                    Divider()
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    // MARK: Helpers

    private func sprintShortName(_ name: String) -> String {
        // Try to extract sprint number or short label
        let parts = name.components(separatedBy: " ")
        return parts.last ?? name
    }

    private func formatSprintDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return df.string(from: date)
        }
        return String(iso.prefix(10))
    }
}

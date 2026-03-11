import SwiftUI

/// Displays report data as a native macOS table.
struct ReportTableView: View {
    let rows: [ResultRow]

    private var hasValues: Bool {
        rows.contains { $0.value > 0 }
    }

    private var hasGroups: Bool {
        rows.contains { !$0.group.isEmpty }
    }

    private var hasDetails: Bool {
        rows.contains { !$0.detail.isEmpty }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Label") { row in
                Text(row.label)
                    .font(.body)
            }
            .width(min: 150, ideal: 250)

            if hasValues {
                TableColumn("Value") { row in
                    Text(formatValue(row.value))
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 120)
            }

            if hasGroups {
                TableColumn("Group") { row in
                    if !row.group.isEmpty {
                        Text(row.group)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                    }
                }
                .width(min: 60, ideal: 100)
            }

            if hasDetails {
                TableColumn("Details") { row in
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 100, ideal: 200)
            }
        }
        .frame(minHeight: CGFloat(min(rows.count * 32 + 40, 600)))
    }

    private func formatValue(_ v: Double) -> String {
        if v == 0 { return "-" }
        if v >= 1000 {
            return String(format: "%,.0f", v)
        }
        if v == v.rounded() {
            return String(format: "%.0f", v)
        }
        return String(format: "%.2f", v)
    }
}

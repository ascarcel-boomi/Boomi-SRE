import SwiftUI

/// Individual SLO status card with traffic-light indicator and error budget gauge.
struct SLOCardView: View {
    let status: SLOStatus
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: status.health.icon)
                    .foregroundStyle(status.health.color)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.definition.name)
                        .font(.callout.bold())
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: status.definition.category.icon)
                            .font(.caption2)
                        Text(status.definition.category.rawValue)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // SLI value + target
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current SLI")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let sli = status.currentSLI {
                        Text(formatPercent(sli))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(status.health.color)
                    } else {
                        Text(status.queryError ?? "No data")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(formatPercent(status.definition.target))
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(status.definition.windowDays)d")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Error budget gauge
            if status.currentSLI != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Error Budget")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", status.errorBudgetRemainingPct))% remaining")
                            .font(.caption2.bold())
                            .foregroundStyle(budgetColor)
                    }
                    ProgressView(value: max(0, min(100, status.errorBudgetRemainingPct)), total: 100)
                        .tint(budgetColor)
                        .scaleEffect(x: 1, y: 1.5)

                    if status.burnRate > 1.5 {
                        Label("Burn rate \(String(format: "%.1f", status.burnRate))x — budget depleting faster than expected",
                              systemImage: "flame")
                            .font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(status.health.color.opacity(0.3), lineWidth: 1)
        )
    }

    private var budgetColor: Color {
        if status.errorBudgetRemainingPct < 10 { return .red }
        if status.errorBudgetRemainingPct < 50 { return .orange }
        return .green
    }

    private func formatPercent(_ value: Double) -> String {
        if value >= 0.9999 { return String(format: "%.4f%%", value * 100) }
        if value >= 0.999 { return String(format: "%.3f%%", value * 100) }
        if value >= 0.99 { return String(format: "%.2f%%", value * 100) }
        return String(format: "%.1f%%", value * 100)
    }
}

import SwiftUI
import Charts

struct ProductivityView: View {
    @ObservedObject var tracker = ProductivityTracker.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Productivity Analytics").font(.title2.bold())

                HStack(spacing: 16) {
                    metricCard("Today", value: tracker.timeSavedTodayFormatted,
                              subtitle: "\(tracker.actionsToday) actions", color: .green)
                    metricCard("This Week", value: formatMinutes(tracker.minutesSavedThisWeek),
                              subtitle: "", color: .blue)
                    metricCard("This Month", value: formatMinutes(tracker.minutesSavedThisMonth),
                              subtitle: "", color: .purple)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 7 Days").font(.headline)
                    Chart(tracker.weeklyTrend, id: \.date) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes Saved", point.minutes)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .frame(height: 150)
                    .chartYAxisLabel("Minutes")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today by Category").font(.headline)
                    ForEach(tracker.todayByCategory, id: \.category) { cat in
                        HStack {
                            Text(cat.category).font(.callout)
                            Spacer()
                            Text("\(cat.count) actions").font(.caption).foregroundStyle(.secondary)
                            Text(formatMinutes(cat.minutes)).font(.callout.bold())
                        }
                        .padding(.vertical, 4)
                    }
                    if tracker.todayByCategory.isEmpty {
                        Text("No actions recorded today yet. Start using the app!")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity").font(.headline)
                    ForEach(Array(tracker.events.suffix(20).reversed())) { event in
                        HStack(spacing: 8) {
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospaced()).foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .trailing)
                            Text(event.detail).font(.caption).lineLimit(1)
                            Spacer()
                            Text("+\(Int(event.estimatedMinutesSaved))m")
                                .font(.caption.bold()).foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func metricCard(_ title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(color)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.08)))
    }

    private func formatMinutes(_ mins: Double) -> String {
        if mins < 60 { return "\(Int(mins)) min" }
        let hours = mins / 60
        if hours < 10 { return String(format: "%.1f hrs", hours) }
        return "\(Int(hours)) hrs"
    }
}

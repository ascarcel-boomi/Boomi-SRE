import SwiftUI
import Charts

// MARK: - Achievement (data model only — NOT a View)

struct Achievement: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let earned: Bool
}

// MARK: - TeamLeaderboard

struct TeamLeaderboard: View {
    @ObservedObject var tracker = ProductivityTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team Leaderboard — Today").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                Text("Your Team").font(.callout.bold())
                Spacer()
                Text(tracker.timeSavedTodayFormatted).font(.callout.bold()).foregroundStyle(.green)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.08)))
        }
    }
}

// MARK: - ProductivityView

struct ProductivityView: View {
    @ObservedObject var tracker = ProductivityTracker.shared

    private let achievements: [Achievement] = [
        Achievement(id: "first-ack", name: "First ACK",
                    description: "Acknowledged your first alert via the app",
                    icon: "checkmark.circle.fill", earned: false),
        Achievement(id: "ai-ninja", name: "AI Ninja",
                    description: "Used AI features 50 times",
                    icon: "sparkles", earned: false),
        Achievement(id: "velocity-master", name: "Velocity Master",
                    description: "Completed 100% of sprint story points",
                    icon: "chart.bar.fill", earned: false),
        Achievement(id: "cross-product-hero", name: "Cross-Product Hero",
                    description: "Covered on-call for a product that isn't your primary",
                    icon: "person.badge.shield.checkmark", earned: false),
    ]

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

                TeamLeaderboard()
                achievementsSection
            }
            .padding(24)
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Achievements").font(.headline)
            HStack(spacing: 12) {
                ForEach(achievements) { a in
                    VStack(spacing: 4) {
                        Image(systemName: a.icon)
                            .font(.title2)
                            .foregroundStyle(a.earned ? Color.yellow : Color.secondary.opacity(0.4))
                        Text(a.name).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(width: 64)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(a.earned ? Color.yellow.opacity(0.1) : Color.secondary.opacity(0.05)))
                }
            }
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

// MARK: - ProductivityTabView

/// Wrapper that adds BPOP and Velocity sub-tabs to the existing Productivity analytics.
struct ProductivityTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Analytics").tag(0)
                Text("BPOP").tag(1)
                Text("Velocity").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: ProductivityView()
                case 1: BPOPDashboardView()
                case 2: VelocityView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

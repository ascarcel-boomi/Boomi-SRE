import SwiftUI
import Charts

/// Renders the best chart type for a given ResultSection.
struct ReportChartView: View {
    let section: ResultSection
    var onSelect: ((String) -> Void)? = nil
    var showLegend: Bool = true

    @State private var selectedLabel: String? = nil

    /// Only rows with a positive value are chartable.
    private var chartRows: [ResultRow] {
        section.rows.filter { $0.value > 0 }
    }

    private var hasGroups: Bool {
        chartRows.contains { !$0.group.isEmpty }
    }

    var body: some View {
        if chartRows.isEmpty {
            Text("No numeric data to chart")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            chartForType(section.chartHint)
                .chartLegend(showLegend ? .visible : .hidden)
                .padding()
        }
    }

    @ViewBuilder
    private func chartForType(_ type: ChartType) -> some View {
        switch type {
        case .bar:
            barChart
        case .horizontalBar:
            horizontalBarChart
        case .line:
            lineChart
        case .pie:
            pieChart
        case .stackedBar:
            stackedBarChart
        case .table:
            Text("Table view — switch to Table mode")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bar Chart

    private var barChart: some View {
        Chart(chartRows) { row in
            if hasGroups {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(by: .value("Group", row.group))
                .position(by: .value("Group", row.group))
                .opacity(opacity(for: row.label))
            } else {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
                .opacity(opacity(for: row.label))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotOrigin = geo[plotFrame].origin
                        let plotWidth = geo[plotFrame].width
                        var seen = Set<String>()
                        let uniqueLabels = chartRows.map(\.label).filter { seen.insert($0).inserted }
                        let barWidth = plotWidth / CGFloat(uniqueLabels.count)
                        let relativeX = location.x - plotOrigin.x
                        let index = Int(relativeX / barWidth)
                        if index >= 0 && index < uniqueLabels.count {
                            handleTap(uniqueLabels[index])
                        }
                    }
            }
        }
    }

    // MARK: - Horizontal Bar Chart

    private var horizontalBarChart: some View {
        Chart(chartRows) { row in
            BarMark(
                x: .value("Value", row.value),
                y: .value("Category", row.label)
            )
            .foregroundStyle(.blue.gradient)
            .cornerRadius(4)
            .annotation(position: .trailing) {
                Text(formatCompact(row.value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption)
            }
        }
    }

    // MARK: - Line Chart

    private var lineChart: some View {
        Chart(chartRows) { row in
            if hasGroups {
                LineMark(
                    x: .value("Period", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(by: .value("Group", row.group))
                .symbol(by: .value("Group", row.group))

                PointMark(
                    x: .value("Period", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(by: .value("Group", row.group))
            } else {
                LineMark(
                    x: .value("Period", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Period", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue.opacity(0.1))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Period", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Pie Chart

    private var pieChart: some View {
        Chart(chartRows) { row in
            SectorMark(
                angle: .value("Value", row.value),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value("Category", row.label))
            .cornerRadius(4)
            .opacity(opacity(for: row.label))
            .annotation(position: .overlay) {
                let pct = row.value / chartRows.reduce(0) { $0 + $1.value } * 100
                if pct > 5 {
                    Text(String(format: "%.0f%%", pct))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotRect = geo[plotFrame]
                        let center = CGPoint(x: plotRect.midX, y: plotRect.midY)
                        let dx = location.x - center.x
                        let dy = location.y - center.y
                        let distance = sqrt(dx * dx + dy * dy)
                        let outerRadius = min(plotRect.width, plotRect.height) / 2
                        let innerRadius = outerRadius * 0.5
                        guard distance >= innerRadius && distance <= outerRadius else { return }

                        // atan2 gives angle from 3 o'clock, y-down = clockwise
                        // Swift Charts SectorMark starts at 12 o'clock, clockwise
                        // Convert: chart_angle = atan2_angle + 90
                        var angle = atan2(dy, dx) * 180 / .pi + 90
                        if angle < 0 { angle += 360 }

                        let total = chartRows.reduce(0.0) { $0 + $1.value }
                        var cumulative = 0.0
                        for row in chartRows {
                            let sliceAngle = row.value / total * 360
                            if angle >= cumulative && angle < cumulative + sliceAngle {
                                handleTap(row.label)
                                return
                            }
                            cumulative += sliceAngle
                        }
                    }
            }
        }
    }

    // MARK: - Stacked Bar Chart

    private var stackedBarChart: some View {
        Chart(chartRows) { row in
            if hasGroups {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(by: .value("Group", row.group))
                .opacity(opacity(for: row.label))
            } else {
                BarMark(
                    x: .value("Category", row.label),
                    y: .value("Value", row.value)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
                .opacity(opacity(for: row.label))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plotOrigin = geo[plotFrame].origin
                        let plotWidth = geo[plotFrame].width
                        var seen = Set<String>()
                        let uniqueLabels = chartRows.map(\.label).filter { seen.insert($0).inserted }
                        let barWidth = plotWidth / CGFloat(uniqueLabels.count)
                        let relativeX = location.x - plotOrigin.x
                        let index = Int(relativeX / barWidth)
                        if index >= 0 && index < uniqueLabels.count {
                            handleTap(uniqueLabels[index])
                        }
                    }
            }
        }
    }

    // MARK: - Helpers

    private func opacity(for label: String) -> Double {
        guard let selected = selectedLabel else { return 1.0 }
        return label == selected ? 1.0 : 0.3
    }

    private func handleTap(_ label: String) {
        if selectedLabel == label {
            selectedLabel = nil
            onSelect?("")
        } else {
            selectedLabel = label
            onSelect?(label)
        }
    }

    private func formatCompact(_ v: Double) -> String {
        if v >= 1_000_000 {
            return String(format: "$%.1fM", v / 1_000_000)
        } else if v >= 1_000 {
            return String(format: "$%.1fK", v / 1_000)
        }
        return String(format: "%.0f", v)
    }
}

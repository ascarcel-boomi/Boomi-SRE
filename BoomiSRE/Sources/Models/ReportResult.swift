import Foundation

/// Parsed result from a Python script, ready for table and chart rendering.
struct ReportResult: Identifiable {
    let id = UUID()
    let title: String
    let generatedAt: Date
    let sections: [ResultSection]
    let rawOutput: String
}

/// A logical section within a report (e.g., "Cost by Service", "Monthly Trend").
struct ResultSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [ResultRow]
    let chartHint: ChartType
}

/// A single data row — label + numeric value + optional grouping/year.
struct ResultRow: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let group: String  // for grouped/stacked charts (e.g., year "2024" vs "2025")
    let detail: String // extra text for table view

    init(label: String, value: Double, group: String = "", detail: String = "") {
        self.label = label
        self.value = value
        self.group = group
        self.detail = detail
    }
}

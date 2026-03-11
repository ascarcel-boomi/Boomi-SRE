import Foundation

/// A report that can be selected from the sidebar.
struct ReportItem: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let section: ReportSection
    let scriptName: String
    let csvKeys: [String]       // empty = runs in real-time; non-empty = needs pre-exported CSVs
    let chartType: ChartType

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ReportItem, rhs: ReportItem) -> Bool { lhs.id == rhs.id }

    /// True if this report can run without pre-exported CSV files.
    var isRealTime: Bool { csvKeys.isEmpty }
}

enum ReportSection: String, CaseIterable {
    case awsCost = "AWS Cost Reports"
    case jiraAnalytics = "Jira / SRE Analytics"

    var icon: String {
        switch self {
        case .awsCost: return "dollarsign.circle"
        case .jiraAnalytics: return "chart.bar.xaxis"
        }
    }
}

enum ChartType {
    case bar
    case line
    case pie
    case stackedBar
    case horizontalBar
    case table
}

/// All available reports organized by section.
///
/// Only reports that can run in real-time (no pre-exported CSVs) are included.
/// CSV-dependent Jira analytics reports will be added in Phase 2 once we build
/// a Jira API data pipeline that can generate the data on demand.
struct ReportCatalog {
    static let all: [ReportItem] = [
        // ── AWS Cost Reports (hit AWS Cost Explorer API directly) ────────
        ReportItem(id: "aws_cam_prod", title: "CAM Production Costs",
                   description: "Previous month cost breakdown by service for CAM Production (809167139867)",
                   section: .awsCost, scriptName: "generate_real_aws_report.py",
                   csvKeys: [], chartType: .bar),
        ReportItem(id: "aws_smoke_test", title: "Top 10 Services",
                   description: "Quick snapshot — top 10 AWS services by spend in CAM Production",
                   section: .awsCost, scriptName: "test_real_aws_costs.py",
                   csvKeys: [], chartType: .horizontalBar),

        // ── Jira / SRE Analytics (coming soon — Phase 2 will query Jira API directly) ──
        // Placeholder: these will be added when the Jira API pipeline is built.
    ]

    static func reports(for section: ReportSection) -> [ReportItem] {
        all.filter { $0.section == section }
    }

    /// Sections that actually have reports.
    static var activeSections: [ReportSection] {
        ReportSection.allCases.filter { !reports(for: $0).isEmpty }
    }
}

import Foundation

/// A report that can be selected from the sidebar.
struct ReportItem: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let section: ReportSection
    let scriptName: String
    let csvKeys: [String]
    let chartType: ChartType

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ReportItem, rhs: ReportItem) -> Bool { lhs.id == rhs.id }
}

enum ReportSection: String, CaseIterable {
    case awsCost = "AWS Cost Reports"
    case jiraAnalytics = "Jira / SRE Analytics"
    case fy26Eval = "FY26 Self-Evaluation"
    case automation = "Automation & Scheduling"

    var icon: String {
        switch self {
        case .awsCost: return "dollarsign.circle"
        case .jiraAnalytics: return "chart.bar.xaxis"
        case .fy26Eval: return "checkmark.seal"
        case .automation: return "clock.arrow.2.circlepath"
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
struct ReportCatalog {
    static let all: [ReportItem] = [
        // AWS Cost Reports
        ReportItem(id: "aws_cam_prod", title: "CAM Production Costs",
                   description: "Monthly cost breakdown by service for CAM Production (809167139867)",
                   section: .awsCost, scriptName: "generate_real_aws_report.py",
                   csvKeys: [], chartType: .bar),
        ReportItem(id: "aws_smoke_test", title: "Top 10 Services",
                   description: "Quick view — top 10 AWS services by cost",
                   section: .awsCost, scriptName: "test_real_aws_costs.py",
                   csvKeys: [], chartType: .horizontalBar),

        // Jira / SRE Analytics
        ReportItem(id: "jira_epic_dist", title: "Epic Distribution",
                   description: "Strategic category breakdown: Security, Infra, KTLO, Cloud Migration, Platform Growth",
                   section: .jiraAnalytics, scriptName: "analyze_boomi_sre.py",
                   csvKeys: ["Epics completed by Boomi SRE in 2025.csv"], chartType: .pie),
        ReportItem(id: "jira_sev2", title: "Sev2 Incidents YoY",
                   description: "Year-over-year Sev2 incident comparison with monthly trends",
                   section: .jiraAnalytics, scriptName: "analyze_sev2.py",
                   csvKeys: ["All Incidents 2024 Boomi Wide.csv", "All Incidents 2025 Boomi Wide.csv"],
                   chartType: .line),
        ReportItem(id: "jira_planned_unplanned", title: "Planned vs Unplanned",
                   description: "Work volume breakdown by status and priority, YoY comparison",
                   section: .jiraAnalytics, scriptName: "planned_vs_unplanned.py",
                   csvKeys: ["Planned 2024.csv", "Planned 2025.csv", "Unplanned 2024.csv", "Unplanned 2025.csv"],
                   chartType: .stackedBar),
        ReportItem(id: "jira_team_perf", title: "Team Performance",
                   description: "Individual contributor work volume and YoY trends",
                   section: .jiraAnalytics, scriptName: "team_performance.py",
                   csvKeys: ["Planned 2024.csv", "Planned 2025.csv", "Unplanned 2024.csv", "Unplanned 2025.csv"],
                   chartType: .bar),
        ReportItem(id: "jira_yoy", title: "YoY Comparison",
                   description: "Planned, unplanned, and incident totals — full year-over-year delta",
                   section: .jiraAnalytics, scriptName: "yoy_comparison.py",
                   csvKeys: ["Planned 2024.csv", "Planned 2025.csv", "Unplanned 2024.csv", "Unplanned 2025.csv",
                             "All Incidents 2024 Boomi Wide.csv", "All Incidents 2025 Boomi Wide.csv"],
                   chartType: .stackedBar),
        ReportItem(id: "jira_work_dist", title: "Work Distribution",
                   description: "Epic distribution by category with percentages",
                   section: .jiraAnalytics, scriptName: "work_distribution.py",
                   csvKeys: ["CAMSRE-Epics-CY25.csv"], chartType: .pie),
        ReportItem(id: "jira_alert_yoy", title: "Alert Volume YoY",
                   description: "Alert volume year-over-year: totals, status breakdown",
                   section: .jiraAnalytics, scriptName: "analyze_unplanned.py",
                   csvKeys: ["finalAlertData CY24.csv", "finalAlertData CY25.csv"], chartType: .bar),
    ]

    static func reports(for section: ReportSection) -> [ReportItem] {
        all.filter { $0.section == section }
    }
}

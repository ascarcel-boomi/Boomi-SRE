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

    var isRealTime: Bool { csvKeys.isEmpty }
}

enum ReportSection: String, CaseIterable {
    case jiraDashboard = "Jira Dashboards"
    case awsCost = "AWS Cost Reports"

    var icon: String {
        switch self {
        case .jiraDashboard: return "person.crop.rectangle.stack"
        case .awsCost: return "dollarsign.circle"
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

struct ReportCatalog {
    static let all: [ReportItem] = [
        // Jira Dashboards (native Swift — queries Jira API directly)
        ReportItem(id: "jira_todo", title: "My TODO",
                   description: "Personal task list from sprint work and unplanned kanban",
                   section: .jiraDashboard, scriptName: "", csvKeys: [], chartType: .stackedBar),
        ReportItem(id: "jira_filters", title: "Saved Filters",
                   description: "Run and visualize your favourite Jira filters with auto-generated charts",
                   section: .jiraDashboard, scriptName: "", csvKeys: [], chartType: .bar),
        ReportItem(id: "jira_boards", title: "Boards",
                   description: "Browse Jira boards across your projects — scrum sprints and kanban boards",
                   section: .jiraDashboard, scriptName: "", csvKeys: [], chartType: .pie),

        // AWS Cost Reports (Python scripts via subprocess)
        ReportItem(id: "aws_cam_prod", title: "CAM Production Costs",
                   description: "Previous month cost breakdown by service for CAM Production (809167139867)",
                   section: .awsCost, scriptName: "generate_real_aws_report.py",
                   csvKeys: [], chartType: .bar),
        ReportItem(id: "aws_smoke_test", title: "Top 10 Services",
                   description: "Quick snapshot — top 10 AWS services by spend in CAM Production",
                   section: .awsCost, scriptName: "test_real_aws_costs.py",
                   csvKeys: [], chartType: .horizontalBar),
    ]

    static func reports(for section: ReportSection) -> [ReportItem] {
        all.filter { $0.section == section }
    }

    static var activeSections: [ReportSection] {
        ReportSection.allCases.filter { !reports(for: $0).isEmpty }
    }
}

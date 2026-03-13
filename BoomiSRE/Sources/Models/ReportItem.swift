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
    case ai = "AI"
    case jira = "Jira"
    case aws = "AWS"
    case services = "Services"
    case google = "Google"

    var icon: String {
        switch self {
        case .ai:       return "sparkles"
        case .jira:     return "ticket"
        case .aws:      return "cloud"
        case .services: return "network"
        case .google:   return "envelope"
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
        // Incidents (placed first for visibility)
        ReportItem(id: "incidents", title: "Incidents",
                   description: "Declare and manage P1–P4 incidents with AI-assisted analysis",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table),

        // AI
        ReportItem(id: "copilot_chat", title: "AI Copilot",
                   description: "Chat with an AI assistant that knows your tickets, costs, and calendar",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table),
        ReportItem(id: "exec_assistant", title: "Executive Assistant",
                   description: "7 AI briefings: morning brief, email triage, ticket plan, and more",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table),

        // Jira
        ReportItem(id: "jira_todo", title: "My TODO",
                   description: "Personal task list from sprint work and unplanned kanban",
                   section: .jira, scriptName: "", csvKeys: [], chartType: .stackedBar),
        ReportItem(id: "jira_filters", title: "Saved Filters",
                   description: "Run and visualize your favourite Jira filters with auto-generated charts",
                   section: .jira, scriptName: "", csvKeys: [], chartType: .bar),
        ReportItem(id: "jira_boards", title: "Boards",
                   description: "Browse Jira boards across your projects — scrum sprints and kanban boards",
                   section: .jira, scriptName: "", csvKeys: [], chartType: .pie),

        // Services
        ReportItem(id: "github_browser", title: "GitHub",
                   description: "Browse repos, open PRs, and CI runs with AI code review",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table),
        ReportItem(id: "jenkins_browser", title: "Jenkins",
                   description: "Browse jobs, build history, and console output with AI failure analysis",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table),
        ReportItem(id: "grafana_browser", title: "Grafana",
                   description: "Browse dashboards, panels, and alert rules with AI insights",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table),
        ReportItem(id: "confluence_browser", title: "Confluence",
                   description: "Browse spaces, pages, and search with AI summaries and page drafting",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table),

        // AWS
        ReportItem(id: "aws_cost_explorer", title: "Cost Explorer",
                   description: "Query AWS Cost Explorer for the active profile — costs by service, region, or account",
                   section: .aws, scriptName: "", csvKeys: [], chartType: .horizontalBar),

        // Google
        ReportItem(id: "google_gmail", title: "Gmail",
                   description: "Recent emails from your Boomi Google inbox",
                   section: .google, scriptName: "", csvKeys: [], chartType: .table),
        ReportItem(id: "google_calendar", title: "Calendar",
                   description: "Upcoming events from your Google Calendar",
                   section: .google, scriptName: "", csvKeys: [], chartType: .table),
        ReportItem(id: "google_chat", title: "Chat",
                   description: "Google Chat spaces and recent messages",
                   section: .google, scriptName: "", csvKeys: [], chartType: .table),
    ]

    static func reports(for section: ReportSection) -> [ReportItem] {
        all.filter { $0.section == section }
    }

    static var activeSections: [ReportSection] {
        ReportSection.allCases.filter { !reports(for: $0).isEmpty }
    }
}

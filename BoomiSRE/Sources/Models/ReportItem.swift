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
    let icon: String

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
        // Notifications
        ReportItem(id: "notifications", title: "Notifications",
                   description: "Background alerts: Jira assignments, Jenkins failures, Grafana alerts, PR reviews",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "bell"),

        // Incidents (placed first for visibility)
        ReportItem(id: "incidents", title: "Incidents",
                   description: "Declare and manage P1–P4 incidents with AI-assisted analysis",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "exclamationmark.shield"),

        // Knowledge Base
        ReportItem(id: "knowledge_base", title: "Knowledge Base",
                   description: "SOPs, runbooks, guides, and Boomi documentation from the team KB",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "book.closed"),

        // On-Call
        ReportItem(id: "oncall", title: "On-Call",
                   description: "On-call schedules, alerts, and team rosters from JSM",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "phone.badge.waveform"),

        // AI
        ReportItem(id: "copilot_chat", title: "AI Copilot",
                   description: "Chat with an AI assistant that knows your tickets, costs, and calendar",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "sparkles"),
        ReportItem(id: "exec_assistant", title: "Executive Assistant",
                   description: "7 AI briefings: morning brief, email triage, ticket plan, and more",
                   section: .ai, scriptName: "", csvKeys: [], chartType: .table, icon: "list.clipboard"),

        // Jira
        ReportItem(id: "jira_todo", title: "My TODO",
                   description: "Personal task list from sprint work and unplanned kanban",
                   section: .jira, scriptName: "", csvKeys: [], chartType: .stackedBar, icon: "checklist"),
        ReportItem(id: "jira_filters", title: "Saved Filters",
                   description: "Run and visualize your favourite Jira filters with auto-generated charts",
                   section: .jira, scriptName: "", csvKeys: [], chartType: .bar, icon: "line.3.horizontal.decrease.circle"),
        ReportItem(id: "jira_boards", title: "Boards",
                   description: "Browse Jira boards across your projects — scrum sprints and kanban boards",
                   section: .jira, scriptName: "", csvKeys: [], chartType: .pie, icon: "rectangle.split.3x3"),

        // Services
        ReportItem(id: "github_browser", title: "GitHub",
                   description: "Browse repos, open PRs, and CI runs with AI code review",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table, icon: "chevron.left.forwardslash.chevron.right"),
        ReportItem(id: "jenkins_browser", title: "Jenkins",
                   description: "Browse jobs, build history, and console output with AI failure analysis",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table, icon: "hammer"),
        ReportItem(id: "grafana_browser", title: "Grafana",
                   description: "Browse dashboards, panels, and alert rules with AI insights",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table, icon: "chart.bar.xaxis"),
        ReportItem(id: "confluence_browser", title: "Confluence",
                   description: "Browse spaces, pages, and search with AI summaries and page drafting",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table, icon: "doc.richtext"),
        ReportItem(id: "bitbucket_browser", title: "Bitbucket",
                   description: "Browse repos, PRs, branches, and pipelines with AI review",
                   section: .services, scriptName: "", csvKeys: [], chartType: .table,
                   icon: "arrow.triangle.branch"),

        // AWS
        ReportItem(id: "aws_health", title: "Infrastructure Health",
                   description: "EC2, ALB, RDS, Lambda, CloudWatch — account health at a glance",
                   section: .aws, scriptName: "", csvKeys: [], chartType: .table, icon: "heart.text.square"),
        ReportItem(id: "aws_cost_explorer", title: "Cost Explorer",
                   description: "Query AWS Cost Explorer for the active profile — costs by service, region, or account",
                   section: .aws, scriptName: "", csvKeys: [], chartType: .horizontalBar, icon: "dollarsign.circle"),

        // Google
        ReportItem(id: "google_gmail", title: "Gmail",
                   description: "Recent emails from your Boomi Google inbox",
                   section: .google, scriptName: "", csvKeys: [], chartType: .table, icon: "envelope"),
        ReportItem(id: "google_calendar", title: "Calendar",
                   description: "Upcoming events from your Google Calendar",
                   section: .google, scriptName: "", csvKeys: [], chartType: .table, icon: "calendar"),
        ReportItem(id: "google_chat", title: "Chat",
                   description: "Google Chat spaces and recent messages",
                   section: .google, scriptName: "", csvKeys: [], chartType: .table, icon: "bubble.left.and.bubble.right"),
    ]

    static func reports(for section: ReportSection) -> [ReportItem] {
        all.filter { $0.section == section }
    }

    static var activeSections: [ReportSection] {
        ReportSection.allCases.filter { !reports(for: $0).isEmpty }
    }
}

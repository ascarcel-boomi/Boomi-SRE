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
    case commandCenter  = "Command Center"
    case work           = "Work"
    case infrastructure = "Infrastructure"
    case observability  = "Observability"
    case sourceControl  = "Source Control"
    case automation     = "Automation"
    case knowledge      = "Knowledge"
    case communication  = "Communication"

    var icon: String {
        switch self {
        case .commandCenter:  return "bolt.shield.fill"
        case .work:           return "checklist.checked"
        case .infrastructure: return "server.rack"
        case .observability:  return "eye"
        case .sourceControl:  return "chevron.left.forwardslash.chevron.right"
        case .automation:     return "gearshape.2"
        case .knowledge:      return "books.vertical"
        case .communication:  return "bubble.left.and.bubble.right"
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

        // ── COMMAND CENTER ────────────────────────────────────────────
        ReportItem(id: "notifications", title: "Notifications",
                   description: "Background alerts: Jira assignments, Jenkins failures, Grafana alerts, PR reviews",
                   section: .commandCenter, scriptName: "", csvKeys: [], chartType: .table, icon: "bell"),
        ReportItem(id: "incidents", title: "Incidents",
                   description: "Declare and manage P1–P4 incidents with AI-assisted analysis",
                   section: .commandCenter, scriptName: "", csvKeys: [], chartType: .table, icon: "exclamationmark.shield"),
        ReportItem(id: "oncall", title: "On-Call",
                   description: "On-call schedules, alerts, and team rosters from JSM",
                   section: .commandCenter, scriptName: "", csvKeys: [], chartType: .table, icon: "phone.badge.waveform"),
        ReportItem(id: "copilot_chat", title: "AI Copilot",
                   description: "Chat with an AI assistant that knows your tickets, costs, and calendar",
                   section: .commandCenter, scriptName: "", csvKeys: [], chartType: .table, icon: "sparkles"),
        ReportItem(id: "exec_assistant", title: "Executive Assistant",
                   description: "7 AI briefings: morning brief, email triage, ticket plan, and more",
                   section: .commandCenter, scriptName: "", csvKeys: [], chartType: .table, icon: "list.clipboard"),

        // ── WORK ──────────────────────────────────────────────────────
        ReportItem(id: "jira_todo", title: "My TODO",
                   description: "Personal task list from sprint work and unplanned kanban",
                   section: .work, scriptName: "", csvKeys: [], chartType: .stackedBar, icon: "checklist"),
        ReportItem(id: "jira_filters", title: "Saved Filters",
                   description: "Run and visualize your favourite Jira filters with auto-generated charts",
                   section: .work, scriptName: "", csvKeys: [], chartType: .bar, icon: "line.3.horizontal.decrease.circle"),
        ReportItem(id: "jira_boards", title: "Boards",
                   description: "Browse Jira boards across your projects — scrum sprints and kanban boards",
                   section: .work, scriptName: "", csvKeys: [], chartType: .pie, icon: "rectangle.split.3x3"),

        // ── INFRASTRUCTURE ────────────────────────────────────────────
        ReportItem(id: "aws_health", title: "AWS Health",
                   description: "EC2, ALB, RDS, Lambda — account health at a glance",
                   section: .infrastructure, scriptName: "", csvKeys: [], chartType: .table, icon: "heart.text.square"),
        ReportItem(id: "aws_cost_explorer", title: "AWS Costs",
                   description: "Costs by service, region, or account",
                   section: .infrastructure, scriptName: "", csvKeys: [], chartType: .horizontalBar, icon: "dollarsign.circle"),

        // ── OBSERVABILITY ─────────────────────────────────────────────
        ReportItem(id: "grafana_browser", title: "Grafana",
                   description: "Dashboards, alerts, and panels with AI insights",
                   section: .observability, scriptName: "", csvKeys: [], chartType: .table, icon: "chart.bar.xaxis"),

        // ── SOURCE CONTROL ────────────────────────────────────────────
        ReportItem(id: "github_browser", title: "GitHub",
                   description: "Repos, PRs, Actions, and AI code review",
                   section: .sourceControl, scriptName: "", csvKeys: [], chartType: .table, icon: "chevron.left.forwardslash.chevron.right"),
        ReportItem(id: "bitbucket_browser", title: "Bitbucket",
                   description: "Repos, PRs, branches, and pipelines",
                   section: .sourceControl, scriptName: "", csvKeys: [], chartType: .table, icon: "arrow.triangle.branch"),

        // ── AUTOMATION ────────────────────────────────────────────────
        ReportItem(id: "jenkins_browser", title: "Jenkins",
                   description: "Jobs, builds, and AI failure analysis",
                   section: .automation, scriptName: "", csvKeys: [], chartType: .table, icon: "hammer"),

        // ── KNOWLEDGE ─────────────────────────────────────────────────
        ReportItem(id: "knowledge_base", title: "Knowledge Base",
                   description: "SOPs, runbooks, and Boomi documentation",
                   section: .knowledge, scriptName: "", csvKeys: [], chartType: .table, icon: "book.closed"),
        ReportItem(id: "confluence_browser", title: "Confluence",
                   description: "Wiki spaces, pages, and AI summaries",
                   section: .knowledge, scriptName: "", csvKeys: [], chartType: .table, icon: "doc.richtext"),

        // ── COMMUNICATION ─────────────────────────────────────────────
        ReportItem(id: "google_gmail", title: "Gmail",
                   description: "Your Boomi inbox",
                   section: .communication, scriptName: "", csvKeys: [], chartType: .table, icon: "envelope"),
        ReportItem(id: "google_calendar", title: "Calendar",
                   description: "Upcoming meetings and events",
                   section: .communication, scriptName: "", csvKeys: [], chartType: .table, icon: "calendar"),
    ]

    static func reports(for section: ReportSection) -> [ReportItem] {
        all.filter { $0.section == section }
    }

    static var activeSections: [ReportSection] {
        ReportSection.allCases.filter { !reports(for: $0).isEmpty }
    }
}

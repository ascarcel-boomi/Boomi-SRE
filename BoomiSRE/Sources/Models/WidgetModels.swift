import Foundation

enum WidgetType: String, Codable, CaseIterable {
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts   // JSM Ops alerts (open, unacked, assigned to me)
    case awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary

    var title: String {
        switch self {
        case .activeIncidents: return "Active Incidents"
        case .myTickets: return "My Tickets"
        case .recentPRs: return "Open PRs"
        case .jenkinsBuilds: return "Jenkins Builds"
        case .grafanaAlerts: return "Grafana Alerts"
        case .jsmOpsAlerts: return "JSM Ops Alerts"
        case .awsCostTrend: return "AWS Cost"
        case .upcomingCalendar: return "Calendar"
        case .unreadEmails: return "Email"
        case .confluenceRecent: return "Confluence"
        case .serviceHealth: return "Service Health"
        case .quickActions: return "Quick Actions"
        case .aiDailySummary: return "AI Daily Summary"
        }
    }

    var icon: String {
        switch self {
        case .activeIncidents: return "exclamationmark.shield"
        case .myTickets: return "checklist"
        case .recentPRs: return "arrow.triangle.pull"
        case .jenkinsBuilds: return "hammer"
        case .grafanaAlerts: return "bell.badge"
        case .jsmOpsAlerts: return "bell.badge.fill"
        case .awsCostTrend: return "dollarsign.circle"
        case .upcomingCalendar: return "calendar"
        case .unreadEmails: return "envelope.badge"
        case .confluenceRecent: return "doc.richtext"
        case .serviceHealth: return "network"
        case .quickActions: return "bolt.circle"
        case .aiDailySummary: return "sparkles"
        }
    }
}

enum WidgetSize: String, Codable {
    case small, medium, large
}

struct DashboardWidget: Identifiable, Codable {
    var id: UUID
    var type: WidgetType
    var position: Int
    var size: WidgetSize
    var isEnabled: Bool

    init(id: UUID = UUID(), type: WidgetType, position: Int, size: WidgetSize = .medium, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.position = position
        self.size = size
        self.isEnabled = isEnabled
    }
}

extension DashboardWidget {
    static var defaults: [DashboardWidget] {
        [
            DashboardWidget(type: .serviceHealth,    position: 0, size: .small),
            DashboardWidget(type: .quickActions,     position: 1, size: .small),
            DashboardWidget(type: .activeIncidents,  position: 2, size: .medium),
            DashboardWidget(type: .jsmOpsAlerts,     position: 3, size: .medium),
            DashboardWidget(type: .grafanaAlerts,    position: 4, size: .medium),
            DashboardWidget(type: .myTickets,        position: 5, size: .medium),
            DashboardWidget(type: .jenkinsBuilds,    position: 5, size: .medium),
            DashboardWidget(type: .recentPRs,        position: 6, size: .medium),
            DashboardWidget(type: .upcomingCalendar, position: 7, size: .medium),
            DashboardWidget(type: .aiDailySummary,   position: 8, size: .large),
        ]
    }
}

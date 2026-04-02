import Foundation

enum WidgetType: String, Codable, CaseIterable {
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts, awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary
    case notifications, onCallSchedule

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
        case .aiDailySummary: return "AI Executive Assistant"
        case .notifications: return "Notifications"
        case .onCallSchedule: return "On-Call"
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
        case .notifications: return "bell.fill"
        case .onCallSchedule: return "phone.badge.waveform"
        }
    }

    var hasFilters: Bool {
        switch self {
        case .jsmOpsAlerts, .grafanaAlerts, .myTickets, .jenkinsBuilds,
             .recentPRs, .notifications, .activeIncidents, .onCallSchedule: return true
        default: return false
        }
    }
}

struct DashboardWidget: Identifiable, Codable, Equatable {
    var id: UUID
    var type: WidgetType
    var position: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), type: WidgetType, position: Int, isEnabled: Bool = true) {
        self.id = id; self.type = type; self.position = position; self.isEnabled = isEnabled
    }

    static func == (lhs: DashboardWidget, rhs: DashboardWidget) -> Bool { lhs.id == rhs.id }

    // Custom CodingKeys to ignore old fields (size, columnSpan) from saved configs
    enum CodingKeys: String, CodingKey { case id, type, position, isEnabled }
}

extension DashboardWidget {
    static var defaults: [DashboardWidget] {
        [
            DashboardWidget(type: .activeIncidents,  position: 0),
            DashboardWidget(type: .jsmOpsAlerts,     position: 1),
            DashboardWidget(type: .grafanaAlerts,    position: 2),
            DashboardWidget(type: .onCallSchedule,   position: 3),
            DashboardWidget(type: .notifications,    position: 4),
            DashboardWidget(type: .myTickets,        position: 5),
            DashboardWidget(type: .jenkinsBuilds,    position: 6),
            DashboardWidget(type: .recentPRs,        position: 7),
            DashboardWidget(type: .serviceHealth,    position: 8),
            DashboardWidget(type: .quickActions,     position: 9),
            DashboardWidget(type: .upcomingCalendar, position: 10),
            DashboardWidget(type: .unreadEmails,     position: 11),
            DashboardWidget(type: .awsCostTrend,     position: 12),
            DashboardWidget(type: .confluenceRecent, position: 13),
            DashboardWidget(type: .aiDailySummary,   position: 14),
        ]
    }
}

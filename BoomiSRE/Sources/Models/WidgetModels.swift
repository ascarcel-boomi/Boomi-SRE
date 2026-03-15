import Foundation

enum WidgetType: String, Codable, CaseIterable {
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts
    case awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary
    case notifications      // Recent notifications from the notification system
    case onCallSchedule     // Who's currently on call

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
        case .notifications: return "Notifications"
        case .onCallSchedule: return "On-Call"
        }
    }

    /// Widget types that support per-widget filtering
    var hasFilters: Bool {
        switch self {
        case .jsmOpsAlerts, .grafanaAlerts, .myTickets, .jenkinsBuilds,
             .recentPRs, .notifications, .activeIncidents, .onCallSchedule: return true
        default: return false
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
            DashboardWidget(type: .activeIncidents,  position: 2,  size: .medium),
            DashboardWidget(type: .jsmOpsAlerts,     position: 3,  size: .medium),
            DashboardWidget(type: .grafanaAlerts,    position: 4,  size: .medium),
            DashboardWidget(type: .onCallSchedule,   position: 5,  size: .medium),
            DashboardWidget(type: .notifications,    position: 6,  size: .medium),
            DashboardWidget(type: .myTickets,        position: 7,  size: .medium),
            DashboardWidget(type: .jenkinsBuilds,    position: 8,  size: .medium),
            DashboardWidget(type: .recentPRs,        position: 9,  size: .medium),
            DashboardWidget(type: .upcomingCalendar, position: 10, size: .medium),
            DashboardWidget(type: .unreadEmails,     position: 11, size: .small),
            DashboardWidget(type: .awsCostTrend,     position: 12, size: .small),
            DashboardWidget(type: .confluenceRecent, position: 13, size: .small),
            DashboardWidget(type: .aiDailySummary,   position: 14, size: .large),
        ]
    }
}

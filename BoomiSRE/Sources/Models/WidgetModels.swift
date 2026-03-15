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
    var size: WidgetSize      // kept for backward compat with saved configs
    var columnSpan: Int       // primary sizing: how many grid columns this spans (1...maxColumns)
    var isEnabled: Bool

    init(id: UUID = UUID(), type: WidgetType, position: Int,
         size: WidgetSize = .medium, columnSpan: Int = 1, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.position = position
        self.size = size
        self.columnSpan = columnSpan
        self.isEnabled = isEnabled
    }

    /// WidgetSize derived from columnSpan for widget views
    var effectiveSize: WidgetSize {
        switch columnSpan {
        case 1: return .small
        case 2: return .medium
        default: return .large
        }
    }
}

extension DashboardWidget {
    /// System defaults — use `columns` to set full-width spans correctly
    static func defaults(columns: Int = 3) -> [DashboardWidget] {
        [
            DashboardWidget(type: .activeIncidents,  position: 0,  columnSpan: columns),
            DashboardWidget(type: .jsmOpsAlerts,     position: 1,  columnSpan: 2),
            DashboardWidget(type: .grafanaAlerts,    position: 2,  columnSpan: 1),
            DashboardWidget(type: .onCallSchedule,   position: 3,  columnSpan: 1),
            DashboardWidget(type: .notifications,    position: 4,  columnSpan: 1),
            DashboardWidget(type: .myTickets,        position: 5,  columnSpan: 1),
            DashboardWidget(type: .jenkinsBuilds,    position: 6,  columnSpan: 1),
            DashboardWidget(type: .recentPRs,        position: 7,  columnSpan: 1),
            DashboardWidget(type: .serviceHealth,    position: 8,  columnSpan: 1),
            DashboardWidget(type: .quickActions,     position: 9,  columnSpan: 1),
            DashboardWidget(type: .upcomingCalendar, position: 10, columnSpan: 1),
            DashboardWidget(type: .unreadEmails,     position: 11, columnSpan: 1),
            DashboardWidget(type: .awsCostTrend,     position: 12, columnSpan: 1),
            DashboardWidget(type: .confluenceRecent, position: 13, columnSpan: 1),
            DashboardWidget(type: .aiDailySummary,   position: 14, columnSpan: columns),
        ]
    }

    /// Backward-compat shim — used by older code that referenced `.defaults` as a property
    static var defaults: [DashboardWidget] { defaults(columns: 3) }
}

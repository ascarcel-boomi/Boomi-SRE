import Foundation
import SwiftUI

struct FeedItem: Identifiable {
    let id: String
    let source: FeedSource
    let priority: FeedPriority
    let title: String
    let subtitle: String
    let detail: String
    let timestamp: Date
    let actions: [FeedAction]
    let navigateTo: String?
    let metadata: [String: String]

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

enum FeedSource: String {
    case jsmAlert    = "JSM Alert"
    case grafanaAlert = "Grafana Alert"
    case incident    = "Incident"
    case jiraTicket  = "Jira"
    case githubPR    = "GitHub PR"
    case jenkinsBuild = "Jenkins"
    case onCall      = "On-Call"
    case notification = "Notification"
    case aiSummary   = "AI Summary"

    var icon: String {
        switch self {
        case .jsmAlert:       return "bell.badge.fill"
        case .grafanaAlert:   return "bell.badge"
        case .incident:       return "exclamationmark.shield"
        case .jiraTicket:     return "checklist"
        case .githubPR:       return "arrow.triangle.pull"
        case .jenkinsBuild:   return "hammer"
        case .onCall:         return "phone.badge.waveform"
        case .notification:   return "bell.fill"
        case .aiSummary:      return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .jsmAlert, .grafanaAlert: return .red
        case .incident:      return .red
        case .jiraTicket:    return .blue
        case .githubPR:      return .purple
        case .jenkinsBuild:  return .orange
        case .onCall:        return .green
        case .notification:  return .secondary
        case .aiSummary:     return .accentColor
        }
    }
}

enum FeedPriority: Int, Comparable {
    case critical = 0
    case high = 1
    case medium = 2
    case low = 3
    case info = 4

    static func < (lhs: FeedPriority, rhs: FeedPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct FeedAction: Identifiable {
    let id: String
    let label: String
    let icon: String
    let style: ActionStyle
    let action: () async -> Void

    enum ActionStyle {
        case primary
        case secondary
        case destructive
    }
}

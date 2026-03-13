import Foundation
import SwiftUI

// MARK: - Notification Type

enum NotificationType: String, Codable, CaseIterable {
    case jiraAssigned            = "Jira Assigned"
    case jiraStatusChange        = "Jira Status Change"
    case jenkinsBuildFailed      = "Jenkins Failed"
    case jenkinsBuildRecovered   = "Jenkins Recovered"
    case grafanaAlertFiring      = "Grafana Alert"
    case grafanaAlertResolved    = "Grafana Resolved"
    case githubPRReview          = "PR Review Requested"
    case githubPRMerged          = "PR Merged"
    case githubWorkflowFailed    = "Workflow Failed"
    case confluencePageUpdated   = "Confluence Updated"
    case briefingGenerated       = "Briefing Ready"
    case awsCostAnomaly          = "Cost Anomaly"

    var icon: String {
        switch self {
        case .jiraAssigned:          return "ticket"
        case .jiraStatusChange:      return "arrow.triangle.2.circlepath"
        case .jenkinsBuildFailed:    return "xmark.circle.fill"
        case .jenkinsBuildRecovered: return "checkmark.circle.fill"
        case .grafanaAlertFiring:    return "bell.badge.fill"
        case .grafanaAlertResolved:  return "bell.slash.fill"
        case .githubPRReview:        return "arrow.triangle.pull"
        case .githubPRMerged:        return "arrow.triangle.merge"
        case .githubWorkflowFailed:  return "gearshape.fill"
        case .confluencePageUpdated: return "doc.text.fill"
        case .briefingGenerated:     return "doc.text"
        case .awsCostAnomaly:        return "dollarsign.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .jiraAssigned:          return .blue
        case .jiraStatusChange:      return .blue
        case .jenkinsBuildFailed:    return .red
        case .jenkinsBuildRecovered: return .green
        case .grafanaAlertFiring:    return .red
        case .grafanaAlertResolved:  return .green
        case .githubPRReview:        return .purple
        case .githubPRMerged:        return .purple
        case .githubWorkflowFailed:  return .orange
        case .confluencePageUpdated: return Color.accentColor
        case .briefingGenerated:     return Color.accentColor
        case .awsCostAnomaly:        return .orange
        }
    }

    /// Whether this type triggers a macOS system notification.
    var isHighPriority: Bool {
        switch self {
        case .jenkinsBuildFailed, .grafanaAlertFiring, .jiraAssigned, .githubWorkflowFailed: return true
        default: return false
        }
    }
}

// MARK: - SRE Notification

struct SRENotification: Identifiable, Codable {
    var id: UUID
    let type: NotificationType
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool
    /// Report ID to navigate to when user taps the notification.
    let deepLink: String?
    /// Extra context: ticket key, job name, etc.
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        type: NotificationType,
        title: String,
        body: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        deepLink: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.deepLink = deepLink
        self.metadata = metadata
    }

    /// Relative timestamp string.
    var relativeTime: String {
        let diff = Date().timeIntervalSince(timestamp)
        if diff < 60   { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        return df.string(from: timestamp)
    }
}

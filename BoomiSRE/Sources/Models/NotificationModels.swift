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
    case appUpdate               = "App Update"

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
        case .appUpdate:             return "arrow.down.circle.fill"
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
        case .appUpdate:             return Color.accentColor
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

// MARK: - Archive Retention

enum ArchiveRetention: String, Codable, CaseIterable {
    case hours24  = "24 Hours"
    case today    = "Today"
    case workWeek = "Work Week"
    case days7    = "7 Days"

    /// The earliest date an archived notification may have been archived and still be kept.
    func cutoff() -> Date {
        let cal = Calendar.current
        switch self {
        case .hours24:
            return Date().addingTimeInterval(-86400)
        case .today:
            return cal.startOfDay(for: Date())
        case .workWeek:
            // Start of Monday of the current week
            let now = Date()
            let weekday = cal.component(.weekday, from: now) // 1=Sun … 7=Sat
            let daysFromMonday = (weekday + 5) % 7           // 0=Mon, 1=Tue …
            return cal.startOfDay(for: now.addingTimeInterval(-Double(daysFromMonday) * 86400))
        case .days7:
            return Date().addingTimeInterval(-7 * 86400)
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
    var isArchived: Bool
    var archivedAt: Date?
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
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        deepLink: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.deepLink = deepLink
        self.metadata = metadata
    }

    // Custom Codable so old notifications without isArchived/archivedAt decode cleanly.
    enum CodingKeys: String, CodingKey {
        case id, type, title, body, timestamp, isRead, isArchived, archivedAt, deepLink, metadata
    }

    init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,              forKey: .id)
        type       = try c.decode(NotificationType.self,  forKey: .type)
        title      = try c.decode(String.self,            forKey: .title)
        body       = try c.decode(String.self,            forKey: .body)
        timestamp  = try c.decode(Date.self,              forKey: .timestamp)
        isRead     = try c.decode(Bool.self,              forKey: .isRead)
        isArchived = try c.decodeIfPresent(Bool.self,     forKey: .isArchived) ?? false
        archivedAt = try c.decodeIfPresent(Date.self,     forKey: .archivedAt)
        deepLink   = try c.decodeIfPresent(String.self,   forKey: .deepLink)
        metadata   = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(type,       forKey: .type)
        try c.encode(title,      forKey: .title)
        try c.encode(body,       forKey: .body)
        try c.encode(timestamp,  forKey: .timestamp)
        try c.encode(isRead,     forKey: .isRead)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try c.encodeIfPresent(deepLink,   forKey: .deepLink)
        try c.encode(metadata,   forKey: .metadata)
    }

    /// Relative timestamp string.
    var relativeTime: String {
        let diff = Date().timeIntervalSince(timestamp)
        if diff < 60    { return "Just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        return df.string(from: timestamp)
    }
}

import Foundation
import SwiftUI

// MARK: - Severity

enum IncidentSeverity: String, Codable, CaseIterable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"

    var label: String { rawValue }

    var color: Color {
        switch self {
        case .p1: return .red
        case .p2: return .orange
        case .p3: return .yellow
        case .p4: return .blue
        }
    }

    var icon: String {
        switch self {
        case .p1: return "exclamationmark.triangle.fill"
        case .p2: return "exclamationmark.triangle"
        case .p3: return "exclamationmark.circle"
        case .p4: return "info.circle"
        }
    }

    var isActive: Bool { self == .p1 || self == .p2 }
}

// MARK: - Status

enum IncidentStatus: String, Codable, CaseIterable {
    case investigating = "Investigating"
    case identified    = "Identified"
    case monitoring    = "Monitoring"
    case resolved      = "Resolved"

    var color: Color {
        switch self {
        case .investigating: return .red
        case .identified:    return .orange
        case .monitoring:    return .blue
        case .resolved:      return .green
        }
    }

    var icon: String {
        switch self {
        case .investigating: return "magnifyingglass"
        case .identified:    return "checkmark.magnifyingglass"
        case .monitoring:    return "eye"
        case .resolved:      return "checkmark.circle.fill"
        }
    }

    var isResolved: Bool { self == .resolved }
}

// MARK: - Timeline Entry

struct TimelineEntry: Identifiable, Codable {
    var id: UUID
    let timestamp: Date
    let content: String
    let source: String   // "user", "ai", "jira", "grafana", "jenkins", "system"

    init(id: UUID = UUID(), timestamp: Date = Date(), content: String, source: String) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.source = source
    }

    var sourceIcon: String {
        switch source {
        case "ai":      return "sparkles"
        case "jira":    return "ticket"
        case "grafana": return "chart.bar"
        case "jenkins": return "hammer"
        case "system":  return "gear"
        default:        return "person"
        }
    }

    var sourceColor: Color {
        switch source {
        case "ai":      return .purple
        case "jira":    return .blue
        case "grafana": return .orange
        case "jenkins": return .gray
        case "system":  return .secondary
        default:        return .primary
        }
    }
}

// MARK: - Incident

struct Incident: Identifiable, Codable {
    var id: UUID
    var title: String
    var severity: IncidentSeverity
    var status: IncidentStatus
    var createdAt: Date
    var resolvedAt: Date?
    var jiraTicketKey: String?
    var timeline: [TimelineEntry]
    var affectedServices: [String]
    var aiAnalysis: String?

    init(
        id: UUID = UUID(),
        title: String,
        severity: IncidentSeverity,
        status: IncidentStatus = .investigating,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        jiraTicketKey: String? = nil,
        timeline: [TimelineEntry] = [],
        affectedServices: [String] = [],
        aiAnalysis: String? = nil
    ) {
        self.id = id
        self.title = title
        self.severity = severity
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.jiraTicketKey = jiraTicketKey
        self.timeline = timeline
        self.affectedServices = affectedServices
        self.aiAnalysis = aiAnalysis
    }

    /// Human-readable duration since incident creation.
    var elapsedString: String {
        let end = resolvedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(createdAt))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var isActive: Bool { !status.isResolved }

    var isHighPriority: Bool { severity == .p1 || severity == .p2 }
}

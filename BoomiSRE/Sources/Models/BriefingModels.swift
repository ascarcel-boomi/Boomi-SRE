import Foundation

// MARK: - Briefing

struct Briefing: Identifiable, Codable, Equatable {
    var id: UUID
    let type: BriefingType
    let title: String
    let content: String          // markdown from Claude
    let generatedAt: Date
    var contextSummary: String   // e.g. "3 meetings, 12 emails"
    var isRead: Bool

    init(
        id: UUID = UUID(),
        type: BriefingType,
        content: String,
        generatedAt: Date = Date(),
        contextSummary: String = "",
        isRead: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = type.title
        self.content = content
        self.generatedAt = generatedAt
        self.contextSummary = contextSummary
        self.isRead = isRead
    }
}

// MARK: - Briefing Type

enum BriefingType: String, Codable, CaseIterable {
    case morningBrief
    case emailTriage
    case preMeetingBrief
    case actionTracker
    case eodDigest
    case dailyTicketBrief
    case claudeUsage

    var title: String {
        switch self {
        case .morningBrief:    return "Morning Brief"
        case .emailTriage:     return "Email Triage"
        case .preMeetingBrief: return "Pre-Meeting Brief"
        case .actionTracker:   return "Action Tracker"
        case .eodDigest:       return "EOD Digest"
        case .dailyTicketBrief: return "Daily Ticket Brief"
        case .claudeUsage:     return "Claude Usage"
        }
    }

    var icon: String {
        switch self {
        case .morningBrief:    return "sun.horizon"
        case .emailTriage:     return "envelope.badge"
        case .preMeetingBrief: return "person.2.wave.2"
        case .actionTracker:   return "checkmark.circle"
        case .eodDigest:       return "moon.stars"
        case .dailyTicketBrief: return "ticket"
        case .claudeUsage:     return "chart.bar"
        }
    }

    var description: String {
        switch self {
        case .morningBrief:    return "Calendar + overnight emails → day overview"
        case .emailTriage:     return "Inbox → P1/P2/P3 prioritization with reply suggestions"
        case .preMeetingBrief: return "Next meeting + related emails → talking points"
        case .actionTracker:   return "Today's emails + meetings → action items"
        case .eodDigest:       return "Day recap + open items + tomorrow preview"
        case .dailyTicketBrief: return "Open Jira tickets → prioritized daily plan"
        case .claudeUsage:     return "~/.claude/ logs → cost & usage report"
        }
    }

    /// Requires Google Workspace (Gmail + Calendar) to be configured.
    var requiresGoogle: Bool {
        switch self {
        case .morningBrief, .emailTriage, .preMeetingBrief, .actionTracker, .eodDigest:
            return true
        case .dailyTicketBrief, .claudeUsage:
            return false
        }
    }

    /// Requires Jira to be configured.
    var requiresJira: Bool { self == .dailyTicketBrief }
}

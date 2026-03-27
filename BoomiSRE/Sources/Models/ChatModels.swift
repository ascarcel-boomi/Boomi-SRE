import Foundation

// MARK: - Copilot Message

struct CopilotMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: CopilotRole
    /// Content shown in the UI (just the user's text for user messages with context).
    var content: String
    /// Full content sent to the API — includes injected context preamble for user turns.
    /// Nil means use `content` directly.
    var apiContent: String?
    var timestamp: Date
    var contextSources: [ContextSource]
    /// Set for `.system` messages that represent a live tool call (fetch / post).
    var toolEvent: ToolCallEvent?
    /// Set for `.system` messages that need user confirmation before a Jira action.
    var pendingAction: PendingCommentConfirmation?

    init(
        id: UUID = UUID(),
        role: CopilotRole,
        content: String,
        apiContent: String? = nil,
        timestamp: Date = Date(),
        contextSources: [ContextSource] = [],
        toolEvent: ToolCallEvent? = nil,
        pendingAction: PendingCommentConfirmation? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.apiContent = apiContent
        self.timestamp = timestamp
        self.contextSources = contextSources
        self.toolEvent = toolEvent
        self.pendingAction = pendingAction
    }
}

enum CopilotRole: String, Codable {
    case user, assistant, system
}

// MARK: - Context Source

struct ContextSource: Identifiable, Codable, Equatable {
    var id: UUID
    var type: ContextType
    var label: String
    var summary: String

    init(id: UUID = UUID(), type: ContextType, label: String, summary: String) {
        self.id = id
        self.type = type
        self.label = label
        self.summary = summary
    }
}

// MARK: - Context Type

enum ContextType: String, Codable, CaseIterable {
    case jiraTickets, grafanaAlerts, jenkinsBuilds, awsCosts, calendar, email

    var icon: String {
        switch self {
        case .jiraTickets:    return "ticket"
        case .grafanaAlerts:  return "bell.badge"
        case .jenkinsBuilds:  return "hammer"
        case .awsCosts:       return "dollarsign.circle"
        case .calendar:       return "calendar"
        case .email:          return "envelope"
        }
    }

    var displayName: String {
        switch self {
        case .jiraTickets:    return "Jira"
        case .grafanaAlerts:  return "Alerts"
        case .jenkinsBuilds:  return "Builds"
        case .awsCosts:       return "AWS"
        case .calendar:       return "Calendar"
        case .email:          return "Email"
        }
    }
}

// MARK: - Quick Action

enum QuickAction: String, CaseIterable {
    case troubleshoot = "Troubleshoot an issue"
    case summarizeDay = "Summarize my day"
    case prioritizeTickets = "Prioritize my tickets"
    case whatNext = "What should I work on next?"
    case draftPostmortem = "Draft incident postmortem"
    case costTrends = "Explain cost trends"
    case planSprint = "Plan next sprint"
    case draftRunbook = "Draft a runbook"

    var icon: String {
        switch self {
        case .troubleshoot: return "wrench.and.screwdriver"
        case .summarizeDay: return "sun.max"
        case .prioritizeTickets: return "list.number"
        case .costTrends: return "chart.line.uptrend.xyaxis"
        case .draftPostmortem: return "exclamationmark.triangle"
        case .planSprint: return "calendar.badge.plus"
        case .whatNext: return "arrow.right.circle"
        case .draftRunbook: return "doc.text"
        }
    }

    var contextTypes: Set<ContextType> {
        switch self {
        case .troubleshoot: return [.jiraTickets, .grafanaAlerts, .jenkinsBuilds]
        case .summarizeDay: return [.jiraTickets, .calendar, .email, .grafanaAlerts]
        case .prioritizeTickets: return [.jiraTickets, .grafanaAlerts]
        case .costTrends: return [.awsCosts]
        case .draftPostmortem: return [.jiraTickets, .grafanaAlerts]
        case .planSprint: return [.jiraTickets]
        case .whatNext: return [.jiraTickets, .calendar, .grafanaAlerts]
        case .draftRunbook: return []
        }
    }

    var prompt: String {
        switch self {
        case .troubleshoot:
            return "I need to troubleshoot an issue. Here's what I know:\n\n[Describe the issue, paste an alert, or mention a ticket key like CAMSRE-123]\n\nPlease cross-reference alerts, recent builds, and related tickets to help me understand the full picture — root cause, blast radius, and recommended next steps."
        case .summarizeDay:
            return "Summarize my day: what alerts are firing, what meetings do I have, what emails need attention, and what are my top ticket priorities?"
        case .prioritizeTickets:
            return "Review my open Jira tickets and any active alerts. Give me a prioritized list of what to work on today, with specific reasons for each priority."
        case .costTrends:
            return "Analyze my AWS costs. What are the top cost drivers? Are there any anomalies or optimization opportunities?"
        case .draftPostmortem:
            return "Help me draft an incident postmortem. I'll describe the incident below — please structure it with timeline, root cause, impact, and action items:\n\n[Describe the incident here]"
        case .planSprint:
            return "Based on my open Jira tickets, help me plan the next sprint. What should be included, and what should be deferred?"
        case .whatNext:
            return "Given my open tickets, today's calendar, and any active alerts, what should I focus on right now? Give me a specific recommendation with reasoning."
        case .draftRunbook:
            return "Help me draft a runbook for the following topic:\n\n[Topic here]"
        }
    }
}

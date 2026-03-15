import Foundation

struct ProductivityEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let action: ProductivityAction
    let detail: String
    let estimatedMinutesSaved: Double
    let source: String

    init(id: UUID = UUID(), action: ProductivityAction, detail: String,
         estimatedMinutesSaved: Double, source: String) {
        self.id = id
        self.timestamp = Date()
        self.action = action
        self.detail = detail
        self.estimatedMinutesSaved = estimatedMinutesSaved
        self.source = source
    }
}

enum ProductivityAction: String, Codable {
    case alertAcknowledged
    case alertClosed
    case alertSnoozed
    case alertNoteAdded
    case aiCopilotQuery
    case aiPRSummary
    case aiPRReview
    case aiIncidentAnalysis
    case aiPostmortemDraft
    case aiStatusUpdateDraft
    case aiRemediationSuggestion
    case aiDashboardExplain
    case aiAlertAnalyze
    case aiPageSummarize
    case aiPageDraft
    case aiCostAnalysis
    case aiDailySummary
    case aiPCRGeneration
    case kbArticleLookup
    case ticketViewedInApp
    case prViewedInApp
    case buildViewedInApp
    case incidentCreated
    case productContextSwitch
    case bulkAlertAcknowledge
    case bulkAlertClose

    var estimatedMinutes: Double {
        switch self {
        case .alertAcknowledged, .alertClosed, .alertNoteAdded: return 2
        case .alertSnoozed: return 1
        case .aiCopilotQuery: return 3
        case .aiPRSummary: return 10
        case .aiPRReview: return 15
        case .aiIncidentAnalysis, .aiRemediationSuggestion, .aiStatusUpdateDraft, .aiCostAnalysis: return 10
        case .aiPostmortemDraft, .aiPCRGeneration: return 30
        case .aiDashboardExplain, .aiAlertAnalyze, .aiPageSummarize: return 5
        case .aiPageDraft: return 20
        case .aiDailySummary: return 15
        case .kbArticleLookup: return 5
        case .ticketViewedInApp, .prViewedInApp, .buildViewedInApp: return 1
        case .incidentCreated: return 5
        case .productContextSwitch: return 3
        case .bulkAlertAcknowledge, .bulkAlertClose: return 1
        }
    }

    var category: String {
        switch self {
        case .alertAcknowledged, .alertClosed, .alertSnoozed, .alertNoteAdded,
             .bulkAlertAcknowledge, .bulkAlertClose:
            return "Alert Management"
        case .aiCopilotQuery, .aiPRSummary, .aiPRReview, .aiIncidentAnalysis,
             .aiPostmortemDraft, .aiStatusUpdateDraft, .aiRemediationSuggestion,
             .aiDashboardExplain, .aiAlertAnalyze, .aiPageSummarize, .aiPageDraft,
             .aiCostAnalysis, .aiDailySummary, .aiPCRGeneration:
            return "AI Assistance"
        case .kbArticleLookup:
            return "Knowledge"
        case .ticketViewedInApp, .prViewedInApp, .buildViewedInApp,
             .incidentCreated, .productContextSwitch:
            return "Navigation"
        }
    }
}

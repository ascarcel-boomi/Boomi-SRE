import Foundation
import SwiftUI

// MARK: - UserProfile

struct UserProfile: Codable {
    // Auto-discovered (populated from service auth checks)
    var displayName: String
    var email: String
    var avatarURL: String?
    var githubHandle: String?
    var jiraAccountId: String?
    var timeZone: String

    // User-editable
    var role: SRERole
    var experienceLevel: ExperienceLevel
    var team: String
    var onCallInfo: String
    var notes: String

    // MARK: Computed

    var firstName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let name = firstName
        return name.isEmpty ? timeOfDay : "\(timeOfDay), \(name)"
    }

    // MARK: Defaults

    static var empty: UserProfile {
        UserProfile(
            displayName: "",
            email: "",
            avatarURL: nil,
            githubHandle: nil,
            jiraAccountId: nil,
            timeZone: TimeZone.current.identifier,
            role: .sre,
            experienceLevel: .mid,
            team: "",
            onCallInfo: "",
            notes: ""
        )
    }
}

// MARK: - SRERole

enum SRERole: String, Codable, CaseIterable {
    case sre              = "SRE"
    case seniorSRE        = "Senior SRE"
    case devops           = "DevOps Engineer"
    case platformEngineer = "Platform Engineer"
    case manager          = "Engineering Manager"
    case director         = "Director"
    case other            = "Other"

    var displayName: String { rawValue }
}

// MARK: - ExperienceLevel

enum ExperienceLevel: String, Codable, CaseIterable {
    case junior = "Junior"
    case mid    = "Mid-Level"
    case senior = "Senior"
    case lead   = "Lead / Staff"

    var displayName: String { rawValue }

    /// Controls AI response depth and verbosity.
    var analysisDepthHint: String {
        switch self {
        case .junior:
            return "Explain concepts clearly, avoid jargon, be encouraging and educational. The reader is still learning."
        case .mid:
            return "Be practical and specific. Assume working knowledge of SRE fundamentals."
        case .senior:
            return "Be concise and technical. Skip basics, focus on root cause and tradeoffs."
        case .lead:
            return "Be strategic. Include blast radius, business impact, and cross-team coordination needs."
        }
    }

    /// Whether "Explain this" buttons should be shown prominently in section headers.
    var showExplainProminently: Bool {
        switch self {
        case .junior, .mid: return true
        case .senior, .lead: return false
        }
    }

    var color: String {
        switch self {
        case .junior: return "blue"
        case .mid:    return "green"
        case .senior: return "orange"
        case .lead:   return "purple"
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openSettingsProfileTab = Notification.Name("openSettingsProfileTab")
}

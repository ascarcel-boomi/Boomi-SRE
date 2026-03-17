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

    // Corporate identity (Okta SSO)
    var oktaEmail: String?
    var oktaDomain: String?

    // User-editable
    var role: SRERole
    var experienceLevel: ExperienceLevel
    var team: String
    var onCallInfo: String
    var notes: String

    /// Product IDs this SRE supports (subset of ProductContext.defaults IDs).
    /// Used to pre-populate the active product filter and personalize AI context.
    var myProducts: Set<String>

    // MARK: Codable — explicit keys for backward compat (myProducts defaults to [])

    private enum CodingKeys: String, CodingKey {
        case displayName, email, avatarURL, githubHandle, jiraAccountId, timeZone
        case oktaEmail, oktaDomain
        case role, experienceLevel, team, onCallInfo, notes
        case myProducts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName    = try c.decode(String.self, forKey: .displayName)
        email          = try c.decode(String.self, forKey: .email)
        avatarURL      = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        githubHandle   = try c.decodeIfPresent(String.self, forKey: .githubHandle)
        jiraAccountId  = try c.decodeIfPresent(String.self, forKey: .jiraAccountId)
        timeZone       = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? TimeZone.current.identifier
        oktaEmail      = try c.decodeIfPresent(String.self, forKey: .oktaEmail)
        oktaDomain     = try c.decodeIfPresent(String.self, forKey: .oktaDomain)
        role           = try c.decodeIfPresent(SRERole.self, forKey: .role) ?? .sre
        experienceLevel = try c.decodeIfPresent(ExperienceLevel.self, forKey: .experienceLevel) ?? .mid
        team           = try c.decodeIfPresent(String.self, forKey: .team) ?? ""
        onCallInfo     = try c.decodeIfPresent(String.self, forKey: .onCallInfo) ?? ""
        notes          = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let productArray = try c.decodeIfPresent([String].self, forKey: .myProducts) ?? []
        myProducts     = Set(productArray)
    }

    // Memberwise init used by static factories and tests
    init(displayName: String, email: String, avatarURL: String? = nil,
         githubHandle: String? = nil, jiraAccountId: String? = nil,
         timeZone: String = TimeZone.current.identifier,
         oktaEmail: String? = nil, oktaDomain: String? = nil,
         role: SRERole = .sre, experienceLevel: ExperienceLevel = .mid,
         team: String = "", onCallInfo: String = "", notes: String = "",
         myProducts: Set<String> = []) {
        self.displayName     = displayName
        self.email           = email
        self.avatarURL       = avatarURL
        self.githubHandle    = githubHandle
        self.jiraAccountId   = jiraAccountId
        self.timeZone        = timeZone
        self.oktaEmail       = oktaEmail
        self.oktaDomain      = oktaDomain
        self.role            = role
        self.experienceLevel = experienceLevel
        self.team            = team
        self.onCallInfo      = onCallInfo
        self.notes           = notes
        self.myProducts      = myProducts
    }

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

    static var empty: UserProfile { UserProfile(displayName: "", email: "") }
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
    static let openSettingsAboutTab = Notification.Name("openSettingsAboutTab")
    static let focusAIBar = Notification.Name("focusAIBar")
    static let toggleAIBar = Notification.Name("toggleAIBar")
}

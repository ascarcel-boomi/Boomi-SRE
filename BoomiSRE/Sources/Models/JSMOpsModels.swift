import Foundation

struct OpsTeam: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
    }
}

struct OnCallParticipant: Identifiable, Codable, Sendable {
    var id: String { "\(name)-\(type)" }
    let name: String
    let type: String  // "user" or "escalation"

    enum CodingKeys: String, CodingKey { case name, type }
}

struct AlertResponder: Sendable {
    let id: String
    let type: String  // "team", "user"
}

struct OpsAlert: Identifiable, Sendable {
    let id: String
    let tinyId: String          // short numeric ID, e.g. "148783"
    let message: String
    let status: String          // "open", "closed", "acked"
    let priority: String        // "P1"–"P5"
    let acknowledged: Bool
    let owner: String           // email of the owner (may be empty)
    let source: String          // e.g. "Coralogix", "New Relic"
    let integrationType: String // e.g. "Coralogix", "NewRelicV2"
    let integrationName: String // e.g. "Data Integration Devops - Coralogix"
    let createdAt: String
    let updatedAt: String
    let tags: [String]
    let snoozed: Bool
    let count: Int
    let responders: [AlertResponder]
}

struct OpsSchedule: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let teamId: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, teamId, enabled
    }
}

struct OnCallResult: Sendable {
    let team: OpsTeam
    let participants: [OnCallParticipant]
    let schedule: OpsSchedule?
}

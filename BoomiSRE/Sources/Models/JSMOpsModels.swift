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

struct OpsAlert: Identifiable, Codable, Sendable {
    let id: String
    let message: String
    let status: String      // "open", "acked", "closed"
    let priority: String    // "P1"-"P5"
    let createdAt: String
    let updatedAt: String
    let source: String?
    let tags: [String]?
    let teamId: String?

    enum CodingKeys: String, CodingKey {
        case id, message, status, priority, createdAt, updatedAt, source, tags, teamId
    }

    var priorityColor: String {
        switch priority {
        case "P1": return "red"
        case "P2": return "orange"
        case "P3": return "yellow"
        case "P4": return "blue"
        default:   return "gray"
        }
    }
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

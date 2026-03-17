import Foundation
import Network

/// A discovered peer on the local network running Boomi SRE.
struct Peer: Identifiable, Hashable, Sendable {
    let id: String              // endpoint hash or email
    var displayName: String
    var email: String
    var role: String
    var team: String
    var product: String         // active product short name or "All"
    var screen: String          // currentScreenContext
    var appVersion: String
    var lastSeen: Date

    /// Peer is considered stale if not seen in 120 seconds.
    var isStale: Bool { Date().timeIntervalSince(lastSeen) > 120 }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Peer, rhs: Peer) -> Bool { lhs.id == rhs.id }

    // MARK: - TXT Record

    /// Build a Peer from a Bonjour TXT record dictionary.
    static func fromTXTRecord(_ dict: [String: String], endpointId: String) -> Peer {
        Peer(
            id: dict["em"] ?? endpointId,
            displayName: dict["dn"] ?? "Unknown",
            email: dict["em"] ?? "",
            role: dict["ro"] ?? "",
            team: dict["tm"] ?? "",
            product: dict["pr"] ?? "All",
            screen: dict["sc"] ?? "",
            appVersion: dict["av"] ?? "",
            lastSeen: Date()
        )
    }

    /// Encode this peer's info into a TXT record dictionary.
    func toTXTRecord() -> [String: String] {
        [
            "dn": String(displayName.prefix(40)),
            "em": String(email.prefix(60)),
            "ro": String(role.prefix(20)),
            "tm": String(team.prefix(30)),
            "pr": String(product.prefix(20)),
            "sc": String(screen.prefix(40)),
            "av": String(appVersion.prefix(20)),
        ]
    }

    /// Convert a TXT record dictionary to NWTXTRecord.
    static func makeTXTRecord(from dict: [String: String]) -> NWTXTRecord {
        Peer.buildTXTRecord(from: dict)
    }

    /// Parse an NWTXTRecord into a dictionary.
    static func parseTXTRecord(_ record: NWTXTRecord) -> [String: String] {
        Peer.parseTXTRecordDict(record)
    }
}

// MARK: - NWTXTRecord helpers

extension Peer {
    /// Parse an NWTXTRecord into a dictionary using known keys.
    static func parseTXTRecordDict(_ record: NWTXTRecord) -> [String: String] {
        var dict: [String: String] = [:]
        let keys = ["dn", "em", "ro", "tm", "pr", "sc", "av"]
        for key in keys {
            if let entry = record.getEntry(for: key) {
                switch entry {
                case .string(let value):
                    dict[key] = value
                default: break
                }
            }
        }
        return dict
    }

    /// Build an NWTXTRecord from a dictionary.
    static func buildTXTRecord(from dict: [String: String]) -> NWTXTRecord {
        var record = NWTXTRecord()
        for (key, value) in dict {
            record[key] = value
        }
        return record
    }
}

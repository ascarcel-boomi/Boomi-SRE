import Foundation

/// Lightweight model for Confluence space list in Preferences and browser.
struct ConfluenceSpaceSummary: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let key: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, key, name
    }
}

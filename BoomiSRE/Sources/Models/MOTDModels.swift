import Foundation

struct MOTDMessage: Identifiable {
    let id = UUID()
    let quote: String
    let attribution: String
    let category: MOTDCategory
    let emoji: String
}

enum MOTDCategory: String, CaseIterable {
    case teamPhilosophy = "Team Philosophy"
    case sreWisdom      = "SRE Wisdom"
    case boomiPride     = "Boomi"
    case ninjaSpirit    = "Ninja Spirit"
}

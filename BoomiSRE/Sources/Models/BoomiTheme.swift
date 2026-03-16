import SwiftUI

enum AppTheme: String, Codable, CaseIterable {
    case system = "System"
    case boomi  = "Boomi"

    var displayName: String { rawValue }
}

struct BoomiColors {
    static let deepNavy     = Color(hex: "072B55")
    static let boomiPurple  = Color(hex: "4B4FE2")
    static let boomiMagenta = Color(hex: "A03291")
    static let boomiGreen   = Color(hex: "0EC38B")
    static let boomiCoral   = Color(hex: "FF7C66")
    static let darkIndigo   = Color(hex: "181CAF")
    static let boomiMaroon  = Color(hex: "7B0A2E")

    static let gradientGreenPurple = LinearGradient(
        colors: [boomiGreen, boomiPurple], startPoint: .leading, endPoint: .trailing)
    static let gradientPurpleMagenta = LinearGradient(
        colors: [boomiPurple, boomiMagenta], startPoint: .leading, endPoint: .trailing)
    static let gradientMagentaCoral = LinearGradient(
        colors: [boomiMagenta, boomiCoral], startPoint: .leading, endPoint: .trailing)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension AppState {
    var themeAccent: Color {
        appTheme == "boomi" ? BoomiColors.boomiPurple : .accentColor
    }
    var themeSuccess: Color {
        appTheme == "boomi" ? BoomiColors.boomiGreen : .green
    }
    var themeWarning: Color {
        appTheme == "boomi" ? BoomiColors.boomiCoral : .orange
    }
    var themeDanger: Color {
        appTheme == "boomi" ? BoomiColors.boomiMagenta : .red
    }
}

import SwiftUI

/// Calls the built-in macOS About panel with custom credits content.
/// This is the only reliable approach for SPM-built .app bundles.
func showAboutPanel() {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    let year = String(Calendar.current.component(.year, from: Date()))

    // Build the credits attributed string
    let credits = NSMutableAttributedString()

    // Quote
    let quoteStyle = NSMutableParagraphStyle()
    quoteStyle.alignment = .center
    quoteStyle.paragraphSpacing = 12
    credits.append(NSAttributedString(
        string: "\u{201C}You\u{2019}re only limited by your imagination!\u{201D}\n\n",
        attributes: [
            .font: NSFont(name: "Georgia-Italic", size: 13) ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: quoteStyle,
        ]
    ))

    // Authors header
    let headerStyle = NSMutableParagraphStyle()
    headerStyle.alignment = .center
    headerStyle.paragraphSpacing = 6
    credits.append(NSAttributedString(
        string: "Authors\n",
        attributes: [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: headerStyle,
        ]
    ))

    // Author list
    let authors: [(String, String)] = [
        ("Adam Scarcella",     "Creator & Lead Engineer"),
        ("Henry Wang",         "APIM SRE"),
        ("James Beck",         "APIM SRE"),
        ("Mayur Gupta",        "APIM SRE"),
        ("Aviral Shukla",      "APIM SRE"),
        ("Vishwajit Nagulkar", "APIM SRE"),
        ("Jason Schadel",      "APIM SRE"),
        ("Bill Shikrallah",    "APIM SRE"),
    ]

    let authorStyle = NSMutableParagraphStyle()
    authorStyle.alignment = .center
    authorStyle.paragraphSpacing = 2
    for (name, role) in authors {
        credits.append(NSAttributedString(
            string: "\(name)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: authorStyle,
            ]
        ))
        credits.append(NSAttributedString(
            string: "  \(role)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: authorStyle,
            ]
        ))
    }

    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        .applicationName:    "Boomi SRE",
        .applicationVersion: "Version \(version)",
        .version:            "",
        .credits:            credits,
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(year) Boomi, Ltd. All rights reserved.",
    ])
}

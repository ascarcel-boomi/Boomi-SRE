import SwiftUI

/// Calls the built-in macOS About panel with custom credits content.
/// Core authors have hardcoded roles; additional git contributors are appended dynamically.
func showAboutPanel() {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    let year = String(Calendar.current.component(.year, from: Date()))

    // Core authors with their titles (always shown first)
    let coreAuthors: [(name: String, role: String)] = [
        ("Adam Scarcella", "Lead Idea Generator"),
        ("Claude Opus",    "Ph.D PM with a 250 AIQ"),
        ("Claude Sonnet",  "Master Coder"),
    ]
    let coreNames = Set(coreAuthors.map(\.name))

    // Additional contributors from git shortlog (anyone not already in the core list)
    var extraAuthors: [String] = []
    if let authorsPath = Bundle.main.path(forResource: "AUTHORS", ofType: nil),
       let content = try? String(contentsOfFile: authorsPath, encoding: .utf8) {
        extraAuthors = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !coreNames.contains($0) }
    }

    let credits = NSMutableAttributedString()

    // Spacer before quote
    credits.append(NSAttributedString(string: "\n"))

    // Quote
    let quoteStyle = NSMutableParagraphStyle()
    quoteStyle.alignment = .center
    quoteStyle.paragraphSpacing = 14
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

    // Core authors with roles
    let authorStyle = NSMutableParagraphStyle()
    authorStyle.alignment = .center
    authorStyle.paragraphSpacing = 3
    for author in coreAuthors {
        credits.append(NSAttributedString(
            string: author.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: authorStyle,
            ]
        ))
        credits.append(NSAttributedString(
            string: "  \(author.role)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: authorStyle,
            ]
        ))
    }

    // Additional git contributors (no role, appended automatically)
    for name in extraAuthors {
        credits.append(NSAttributedString(
            string: "\(name)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
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

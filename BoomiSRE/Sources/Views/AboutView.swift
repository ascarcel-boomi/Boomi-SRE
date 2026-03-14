import SwiftUI

/// Menu button that opens the About window imperatively (no window restoration on launch).
struct AboutMenuItem: View {
    var body: some View {
        Button("About Boomi SRE") {
            AboutWindowController.shared.show()
        }
    }
}

/// Opens AboutView in a plain NSPanel so macOS never restores it on launch.
@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: AboutView())
        hosting.sizingOptions = .preferredContentSize
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Boomi SRE"
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    }

    private let authors: [(name: String, role: String)] = [
        ("Adam Scarcella",    "Creator & Lead Engineer"),
        ("Henry Wang",        "APIM SRE"),
        ("James Beck",        "APIM SRE"),
        ("Mayur Gupta",       "APIM SRE"),
        ("Aviral Shukla",     "APIM SRE"),
        ("Vishwajit Nagulkar","APIM SRE"),
        ("Jason Schadel",     "APIM SRE"),
        ("Bill Shikrallah",   "APIM SRE"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // App icon + name
            VStack(spacing: 8) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                } else {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                }

                Text("Boomi SRE")
                    .font(.title.bold())

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 16)

            Divider()

            // Quote
            VStack(spacing: 4) {
                Text("\u{201C}You\u{2019}re only limited by your imagination!\u{201D}")
                    .font(.system(.body, design: .serif).italic())
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)

            Divider()

            // Authors
            VStack(alignment: .leading, spacing: 10) {
                Text("Authors")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)

                ForEach(authors, id: \.name) { author in
                    HStack {
                        Text(author.name)
                            .font(.callout)
                        Spacer()
                        Text(author.role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)

            Divider()

            // Copyright
            Text("© \(String(Calendar.current.component(.year, from: Date()))) Boomi, Ltd. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
        .fixedSize()
    }
}

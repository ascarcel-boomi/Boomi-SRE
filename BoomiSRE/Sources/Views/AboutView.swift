import SwiftUI
import AppKit

// MARK: - Custom About Panel

/// Replaces the standard NSApplication About panel with a custom NSWindow
/// containing all content visible without scrolling.
///
/// Single-instance: if the window is already open, brings it to front.
private var aboutWindow: NSWindow?

func showAboutPanel() {
    // Bring existing window to front rather than creating a duplicate
    if let existing = aboutWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        return
    }

    let hostingView = NSHostingView(rootView: AboutPanelContent())
    hostingView.setFrameSize(hostingView.fittingSize)

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.title = "About Boomi SRE"
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.makeKeyAndOrderFront(nil)

    aboutWindow = window
}

// MARK: - About Panel Content

struct AboutPanelContent: View {
    @State private var currentMOTD = MOTDLibrary.messageOfTheMoment()
    @State private var motdOpacity: Double = 1.0

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    private let year    = String(Calendar.current.component(.year, from: Date()))

    private let coreAuthors: [(name: String, role: String)] = [
        ("Adam Scarcella", "Lead Idea Generator"),
        ("Claude Opus",    "Ph.D PM with a 250 AIQ"),
        ("Claude Sonnet",  "Master Coder"),
    ]

    private var extraAuthors: [String] {
        guard let path    = Bundle.main.path(forResource: "AUTHORS", ofType: nil),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let coreNames = Set(coreAuthors.map(\.name))
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !coreNames.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {

            // App icon
            Group {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                }
            }

            // App name + version
            VStack(spacing: 4) {
                Text("Boomi SRE")
                    .font(.title.bold())
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // MOTD card
            motdCard

            // Inspirational quote
            Text("\u{201C}You\u{2019}re only limited by your imagination!\u{201D}")
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Authors
            VStack(spacing: 6) {
                Text("Authors")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                ForEach(coreAuthors, id: \.name) { author in
                    HStack(spacing: 0) {
                        Text(author.name)
                            .font(.callout)
                            .frame(width: 140, alignment: .trailing)
                        Text("  ")
                        Text(author.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ForEach(extraAuthors, id: \.self) { name in
                    Text(name)
                        .font(.callout)
                }
            }

            // Copyright
            Text("© \(year) Boomi, Ltd. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(width: 380)
        .onAppear {
            currentMOTD = MOTDLibrary.messageOfTheMoment()
        }
    }

    // MARK: - MOTD card

    private var motdCard: some View {
        Button { cycleMOTD() } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)

                Text(currentMOTD.emoji)
                    .font(.title3)
                    .frame(width: 26)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentMOTD.quote)
                        .font(.callout.italic())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("— \(currentMOTD.attribution)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Tap for a new message")
        .opacity(motdOpacity)
        .animation(.easeInOut(duration: 0.3), value: motdOpacity)
    }

    // MARK: - MOTD cycling

    private func cycleMOTD() {
        withAnimation(.easeInOut(duration: 0.3)) { motdOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            currentMOTD = MOTDLibrary.nextRandom(excluding: currentMOTD)
            withAnimation(.easeInOut(duration: 0.3)) { motdOpacity = 1 }
        }
    }
}

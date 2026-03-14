import SwiftUI

/// Menu button that opens the custom About window.
struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Boomi SRE") {
            openWindow(id: "about")
        }
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
            Text("© \(Calendar.current.component(.year, from: Date())) Boomi, Ltd. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
        .fixedSize()
    }
}

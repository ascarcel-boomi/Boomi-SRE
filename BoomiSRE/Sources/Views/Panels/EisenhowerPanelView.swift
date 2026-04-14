import SwiftUI
import AppKit

// MARK: - EisenhowerPanelView

/// Right-side panel showing Focus Now top 3 + four quadrant sections with compact cards.
struct EisenhowerPanelView: View {
    @EnvironmentObject var appState: AppState
    let result: EisenhowerResult
    let onSelectTicket: (String) -> Void
    @Binding var highlightedKey: String?

    var body: some View {
        Group {
            if result.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
        .frame(minWidth: 220, maxWidth: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: DesignTokens.emptyIconSize))
                .foregroundStyle(.secondary)
            Text("No work found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("No tickets are assigned to you or on your watchlist for the current quarter.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.sectionPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !result.focusNow.isEmpty {
                        quadrantSection(
                            emoji: "⚡️",
                            title: "FOCUS NOW",
                            accent: .purple,
                            items: result.focusNow,
                            isFocusNow: true
                        )
                    }

                    quadrantSection(
                        emoji: "🔴",
                        title: "DO FIRST",
                        accent: .red,
                        items: result.doFirst,
                        isFocusNow: false
                    )

                    quadrantSection(
                        emoji: "🔵",
                        title: "SCHEDULE",
                        accent: .blue,
                        items: result.schedule,
                        isFocusNow: false
                    )

                    quadrantSection(
                        emoji: "🟠",
                        title: "DELEGATE",
                        accent: .orange,
                        items: result.delegate,
                        isFocusNow: false
                    )

                    quadrantSection(
                        emoji: "⚫️",
                        title: "ELIMINATE",
                        accent: .gray,
                        items: result.eliminate,
                        isFocusNow: false
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onChange(of: highlightedKey) { _, newKey in
                guard let key = newKey else { return }
                withAnimation {
                    proxy.scrollTo(key, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    highlightedKey = nil
                }
            }
        }
    }

    // MARK: - Section

    private func quadrantSection(
        emoji: String,
        title: String,
        accent: Color,
        items: [EisenhowerItem],
        isFocusNow: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section header
            HStack(spacing: 4) {
                Text("\(emoji) \(title)")
                    .font(.system(.caption, design: .default).weight(.bold))
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                Text("(\(items.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 2)

            if items.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                ForEach(items) { item in
                    EisenhowerCardView(
                        item: item,
                        accent: accent,
                        isFocusNow: isFocusNow,
                        isHighlighted: highlightedKey == item.key,
                        onTap: { onSelectTicket(item.key) },
                        jiraBaseURL: appState.jiraBaseURL
                    )
                    .id(item.key)
                }
            }
        }
    }
}

// MARK: - EisenhowerCardView

/// Compact single-line card for an Eisenhower item.
private struct EisenhowerCardView: View {
    let item: EisenhowerItem
    let accent: Color
    let isFocusNow: Bool
    let isHighlighted: Bool
    let onTap: () -> Void
    let jiraBaseURL: String

    private var fillOpacity: Double {
        if isHighlighted { return 0.25 }
        if isFocusNow { return 0.10 }
        return 0.05
    }

    var body: some View {
        HStack(spacing: 4) {
            // Jira key
            Text(item.key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)

            // Summary
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Delegated eye
            if item.isDelegated {
                Text("👁")
                    .font(.system(size: 10))
                    .help("Watched — assigned to someone else")
            }

            // Status badge
            statusBadge

            // Stale or SP badge
            if let staleDays = item.staleDays, staleDays >= EisenhowerClassifier.staleDaysThreshold {
                stalePill(days: staleDays)
            } else if let sp = item.sp, sp > 0 {
                spPill(sp: sp)
            }

            // Open in Jira button
            Button {
                if let url = URL(string: "\(jiraBaseURL)/browse/\(item.key)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in Jira")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                .fill(accent.opacity(fillOpacity))
        )
        .overlay {
            if isFocusNow {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                    .strokeBorder(accent.opacity(0.3), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Status badge

    @ViewBuilder
    private var statusBadge: some View {
        let (abbrev, color) = statusInfo(item.statusCategory)
        Text(abbrev)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private func statusInfo(_ category: String) -> (String, Color) {
        switch category.lowercased() {
        case "indeterminate": return ("IP", .orange)
        case "new":           return ("TD", .gray)
        case "done":          return ("DN", .green)
        default:              return ("??", .secondary)
        }
    }

    // MARK: Stale pill

    private func stalePill(days: Int) -> some View {
        Text("\(days)d")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.red))
    }

    // MARK: SP pill

    private func spPill(sp: Double) -> some View {
        Text("\(Int(sp))sp")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue))
    }
}

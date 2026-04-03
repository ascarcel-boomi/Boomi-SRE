import SwiftUI

// MARK: - App Theme Environment Key

/// Propagates the current appTheme ("system" or "boomi") through the SwiftUI environment
/// so shared components (SectionHeaderLabel, CardStyle, etc.) can apply brand colors
/// without needing direct access to AppState.
private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: String = "system"
}

extension EnvironmentValues {
    var appTheme: String {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Propagate appTheme from AppState down the view tree.
    func appTheme(_ theme: String) -> some View {
        environment(\.appTheme, theme)
    }
}

// MARK: - Standard Design Tokens
//
// Centralised constants so every view uses the same radii, padding, and opacity values.
// Prefer these over hard-coding numbers in individual views.

enum DesignTokens {
    // Corner radii
    static let cornerRadius: CGFloat = 10
    static let cornerRadiusSmall: CGFloat = 6

    // Padding
    static let cardPadding: CGFloat = 14
    static let sectionPadding: CGFloat = 16
    static let panelPadding: CGFloat = 20

    // Opacity
    static let fillOpacity: Double = 0.06
    static let strokeOpacity: Double = 0.15
    static let badgeFillOpacity: Double = 0.15

    // Empty state icon
    static let emptyIconSize: CGFloat = 48
}

// MARK: - Card Modifier

/// Standard card container: rounded background + subtle border.
/// Use for content sections, detail panels, grouped info.
struct CardStyle: ViewModifier {
    var borderColor: Color = .secondary
    var cornerRadius: CGFloat = DesignTokens.cornerRadius

    func body(content: Content) -> some View {
        content
            .padding(DesignTokens.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor.opacity(DesignTokens.strokeOpacity))
            )
    }
}

extension View {
    /// Standard card wrapper with subtle border.
    func cardStyle(borderColor: Color = .secondary) -> some View {
        modifier(CardStyle(borderColor: borderColor))
    }

    /// Theme-aware card wrapper: uses Boomi purple border when the Boomi theme is active.
    func themedCardStyle(theme: String) -> some View {
        modifier(CardStyle(borderColor: theme == "boomi" ? BoomiColors.boomiPurple : .secondary))
    }
}

// MARK: - Section Card (simpler, fill-only — for inner sections within a scroll view)

struct SectionCardStyle: ViewModifier {
    var cornerRadius: CGFloat = DesignTokens.cornerRadius + 2 // 12pt for outer sections

    func body(content: Content) -> some View {
        content
            .padding(DesignTokens.sectionPadding)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(.background))
    }
}

extension View {
    /// Section-level card (no border, fill-only). Use inside ScrollViews for grouping.
    func sectionCard() -> some View {
        modifier(SectionCardStyle())
    }
}

// MARK: - Status Badge

/// Capsule pill for status, priority, state, and category labels.
struct PillBadge: View {
    let text: String
    var color: Color = .secondary
    var bold: Bool = false

    var body: some View {
        Text(text)
            .font(bold ? .caption.bold() : .caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(DesignTokens.badgeFillOpacity)))
            .foregroundStyle(color)
    }
}

/// Smaller badge variant for compact contexts (lists, table rows).
struct CompactBadge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(DesignTokens.badgeFillOpacity)))
            .foregroundStyle(color)
    }
}

// MARK: - AI Analysis Box

/// Purple-bordered markdown container for AI-generated analysis.
/// Reused across TicketDetail, GitHub PRs, Bitbucket, Jenkins, Confluence, Grafana, SavedFilters.
struct AIAnalysisBox: View {
    let text: String
    var tintColor: Color = .purple
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dismiss = onDismiss {
                HStack {
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss analysis")
                }
                .padding(.bottom, 4)
            }
            InlineMarkdownText(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            .fill(tintColor.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            .strokeBorder(tintColor.opacity(0.2)))
    }
}

// MARK: - Section Header

/// Consistent section header with optional icon.
/// When appTheme == "boomi" and no explicit iconColor is provided, uses the Boomi purple accent.
struct SectionHeaderLabel: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color? = nil  // nil = auto-themed

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(resolvedIconColor)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(appTheme == "boomi" ? BoomiColors.deepNavy.opacity(0.9) : Color.primary)
        }
    }

    private var resolvedIconColor: Color {
        if let explicit = iconColor { return explicit }
        return appTheme == "boomi" ? BoomiColors.boomiPurple : .secondary
    }
}

// MARK: - Panel Header (top bar of a detail pane)

struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(appTheme == "boomi" ? BoomiColors.boomiPurple : Color.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, DesignTokens.panelPadding)
            .padding(.vertical, DesignTokens.sectionPadding)
            Divider()
        }
    }
}

// MARK: - Refresh Timestamp

/// Displays a relative "Updated X ago" label. Shows nothing when the date is nil.
struct RefreshTimestampView: View {
    let date: Date?

    var body: some View {
        if let date {
            Text("Updated \(date, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Browser Sidebar Header

/// Consistent header for browser sidebar panes (GitHub, Bitbucket, Jenkins, etc.)
/// When appTheme == "boomi", renders the title in Boomi purple.
struct BrowserSidebarHeader: View {
    let title: String
    var isLoading: Bool = false
    var lastRefreshed: Date? = nil
    var onRefresh: (() -> Void)? = nil

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(appTheme == "boomi" ? BoomiColors.boomiPurple : Color.primary)
            RefreshTimestampView(date: lastRefreshed)
            Spacer()
            if isLoading { ProgressView().scaleEffect(0.7) }
            if let refresh = onRefresh {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")
            }
        }
        .padding(12)
    }
}

// MARK: - Integration Health Badge

/// A small colored dot + service name indicating integration auth status.
/// Green = authenticated, red = error/expired, yellow = checking, gray = not configured.
struct IntegrationHealthBadge: View {
    let serviceName: String
    let status: AuthStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(serviceName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(status.label)
        .accessibilityLabel("\(serviceName): \(status.label)")
    }

    private var badgeColor: Color {
        switch status {
        case .authenticated: return .green
        case .error, .expired: return .red
        case .checking: return .orange
        case .notConfigured: return Color(nsColor: .placeholderTextColor)
        case .unknown: return .secondary
        }
    }
}

// MARK: - Split View Grip Indicator

/// Overlay a vertical grip pill on the trailing edge of a view to hint that
/// the adjacent HSplitView divider is resizable. Purely cosmetic — the native
/// HSplitView still handles the actual drag.
struct SplitGripOverlay: ViewModifier {
    let edge: Edge

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            gripPill
                .allowsHitTesting(false)  // let clicks pass through to the native divider
        }
    }

    private var alignment: Alignment {
        switch edge {
        case .trailing: return .trailing
        case .leading:  return .leading
        case .bottom:   return .bottom
        case .top:      return .top
        }
    }

    @ViewBuilder
    private var gripPill: some View {
        if edge == .trailing || edge == .leading {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 5, height: 36)
                .padding(edge == .trailing ? .trailing : .leading, 1)
        } else {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(edge == .bottom ? .bottom : .top, 1)
        }
    }
}

extension View {
    /// Add a visible grip pill on the specified edge to hint at resizability.
    func splitGrip(_ edge: Edge = .trailing) -> some View {
        modifier(SplitGripOverlay(edge: edge))
    }
}

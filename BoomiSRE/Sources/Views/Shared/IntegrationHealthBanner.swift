import SwiftUI

/// A compact, full-width banner shown at the top of browser views when the integration
/// is not in an `.authenticated` state. Displays a colored icon, message, and a "Settings"
/// button that deep-links into the relevant integration settings tab.
///
/// Usage:
///     IntegrationHealthBanner(
///         service: "GitHub",
///         status: appState.githubAuthStatus,
///         settingsTab: "github",
///         appState: appState
///     )
///
/// The banner hides itself automatically when `status` is `.authenticated`.
struct IntegrationHealthBanner: View {
    let service: String
    let status: AuthStatus
    let settingsTab: String
    @ObservedObject var appState: AppState

    var body: some View {
        if !status.isOK {
            HStack(spacing: 8) {
                Image(systemName: bannerIcon)
                    .foregroundStyle(bannerColor)

                Text(bannerMessage)
                    .font(.callout)
                    .lineLimit(2)

                Spacer()

                Button("Settings") {
                    appState.selectedSettingsTab = settingsTab
                    appState.showSettings = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                    .fill(bannerColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                    .strokeBorder(bannerColor.opacity(0.18))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Derived properties

    private var bannerIcon: String {
        switch status {
        case .error, .expired:
            return "xmark.circle.fill"
        case .notConfigured:
            return "gear.badge.questionmark"
        case .checking:
            return "arrow.trianglehead.2.clockwise"
        case .unknown:
            return "questionmark.circle"
        case .authenticated:
            return "checkmark.circle.fill" // unreachable due to guard above
        }
    }

    private var bannerColor: Color {
        switch status {
        case .error, .expired: return .red
        case .notConfigured: return .orange
        case .checking: return .orange
        case .unknown: return .secondary
        case .authenticated: return .green
        }
    }

    private var bannerMessage: String {
        switch status {
        case .notConfigured:
            return "\(service) is not configured"
        case .error(let msg):
            return "\(service): \(msg)"
        case .expired:
            return "\(service) session expired"
        case .checking:
            return "Checking \(service)..."
        case .unknown:
            return "\(service) status unknown"
        case .authenticated:
            return "\(service) connected"
        }
    }
}

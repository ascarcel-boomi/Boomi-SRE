import SwiftUI

// MARK: - LoadingView

/// Centered progress spinner with an optional message label.
struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView(message)
                .progressViewStyle(.circular)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EmptyStateView

/// Centered icon + title + optional subtitle for empty list states.
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - ErrorBanner

/// Inline red error label shown beneath a header area.
struct ErrorBanner: View {
    var message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
            if let retry = onRetry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.07))
    }
}

import SwiftUI

/// Message of the Day card — a subtle, elegant quote widget.
/// Tap to cycle to a new random message.
struct MOTDView: View {
    let message: MOTDMessage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                // Accent left border
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)

                // Emoji
                Text(message.emoji)
                    .font(.title2)
                    .frame(width: 30)
                    .padding(.top, 2)

                // Quote + attribution
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.quote)
                        .font(.body.italic())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text("— \(message.attribution)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(message.category.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Tap for a new message")
    }
}

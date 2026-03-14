import SwiftUI
import AppKit

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

// MARK: - UpdateBanner

/// Accent-colored banner shown when a new app version is available.
struct UpdateBanner: View {
    let update: UpdateService.Release
    @ObservedObject var vm: UpdateViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Boomi SRE \(update.version) is available.")
                .font(.callout)
            Spacer()
            if !update.body.isEmpty {
                Button("Release Notes") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE/releases/latest")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            if vm.isDownloading {
                ProgressView(value: vm.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                Text("\(Int(vm.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if vm.isApplying {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Applying…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Update Now") { Task { await vm.downloadAndApply() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button { vm.dismissBanner() } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.accentColor.opacity(0.2)), alignment: .bottom)
    }
}

import SwiftUI

struct FeedView: View {
    let items: [FeedItem]
    @EnvironmentObject var appState: AppState

    var body: some View {
        if items.isEmpty {
            allClearView
        } else {
            LazyVStack(spacing: 12) {
                let urgent = items.filter { $0.priority <= .high }
                let normal = items.filter { $0.priority == .medium }
                let calm   = items.filter { $0.priority >= .low }

                ForEach(urgent) { item in
                    FeedItemCard(item: item).environmentObject(appState)
                }

                if !urgent.isEmpty && !normal.isEmpty {
                    dividerLabel("Needs Attention")
                }

                ForEach(normal) { item in
                    FeedItemCard(item: item).environmentObject(appState)
                }

                if (!urgent.isEmpty || !normal.isEmpty) && !calm.isEmpty {
                    dividerLabel("All Clear Below")
                }

                ForEach(calm) { item in
                    FeedItemCard(item: item).environmentObject(appState)
                }
            }
        }
    }

    private func dividerLabel(_ text: String) -> some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
        }
        .padding(.vertical, 8)
    }

    private var allClearView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
            Text("All Clear").font(.title2.bold())
            Text("No items need your attention right now.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct FeedItemCard: View {
    let item: FeedItem
    @EnvironmentObject var appState: AppState
    @State private var isActioning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(priorityColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: item.source.icon)
                            .font(.caption)
                            .foregroundStyle(item.source.color)
                        Text(item.source.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(item.source.color)
                        Spacer()
                        Text(item.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.title)
                        .font(.callout.bold())
                        .lineLimit(2)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                    }

                    if !item.actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(item.actions) { feedAction in
                                Button {
                                    isActioning = true
                                    Task {
                                        await feedAction.action()
                                        isActioning = false
                                    }
                                } label: {
                                    Label(feedAction.label, systemImage: feedAction.icon)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(feedAction.style == .destructive ? .red : feedAction.style == .primary ? .accentColor : nil)
                                .disabled(isActioning)
                            }
                            if isActioning { ProgressView().scaleEffect(0.6) }
                            Spacer()
                            if let nav = item.navigateTo {
                                Button {
                                    appState.selectedReport = ReportCatalog.all.first { $0.id == nav }
                                    appState.showSettings = false
                                } label: {
                                    Label("View All", systemImage: "chevron.right")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    item.priority == .critical ? Color.red.opacity(0.4) :
                    item.priority == .high     ? Color.orange.opacity(0.2) :
                    Color.secondary.opacity(0.1)
                )
        )
    }

    private var priorityColor: Color {
        switch item.priority {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .blue
        case .low:      return .green
        case .info:     return .secondary
        }
    }
}

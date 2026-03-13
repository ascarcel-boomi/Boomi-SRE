import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var filter: NotificationFilter = .all
    @State private var expandedNotification: UUID?

    enum NotificationFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case highPriority = "Priority"
    }

    var filteredNotifications: [SRENotification] {
        switch filter {
        case .all:          return notificationVM.notifications
        case .unread:       return notificationVM.notifications.filter { !$0.isRead }
        case .highPriority: return notificationVM.notifications.filter { $0.type.isHighPriority }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            filterBar
            Divider()

            if filteredNotifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Label("Notifications", systemImage: "bell")
                .font(.title3.bold())

            if notificationVM.unreadCount > 0 {
                Text("\(notificationVM.unreadCount) unread")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor).clipShape(Capsule())
            }

            Spacer()

            if notificationVM.isPolling {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Checking…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let last = notificationVM.lastPolled {
                Text("Updated \(last, style: .relative) ago")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Button {
                Task { await notificationVM.pollAllServices(appState: appState) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh now")
            .disabled(notificationVM.isPolling)

            Menu {
                Button("Mark All Read") { notificationVM.markAllRead() }
                Button("Clear Read")    { notificationVM.clearRead() }
                Divider()
                Button(role: .destructive) { notificationVM.clear() } label: {
                    Text("Clear All")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(NotificationFilter.allCases, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    let count: Int = {
                        switch f {
                        case .all:          return notificationVM.notifications.count
                        case .unread:       return notificationVM.unreadCount
                        case .highPriority: return notificationVM.notifications.filter { $0.type.isHighPriority }.count
                        }
                    }()
                    HStack(spacing: 5) {
                        Text(f.rawValue).font(.callout)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(filter == f ? Color.accentColor : Color.secondary.opacity(0.2))
                                .foregroundStyle(filter == f ? .white : .secondary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(filter == f ? Color.accentColor.opacity(0.12) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(filter == f ? Color.accentColor : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Notification List

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredNotifications) { notification in
                    notificationRow(notification)
                    Divider()
                }
            }
        }
    }

    private func notificationRow(_ n: SRENotification) -> some View {
        let isExpanded = expandedNotification == n.id
        return VStack(spacing: 0) {
            Button {
                notificationVM.markRead(n)
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedNotification = isExpanded ? nil : n.id
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Unread indicator
                    Circle()
                        .fill(n.isRead ? Color.clear : n.type.color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    // Icon
                    Image(systemName: n.type.icon)
                        .font(.title3)
                        .foregroundStyle(n.type.color)
                        .frame(width: 28)

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(n.title)
                                .font(.callout.bold())
                                .foregroundStyle(n.isRead ? .secondary : .primary)
                            Spacer()
                            Text(n.relativeTime)
                                .font(.caption2).foregroundStyle(.tertiary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(n.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        // Type chip
                        Text(n.type.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(n.type.color.opacity(0.12))
                            .foregroundStyle(n.type.color)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isExpanded
                        ? Color.accentColor.opacity(0.07)
                        : (n.isRead ? Color.clear : n.type.color.opacity(0.03))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                NotificationDetailPane(notification: n)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: filter == .all ? "bell.slash" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(filter == .all ? Color.secondary : .green)

            Text(filter == .all
                 ? "No notifications yet"
                 : "No \(filter.rawValue.lowercased()) notifications")
                .font(.headline).foregroundStyle(.secondary)

            if filter == .all {
                Text("Notifications appear here when tickets are assigned, builds fail, alerts fire, or briefings are generated.")
                    .font(.callout).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Button {
                    Task { await notificationVM.pollAllServices(appState: appState) }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(notificationVM.isPolling)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Navigation Helper

    private func navigateTo(_ reportId: String) {
        appState.showSettings = false
        appState.selectedTicketKey = nil
        appState.selectedReport = ReportCatalog.all.first { $0.id == reportId }
    }
}

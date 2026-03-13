import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var filter: NotificationFilter = .all
    @State private var expandedNotification: UUID?
    @State private var groupByService = false

    // MARK: - Filter

    enum NotificationFilter: String, CaseIterable {
        case all           = "All"
        case unread        = "Unread"
        case highPriority  = "Priority"
        case jira          = "Jira"
        case jenkins       = "Jenkins"
        case grafana       = "Grafana"
        case github        = "GitHub"
        case confluence    = "Confluence"
        case briefings     = "Briefings"

        var icon: String {
            switch self {
            case .all:          return "tray.full"
            case .unread:       return "envelope.badge"
            case .highPriority: return "exclamationmark.triangle"
            case .jira:         return "ticket"
            case .jenkins:      return "gearshape.2"
            case .grafana:      return "bell.badge"
            case .github:       return "arrow.triangle.pull"
            case .confluence:   return "doc.text.fill"
            case .briefings:    return "doc.text"
            }
        }
    }

    var filteredNotifications: [SRENotification] {
        let all = notificationVM.notifications
        switch filter {
        case .all:          return all
        case .unread:       return all.filter { !$0.isRead }
        case .highPriority: return all.filter { $0.type.isHighPriority }
        case .jira:         return all.filter { $0.type == .jiraAssigned || $0.type == .jiraStatusChange }
        case .jenkins:      return all.filter { $0.type == .jenkinsBuildFailed || $0.type == .jenkinsBuildRecovered }
        case .grafana:      return all.filter { $0.type == .grafanaAlertFiring || $0.type == .grafanaAlertResolved }
        case .github:       return all.filter { $0.type == .githubPRReview || $0.type == .githubPRMerged || $0.type == .githubWorkflowFailed }
        case .confluence:   return all.filter { $0.type == .confluencePageUpdated }
        case .briefings:    return all.filter { $0.type == .briefingGenerated }
        }
    }

    func countFor(_ f: NotificationFilter) -> Int {
        let all = notificationVM.notifications
        switch f {
        case .all:          return all.count
        case .unread:       return notificationVM.unreadCount
        case .highPriority: return all.filter { $0.type.isHighPriority }.count
        case .jira:         return all.filter { $0.type == .jiraAssigned || $0.type == .jiraStatusChange }.count
        case .jenkins:      return all.filter { $0.type == .jenkinsBuildFailed || $0.type == .jenkinsBuildRecovered }.count
        case .grafana:      return all.filter { $0.type == .grafanaAlertFiring || $0.type == .grafanaAlertResolved }.count
        case .github:       return all.filter { $0.type == .githubPRReview || $0.type == .githubPRMerged || $0.type == .githubWorkflowFailed }.count
        case .confluence:   return all.filter { $0.type == .confluencePageUpdated }.count
        case .briefings:    return all.filter { $0.type == .briefingGenerated }.count
        }
    }

    // MARK: - Time Grouping

    enum TimeGroup: String {
        case today      = "Today"
        case yesterday  = "Yesterday"
        case thisWeek   = "This Week"
        case older      = "Older"
    }

    func timeGroup(for date: Date) -> TimeGroup {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        if date > weekAgo              { return .thisWeek }
        return .older
    }

    var groupedByTime: [(TimeGroup, [SRENotification])] {
        let order: [TimeGroup] = [.today, .yesterday, .thisWeek, .older]
        let grouped = Dictionary(grouping: filteredNotifications) { timeGroup(for: $0.timestamp) }
        return order.compactMap { g in
            guard let items = grouped[g], !items.isEmpty else { return nil }
            return (g, items)
        }
    }

    var groupedByServiceList: [(String, [SRENotification])] {
        let serviceLabel: (SRENotification) -> String = { n in
            switch n.type {
            case .jiraAssigned, .jiraStatusChange:                         return "Jira"
            case .jenkinsBuildFailed, .jenkinsBuildRecovered:              return "Jenkins"
            case .grafanaAlertFiring, .grafanaAlertResolved:               return "Grafana"
            case .githubPRReview, .githubPRMerged, .githubWorkflowFailed:  return "GitHub"
            case .confluencePageUpdated:                                    return "Confluence"
            case .briefingGenerated:                                        return "Briefings"
            case .awsCostAnomaly:                                           return "AWS"
            }
        }
        let serviceOrder = ["Jira", "Jenkins", "Grafana", "GitHub", "Confluence", "Briefings", "AWS"]
        let grouped = Dictionary(grouping: filteredNotifications, by: serviceLabel)
        return serviceOrder.compactMap { s in
            guard let items = grouped[s], !items.isEmpty else { return nil }
            return (s, items)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            summaryBar
            filterChips
            Divider()

            if filteredNotifications.isEmpty {
                emptyState
            } else if groupByService {
                groupedServiceList
            } else {
                groupedTimeList
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
                Toggle("Group by Service", isOn: $groupByService)
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

    // MARK: - Summary Bar

    private var summaryBar: some View {
        let total   = notificationVM.notifications.count
        let unread  = notificationVM.unreadCount
        let high    = notificationVM.notifications.filter { $0.type.isHighPriority }.count

        return HStack(spacing: 12) {
            summaryChip(count: total,  label: "total",    color: .secondary)
            summaryChip(count: unread, label: "unread",   color: Color.accentColor)
            summaryChip(count: high,   label: "priority", color: .red)
            Spacer()
            if groupByService {
                Text("grouped by service").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("grouped by time").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)").font(.caption.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Chips (scrollable)

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NotificationFilter.allCases, id: \.self) { f in
                    let count = countFor(f)
                    let isSelected = filter == f
                    Button { filter = f } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.icon).font(.caption2)
                            Text(f.rawValue).font(.caption.bold())
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    // MARK: - Grouped Time List

    private var groupedTimeList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedByTime, id: \.0) { group, items in
                    Section {
                        ForEach(items) { notification in
                            notificationRow(notification)
                            Divider()
                        }
                    } header: {
                        timeGroupHeader(group.rawValue, count: items.count)
                    }
                }
            }
        }
    }

    // MARK: - Grouped Service List

    private var groupedServiceList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedByServiceList, id: \.0) { service, items in
                    Section {
                        ForEach(items) { notification in
                            notificationRow(notification)
                            Divider()
                        }
                    } header: {
                        timeGroupHeader(service, count: items.count)
                    }
                }
            }
        }
    }

    private func timeGroupHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.bold())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.97))
    }

    // MARK: - Notification Row

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
}

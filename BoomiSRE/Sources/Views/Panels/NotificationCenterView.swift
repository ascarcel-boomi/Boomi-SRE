import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var filter: NotificationFilter = .all
    @State private var expandedNotification: UUID?
    @State private var groupByService = false
    @State private var archiveExpanded = false

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

    // MARK: - Filtering (active only)

    var filteredNotifications: [SRENotification] {
        let active = notificationVM.activeNotifications
        switch filter {
        case .all:          return active
        case .unread:       return active.filter { !$0.isRead }
        case .highPriority: return active.filter { $0.type.isHighPriority }
        case .jira:         return active.filter { $0.type == .jiraAssigned || $0.type == .jiraStatusChange }
        case .jenkins:      return active.filter { $0.type == .jenkinsBuildFailed || $0.type == .jenkinsBuildRecovered }
        case .grafana:      return active.filter { $0.type == .grafanaAlertFiring || $0.type == .grafanaAlertResolved }
        case .github:       return active.filter { $0.type == .githubPRReview || $0.type == .githubPRMerged || $0.type == .githubWorkflowFailed }
        case .confluence:   return active.filter { $0.type == .confluencePageUpdated }
        case .briefings:    return active.filter { $0.type == .briefingGenerated }
        }
    }

    func countFor(_ f: NotificationFilter) -> Int {
        let active = notificationVM.activeNotifications
        switch f {
        case .all:          return active.count
        case .unread:       return notificationVM.unreadCount
        case .highPriority: return active.filter { $0.type.isHighPriority }.count
        case .jira:         return active.filter { $0.type == .jiraAssigned || $0.type == .jiraStatusChange }.count
        case .jenkins:      return active.filter { $0.type == .jenkinsBuildFailed || $0.type == .jenkinsBuildRecovered }.count
        case .grafana:      return active.filter { $0.type == .grafanaAlertFiring || $0.type == .grafanaAlertResolved }.count
        case .github:       return active.filter { $0.type == .githubPRReview || $0.type == .githubPRMerged || $0.type == .githubWorkflowFailed }.count
        case .confluence:   return active.filter { $0.type == .confluencePageUpdated }.count
        case .briefings:    return active.filter { $0.type == .briefingGenerated }.count
        }
    }

    // MARK: - Time Grouping

    enum TimeGroup: String {
        case today     = "Today"
        case yesterday = "Yesterday"
        case thisWeek  = "This Week"
        case older     = "Older"
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

            projectFilterHint
            if filteredNotifications.isEmpty && notificationVM.archivedNotifications.isEmpty {
                emptyState
            } else {
                mainList
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
                Button("Mark All Read")  { notificationVM.markAllRead() }
                Button("Archive Read")   { notificationVM.archiveRead() }
                Divider()
                Toggle("Group by Service", isOn: $groupByService)
                Divider()
                Button("Clear Archive")  { notificationVM.clearArchive() }
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
        let total    = notificationVM.activeNotifications.count
        let unread   = notificationVM.unreadCount
        let high     = notificationVM.activeNotifications.filter { $0.type.isHighPriority }.count
        let archived = notificationVM.archivedNotifications.count

        return HStack(spacing: 12) {
            summaryChip(count: total,    label: "active",   color: .secondary)
            summaryChip(count: unread,   label: "unread",   color: Color.accentColor)
            summaryChip(count: high,     label: "priority", color: .red)
            if archived > 0 {
                summaryChip(count: archived, label: "archived", color: .secondary)
            }
            Spacer()
            if groupByService {
                Text("by service").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("by time").font(.caption2).foregroundStyle(.tertiary)
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

    // MARK: - Project filter hint

    @ViewBuilder
    private var projectFilterHint: some View {
        let projects = appState.favoriteJiraProjects
        if !projects.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Showing notifications for your projects: \(projects.joined(separator: ", ")). Change in ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Profile") {
                    appState.showSettings = true
                    NotificationCenter.default.post(name: .openSettingsProfileTab, object: nil)
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.05))
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

    // MARK: - Main List (active + archive section)

    private var mainList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Active notifications grouped by time or service
                if groupByService {
                    ForEach(groupedByServiceList, id: \.0) { service, items in
                        Section {
                            ForEach(items) { n in notificationRow(n); Divider() }
                        } header: {
                            groupHeader(service, count: items.count, muted: false)
                        }
                    }
                } else {
                    ForEach(groupedByTime, id: \.0) { group, items in
                        Section {
                            ForEach(items) { n in notificationRow(n); Divider() }
                        } header: {
                            groupHeader(group.rawValue, count: items.count, muted: false)
                        }
                    }
                }

                // Archive section
                let archived = notificationVM.archivedNotifications
                if !archived.isEmpty {
                    Section {
                        if archiveExpanded {
                            ForEach(archived) { n in archivedRow(n); Divider() }
                            Button("Clear Archive") { notificationVM.clearArchive() }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                        }
                    } header: {
                        archiveSectionHeader(count: archived.count)
                    }
                }
            }
        }
    }

    // MARK: - Section Headers

    private func groupHeader(_ title: String, count: Int, muted: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(muted ? .tertiary : .secondary)
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

    private func archiveSectionHeader(count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { archiveExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.caption).foregroundStyle(.tertiary)
                Text("Archived")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                Text("· \(notificationVM.archiveRetention.rawValue)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: archiveExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.97))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notification Row (active)

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
                    Circle()
                        .fill(n.isRead ? Color.clear : n.type.color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                    Image(systemName: n.type.icon)
                        .font(.title3)
                        .foregroundStyle(n.type.color)
                        .frame(width: 28)
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

    // MARK: - Archived Row (muted, no inline detail)

    private func archivedRow(_ n: SRENotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: n.type.icon)
                .font(.subheadline)
                .foregroundStyle(n.type.color.opacity(0.5))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(n.title)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(n.relativeTime)
                        .font(.caption2).foregroundStyle(.quaternary)
                }
                Text(n.body)
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("No notifications yet")
                .font(.headline).foregroundStyle(.secondary)
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
            Spacer()
        }
        .padding()
    }
}

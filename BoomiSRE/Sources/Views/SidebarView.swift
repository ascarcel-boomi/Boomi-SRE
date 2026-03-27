import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var presenceVM: TeamPresenceViewModel
    @State private var showPresencePopover = false

    struct SidebarItemDef: Identifiable {
        let id: String
        let icon: String
        let label: String
        let description: String
    }

    private let items: [SidebarItemDef] = [
        SidebarItemDef(id: "home",        icon: "house",                          label: "Home",             description: "Your intelligent feed"),
        SidebarItemDef(id: "alerts",      icon: "bell.badge",                     label: "Alerts & On-Call", description: "On-call, Grafana, SLOs, notifications"),
        SidebarItemDef(id: "incidents",   icon: "exclamationmark.shield",         label: "Incidents",        description: "Active and recent incidents"),
        SidebarItemDef(id: "mywork",      icon: "checklist",                      label: "My Work",          description: "Tickets, builds, boards"),
        SidebarItemDef(id: "infra",       icon: "server.rack",                    label: "Infrastructure",   description: "AWS, GitHub, Bitbucket"),
        SidebarItemDef(id: "knowledge",   icon: "book.closed",                    label: "Knowledge & Tools",description: "SOPs, Confluence, AI Copilot, Skills"),
        SidebarItemDef(id: "communicate", icon: "bubble.left.and.bubble.right",   label: "Communicate",      description: "Gmail, Calendar"),
    ]

    var body: some View {
        if appState.sidebarCollapsed {
            collapsedSidebar
        } else {
            expandedSidebar
        }
    }

    // MARK: - Collapsed

    private var collapsedSidebar: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        collapsedIconButton(
                            icon: item.icon,
                            help: item.label,
                            isSelected: isSelected(item),
                            badge: badge(for: item)
                        ) { selectItem(item) }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            collapsedIconButton(icon: "gear", help: "Settings", isSelected: appState.showSettings) {
                appState.selectedReport = nil
                appState.showSettings = true
            }
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func collapsedIconButton(icon: String, help: String, isSelected: Bool = false, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? appState.themeAccent : Color.secondary)
                    .frame(width: 44, height: 32)
                    .background(isSelected ? appState.themeAccent.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 9).bold())
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(badge > 0 ? "\(help), \(badge) unread" : help)
    }

    // MARK: - Expanded

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            // Header row: collapse + Home
            HStack {
                Spacer()
                Text("Boomi SRE").font(.headline).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        sidebarRow(item)
                    }
                }
                .padding(.vertical, 6).padding(.horizontal, 6)
            }

            // Team Presence indicator
            if appState.peerPresenceEnabled {
                Divider()
                Button { showPresencePopover.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(presenceVM.onlineCount > 0 ? .green : .secondary)
                        Text("Team")
                            .font(.caption)
                        Spacer()
                        if presenceVM.onlineCount > 0 {
                            Text("\(presenceVM.onlineCount)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPresencePopover) {
                    TeamPresencePopover()
                }
            }

            Divider()

            // Footer: avatar + Settings
            HStack(spacing: 0) {
                Button {
                    appState.selectedReport = nil
                    appState.showSettings = true
                    NotificationCenter.default.post(name: .openSettingsProfileTab, object: nil)
                } label: {
                    Group {
                        if let urlStr = appState.userProfile.avatarURL,
                           let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.circle.fill").resizable().foregroundStyle(appState.themeAccent)
                                }
                            }
                        } else {
                            Image(systemName: "person.circle.fill").resizable().foregroundStyle(appState.themeAccent)
                        }
                    }
                    .frame(width: 24, height: 24).clipShape(Circle())
                }
                .buttonStyle(.plain).padding(.leading, 12).padding(.vertical, 10)
                .help(appState.userProfile.displayName.isEmpty ? "Profile" : appState.userProfile.displayName)

                Spacer()

                Button {
                    appState.selectedReport = nil
                    appState.showSettings = true
                } label: {
                    Label { Text("Settings").font(.body) } icon: {
                        Image(systemName: "gear").foregroundStyle(appState.themeAccent)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(appState.showSettings ? appState.themeAccent.opacity(0.1) : Color.clear)
                .cornerRadius(6)
                .padding(.trailing, 6)
            }
            .padding(.bottom, 6)
        }
        .onChange(of: appState.selectedReport) {
            if appState.selectedReport != nil {
                appState.showSettings = false
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItemDef) -> some View {
        Button { selectItem(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .foregroundStyle(isSelected(item) ? appState.themeAccent : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.label).font(.body)
                        Spacer()
                        let b = badge(for: item)
                        if b > 0 {
                            Text("\(min(b, 99))")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.red).clipShape(Capsule())
                        }
                    }
                    Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected(item) ? appState.themeAccent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func isSelected(_ item: SidebarItemDef) -> Bool {
        guard !appState.showSettings else { return false }
        if appState.selectedReport != nil { return false }
        return appState.selectedSidebarItem == item.id
    }

    private func selectItem(_ item: SidebarItemDef) {
        appState.selectedReport = nil
        appState.showSettings = false
        appState.selectedSidebarItem = item.id
        appState.saveConfig()
    }

    private func badge(for item: SidebarItemDef) -> Int {
        switch item.id {
        case "alerts":    return notificationVM.unreadCount
        case "incidents": return appState.activeIncidentCount
        default:          return 0
        }
    }
}

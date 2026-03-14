import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var collapsedSections: Set<String> = []

    var body: some View {
        if appState.sidebarCollapsed {
            collapsedSidebar
        } else {
            expandedSidebar
        }
    }

    // MARK: - Collapsed (icon-only strip)

    private var collapsedSidebar: some View {
        VStack(spacing: 0) {
            // Expand button
            Button { appState.sidebarCollapsed = false } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .help("Expand Sidebar")

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    // Home
                    collapsedIconButton(
                        icon: "house",
                        help: "Home",
                        isSelected: appState.selectedReport == nil && !appState.showSettings
                    ) {
                        appState.selectedReport = nil
                        appState.showSettings = false
                    }

                    // Collapsed: one icon per section, all items visible on hover
                    ForEach(ReportSection.allCases, id: \.self) { section in
                        Divider().padding(.vertical, 2)
                        ForEach(ReportCatalog.reports(for: section)) { report in
                            collapsedIconButton(
                                icon: report.icon,
                                help: report.title,
                                isSelected: appState.selectedReport == report
                            ) {
                                appState.selectedReport = report
                                appState.showSettings = false
                            }
                        }
                    }

                }
                .padding(.vertical, 4)
            }

            Divider()

            // Pinned Settings footer (collapsed mode)
            collapsedIconButton(
                icon: "gear",
                help: "Settings",
                isSelected: appState.showSettings
            ) {
                appState.selectedReport = nil
                appState.showSettings = true
            }
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func collapsedIconButton(
        icon: String,
        help: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 44, height: 32)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Expanded sidebar

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $appState.selectedReport) {
                // Collapse + Home row
                HStack {
                    Button { appState.sidebarCollapsed = true } label: {
                        Image(systemName: "sidebar.left")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse Sidebar")

                    Button {
                        appState.selectedReport = nil
                        appState.showSettings = false
                    } label: {
                        Label {
                            Text("Home")
                        } icon: {
                            Image(systemName: "house").foregroundStyle(Color.accentColor)
                        }
                        .font(.body.bold())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                .listRowSeparator(.hidden)

                // ── COMMAND CENTER ────────────────────────────────────────
                collapsibleSectionHeader(ReportSection.commandCenter.rawValue, icon: ReportSection.commandCenter.icon)
                if !collapsedSections.contains(ReportSection.commandCenter.rawValue) {
                    ForEach(ReportCatalog.reports(for: .commandCenter)) { report in
                        aiRow(report).tag(report)
                    }
                }

                // ── WORK ──────────────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.work.rawValue, icon: ReportSection.work.icon,
                    status: appState.jiraAuthStatus,
                    retryAction: { retryService("jira") })
                if !collapsedSections.contains(ReportSection.work.rawValue) {
                    ForEach(ReportCatalog.reports(for: .work)) { report in
                        standardRow(report).tag(report)
                    }
                }

                // ── INFRASTRUCTURE ────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.infrastructure.rawValue, icon: ReportSection.infrastructure.icon,
                    status: appState.awsAuthStatus,
                    retryAction: { retryService("aws") })
                if !collapsedSections.contains(ReportSection.infrastructure.rawValue) {
                    ForEach(ReportCatalog.reports(for: .infrastructure)) { report in
                        standardRow(report).tag(report)
                    }
                }

                // ── OBSERVABILITY ─────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.observability.rawValue, icon: ReportSection.observability.icon,
                    status: appState.grafanaAuthStatus,
                    retryAction: { retryService("grafana") })
                if !collapsedSections.contains(ReportSection.observability.rawValue) {
                    ForEach(ReportCatalog.reports(for: .observability)) { report in
                        servicesRow(report).tag(report)
                    }
                }

                // ── SOURCE CONTROL ────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.sourceControl.rawValue, icon: ReportSection.sourceControl.icon,
                    status: compositeStatus([appState.githubAuthStatus, appState.bitbucketAuthStatus]),
                    retryAction: { retryService("github") })
                if !collapsedSections.contains(ReportSection.sourceControl.rawValue) {
                    ForEach(ReportCatalog.reports(for: .sourceControl)) { report in
                        servicesRow(report).tag(report)
                    }
                }

                // ── AUTOMATION ────────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.automation.rawValue, icon: ReportSection.automation.icon,
                    status: appState.jenkinsAuthStatus,
                    retryAction: { retryService("jenkins") })
                if !collapsedSections.contains(ReportSection.automation.rawValue) {
                    ForEach(ReportCatalog.reports(for: .automation)) { report in
                        servicesRow(report).tag(report)
                    }
                }

                // ── KNOWLEDGE ─────────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.knowledge.rawValue, icon: ReportSection.knowledge.icon,
                    status: compositeStatus([appState.confluenceAuthStatus, appState.githubAuthStatus]),
                    retryAction: { retryService("confluence") })
                if !collapsedSections.contains(ReportSection.knowledge.rawValue) {
                    ForEach(ReportCatalog.reports(for: .knowledge)) { report in
                        servicesRow(report).tag(report)
                    }
                }

                // ── COMMUNICATION ─────────────────────────────────────────
                collapsibleSectionHeaderWithStatus(ReportSection.communication.rawValue, icon: ReportSection.communication.icon,
                    status: appState.googleAuthStatus,
                    retryAction: { retryService("google") })
                if !collapsedSections.contains(ReportSection.communication.rawValue) {
                    ForEach(ReportCatalog.reports(for: .communication)) { report in
                        standardRow(report).tag(report)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Boomi SRE")
            .onChange(of: appState.selectedReport) {
                if appState.selectedReport != nil {
                    appState.showSettings = false
                }
            }

            Divider()

            // Pinned footer — Profile + Settings
            HStack(spacing: 0) {
                // Avatar / profile button
                Button {
                    appState.selectedReport = nil
                    appState.showSettings = true
                    // Navigate settings to profile tab via notification
                    NotificationCenter.default.post(name: .openSettingsProfileTab, object: nil)
                } label: {
                    Group {
                        if let urlStr = appState.userProfile.avatarURL,
                           let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.vertical, 10)
                .help(appState.userProfile.displayName.isEmpty ? "Profile" : appState.userProfile.displayName)

                Spacer()

                Button {
                    appState.selectedReport = nil
                    appState.showSettings = true
                } label: {
                    Label {
                        Text("Settings").font(.body)
                    } icon: {
                        Image(systemName: "gear").foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(appState.showSettings ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
                .padding(.trailing, 6)
            }
            .padding(.bottom, 6)
        }
    }

    /// Simple collapsible header (no auth status dot).
    private func collapsibleSectionHeader(_ title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsedSections.contains(title) {
                    collapsedSections.remove(title)
                } else {
                    collapsedSections.insert(title)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsedSections.contains(title) ? 0 : 90))
                    .animation(.easeInOut(duration: 0.15), value: collapsedSections.contains(title))
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    /// Collapsible header with auth status dot + context menu.
    private func collapsibleSectionHeaderWithStatus(
        _ title: String,
        icon: String,
        status: AuthStatus,
        retryAction: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsedSections.contains(title) {
                    collapsedSections.remove(title)
                } else {
                    collapsedSections.insert(title)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsedSections.contains(title) ? 0 : 90))
                    .animation(.easeInOut(duration: 0.15), value: collapsedSections.contains(title))
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                if case .checking = status {
                    ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                } else {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button { retryAction() } label: {
                Label("Re-check Connection", systemImage: "arrow.clockwise")
            }
            Button { goToSettings() } label: {
                Label("Open Settings", systemImage: "gear")
            }
        }
    }

    // MARK: - Row Builders

    private func aiRow(_ report: ReportItem) -> some View {
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.body)
                        .foregroundStyle(report.id == "incidents" && appState.activeIncidentCount > 0 ? .red : .primary)
                    Text(report.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if report.id == "incidents" && appState.activeIncidentCount > 0 {
                    Text("\(appState.activeIncidentCount)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.red).clipShape(Capsule())
                }
                if report.id == "notifications" && notificationVM.unreadCount > 0 {
                    Text("\(notificationVM.unreadCount)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.accentColor).clipShape(Capsule())
                }
                if report.id == "exec_assistant" && appState.unreadBriefingCount > 0 {
                    Text("\(appState.unreadBriefingCount)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.accentColor).clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: report.icon).foregroundStyle(Color.accentColor)
        }
    }

    private func standardRow(_ report: ReportItem) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title).font(.body)
                Text(report.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: report.icon).foregroundStyle(Color.accentColor)
        }
    }

    private func servicesRow(_ report: ReportItem) -> some View {
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title).font(.body)
                    Text(report.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                let status = serviceStatus(for: report.id)
                if case .checking = status {
                    ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                } else {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: report.icon).foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Auth button for services without features

    private func authButton(label: String, status: AuthStatus, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: 6) {
                if case .checking = status {
                    ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                } else {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                }
                Text(label).font(.caption)
                Spacer()
                Text(statusSummary(status)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(status.isOK ? "Click to re-check" : "Click to retry or configure")
        .contextMenu {
            Button { action() } label: {
                Label("Re-check Connection", systemImage: "arrow.clockwise")
            }
            Button { goToSettings() } label: {
                Label("Open Settings", systemImage: "gear")
            }
            Divider()
            Button(role: .destructive) {
                disconnect(label.lowercased())
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .disabled(status == .notConfigured)
        }
    }

    // MARK: - Helpers

    private let awsAuth = AWSAuthService()

    private func navigateTo(_ reportId: String) {
        appState.showSettings = false
        appState.selectedReport = ReportCatalog.all.first { $0.id == reportId }
    }

    private func retryService(_ service: String) {
        switch service {
        case "aws":
            if appState.awsSSOProfile.isEmpty { goToSettings(); return }
            retryAWS()
            return
        case "jira":
            if !appState.isJiraConfigured { goToSettings(); return }
        case "confluence":
            if appState.confluenceAPIToken.isEmpty { goToSettings(); return }
        case "bitbucket":
            if appState.bitbucketAPIToken.isEmpty { goToSettings(); return }
        case "github":
            if appState.githubToken.isEmpty { goToSettings(); return }
        case "jenkins":
            if appState.jenkinsToken.isEmpty { goToSettings(); return }
        case "grafana":
            if appState.grafanaToken.isEmpty { goToSettings(); return }
        case "google":
            if appState.googleCredentials == nil { goToSettings(); return }
        default: break
        }
        appState.checkAllServices()
    }

    private func retryAWS() {
        appState.awsAuthStatus = .checking
        Task {
            do {
                let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
            } catch {
                await MainActor.run {
                    appState.awsAuthStatus = .expired
                    openSSOStartPage()
                }
                do {
                    _ = try await awsAuth.login(profile: appState.awsSSOProfile)
                    let detail = try await awsAuth.checkStatus(profile: appState.awsSSOProfile)
                    await MainActor.run { appState.awsAuthStatus = .authenticated(detail: detail) }
                } catch {
                    await MainActor.run { appState.awsAuthStatus = .expired }
                }
            }
        }
    }

    private func disconnect(_ service: String) {
        switch service {
        case "aws":
            appState.awsAuthStatus = .expired
            Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: AWSAuthService.resolvedAWSPath)
                process.arguments = ["sso", "logout", "--profile", appState.awsSSOProfile]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                try? process.run()
                process.waitUntilExit()
            }
        case "jira":
            appState.jiraAPIToken = ""
            appState.jiraAuthStatus = .notConfigured
        case "confluence":
            appState.confluenceAPIToken = ""
            appState.confluenceAuthStatus = .notConfigured
        case "bitbucket":
            appState.bitbucketAPIToken = ""
            appState.bitbucketAuthStatus = .notConfigured
        case "github":
            appState.githubToken = ""
            appState.githubAuthStatus = .notConfigured
        case "jenkins":
            appState.jenkinsToken = ""
            appState.jenkinsAuthStatus = .notConfigured
        case "grafana":
            appState.grafanaToken = ""
            appState.grafanaAuthStatus = .notConfigured
        default: break
        }
    }

    private func openSSOStartPage() {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")
        if let content = try? String(contentsOf: configPath, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("sso_start_url") && trimmed.contains("=") {
                    let url = trimmed.components(separatedBy: "=")
                        .dropFirst().joined(separator: "=")
                        .trimmingCharacters(in: .whitespaces)
                    if let ssoURL = URL(string: url) {
                        NSWorkspace.shared.open(ssoURL)
                        return
                    }
                }
            }
        }
    }

    private func goToSettings() {
        appState.selectedReport = nil
        appState.showSettings = true
    }

    private func serviceStatus(for reportId: String) -> AuthStatus {
        switch reportId {
        case "github_browser":     return appState.githubAuthStatus
        case "jenkins_browser":    return appState.jenkinsAuthStatus
        case "grafana_browser":    return appState.grafanaAuthStatus
        case "confluence_browser": return appState.confluenceAuthStatus
        case "bitbucket_browser":  return appState.bitbucketAuthStatus
        default: return .unknown
        }
    }

    /// Returns the worst auth status from a set (error > expired > checking > unknown > notConfigured > authenticated).
    private func compositeStatus(_ statuses: [AuthStatus]) -> AuthStatus {
        for s in statuses { if case .error = s { return s } }
        if statuses.contains(where: { if case .expired = $0 { return true }; return false }) { return .expired }
        if statuses.contains(where: { if case .checking = $0 { return true }; return false }) { return .checking }
        if statuses.allSatisfy({ if case .authenticated = $0 { return true }; return false }) { return .authenticated(detail: "") }
        if statuses.allSatisfy({ if case .notConfigured = $0 { return true }; return false }) { return .notConfigured }
        return .unknown
    }

    private func statusSummary(_ status: AuthStatus) -> String {
        switch status {
        case .authenticated: return "Connected"
        case .expired:       return "Expired"
        case .checking:      return "Checking..."
        case .notConfigured: return "Not configured"
        case .error:         return "Error"
        case .unknown:       return "-"
        }
    }
}

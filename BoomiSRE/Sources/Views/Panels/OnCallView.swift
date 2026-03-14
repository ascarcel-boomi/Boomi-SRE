import SwiftUI
import WebKit

// MARK: - Alert Filter (local enum — drives WebView URL, not API)

enum AlertWebFilter: String, CaseIterable, Identifiable {
    case all           = "All Alerts"
    case assignedToMe  = "Assigned to Me"
    case unacknowledged = "Unacknowledged"
    case closed        = "Closed"
    var id: String { rawValue }
}

// MARK: - Main View

struct OnCallView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = OnCallViewModel()

    @State private var alertFilter: AlertWebFilter = .all
    @State private var alertWebLoading = false
    @State private var showAlertSSO = false
    @State private var resolvedAccountId: String = ""   // cached for "Assigned to Me"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-Call").font(.title2.bold())
                    if let last = vm.lastFetched {
                        Text("Last refreshed: \(last, format: .dateTime)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if vm.isLoadingTeams || vm.isLoadingOnCall {
                    ProgressView().scaleEffect(0.8)
                }
                Button {
                    Task { await vm.load(appState: appState) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoadingTeams || vm.isLoadingOnCall)

                Button {
                    appState.showSettings = true
                    appState.selectedReport = nil
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .help("Configure favorite teams in Settings → JSM")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            if !appState.isJiraConfigured {
                jiraNotConfiguredPrompt
            } else {
                if let error = vm.error {
                    errorBanner(error)
                }
                // VSplitView: on-call cards (top) + alerts WebView (bottom)
                VSplitView {
                    ScrollView {
                        onCallSection.padding(20)
                    }
                    .frame(minHeight: 180)

                    alertsWebSection
                        .frame(minHeight: 300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if vm.teams.isEmpty && appState.isJiraConfigured {
                Task { await vm.load(appState: appState) }
            }
            Task { await fetchAccountIdIfNeeded() }
        }
    }

    // MARK: - Account ID (for "Assigned to Me" filter)

    private func fetchAccountIdIfNeeded() async {
        // Use cached profile value if available
        if let id = appState.userProfile.jiraAccountId, !id.isEmpty {
            resolvedAccountId = id; return
        }
        guard appState.isJiraConfigured else { return }
        // Fetch from Jira /rest/api/3/myself
        let clean = appState.jiraBaseURL.hasSuffix("/") ? String(appState.jiraBaseURL.dropLast()) : appState.jiraBaseURL
        guard let url = URL(string: "\(clean)/rest/api/3/myself") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let data = "\(appState.jiraEmail):\(appState.jiraAPIToken)".data(using: .utf8) {
            req.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountId = json["accountId"] as? String else { return }
        resolvedAccountId = accountId
        // Cache it in the user profile
        appState.userProfile.jiraAccountId = accountId
    }

    // MARK: - Alert URL builder

    private func alertURL(for filter: AlertWebFilter) -> URL {
        let base = appState.jiraBaseURL.hasSuffix("/") ? String(appState.jiraBaseURL.dropLast()) : appState.jiraBaseURL
        switch filter {
        case .all:
            return URL(string: "\(base)/jira/ops/alerts")!
        case .assignedToMe:
            let id = resolvedAccountId
            guard !id.isEmpty else { return URL(string: "\(base)/jira/ops/alerts")! }
            let raw = "owner: \"\(id)\""
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "\(base)/jira/ops/alerts?view=list&query=\(encoded)")
                ?? URL(string: "\(base)/jira/ops/alerts")!
        case .unacknowledged:
            let raw = "status: \"open\" AND acknowledged: false"
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "\(base)/jira/ops/alerts?view=list&query=\(encoded)")
                ?? URL(string: "\(base)/jira/ops/alerts")!
        case .closed:
            let raw = "status: \"closed\""
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "\(base)/jira/ops/alerts?view=list&query=\(encoded)")
                ?? URL(string: "\(base)/jira/ops/alerts")!
        }
    }

    // MARK: - Alerts WebView Section

    private var alertsWebSection: some View {
        VStack(spacing: 0) {
            // Header + filter picker
            HStack {
                Image(systemName: "bell.badge").foregroundStyle(.orange)
                Text("Alerts").font(.headline)
                Spacer()
                if alertWebLoading { ProgressView().scaleEffect(0.7) }
                Picker("Filter", selection: $alertFilter) {
                    ForEach(AlertWebFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // SSO hint banner
            if showAlertSSO {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key").foregroundStyle(.orange)
                    Text("Sign in with your Okta credentials. You only need to do this once.")
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { showAlertSSO = false }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                Divider()
            }

            // WebView
            AlertsWebView(
                url: alertURL(for: alertFilter),
                isLoading: $alertWebLoading,
                showSSO: $showAlertSSO
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Open in browser footer
            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(alertURL(for: alertFilter))
                } label: {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(RoundedRectangle(cornerRadius: 0).fill(.background))
    }

    // MARK: - Jira not configured prompt

    private var jiraNotConfiguredPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "ticket").font(.system(size: 48)).foregroundStyle(Color.accentColor.opacity(0.7))
            Text("Jira Required for On-Call").font(.title3.bold())
            Text("On-Call schedules use your Jira credentials — the same token you use for tickets and boards.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            VStack(alignment: .leading, spacing: 8) {
                Label("Who's currently on call for your schedules", systemImage: "person.crop.circle.badge.clock")
                Label("On-call schedule rotations", systemImage: "calendar.badge.clock")
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
            Button {
                appState.showSettings = true
                appState.selectedSettingsTab = "jira"
            } label: {
                Label("Configure Jira", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(40)
    }

    // MARK: - On-Call Section

    private var onCallSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "phone.badge.waveform").foregroundStyle(Color.accentColor)
                Text("Who's On-Call").font(.headline)
                Spacer()
                if vm.isLoadingOnCall { ProgressView().scaleEffect(0.7) }
            }

            if appState.favoriteJSMTeams.isEmpty {
                noFavoriteTeamsPrompt
            } else if vm.teams.isEmpty && !vm.isLoadingTeams {
                HStack(spacing: 8) {
                    Text("No schedules found. Check that your team has schedules configured.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { appState.showSettings = true; appState.selectedSettingsTab = "jsm" } label: {
                        Text("Settings").font(.caption)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                let favTeams = vm.teams.filter { appState.favoriteJSMTeams.contains($0.id) }
                if favTeams.isEmpty {
                    HStack(spacing: 8) {
                        Text("Select your favorite schedules in Settings → JSM Operations to see on-call information.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button { appState.showSettings = true; appState.selectedSettingsTab = "jsm" } label: {
                            Text("Open Settings").font(.caption)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(favTeams) { team in onCallCard(team) }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func onCallCard(_ team: OpsTeam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(team.name).font(.callout.bold())
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://\(appState.jiraBaseURL.replacingOccurrences(of: "https://", with: ""))/jira/ops/overview")!)
                } label: {
                    Label("JSM", systemImage: "safari").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }

            let teamSchedules = vm.allSchedules.filter { $0.teamId == team.id }

            if teamSchedules.isEmpty && vm.isLoadingOnCall {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Loading schedules…").font(.caption).foregroundStyle(.secondary)
                }
            } else if teamSchedules.isEmpty {
                Text("No schedules configured for this team")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(teamSchedules) { schedule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.name).font(.caption.bold()).foregroundStyle(.secondary)
                        let participants = vm.onCallResults[schedule.id] ?? []
                        if participants.isEmpty && vm.isLoadingOnCall {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Loading…").font(.caption2).foregroundStyle(.tertiary)
                            }
                        } else if participants.isEmpty {
                            Text("No one on call").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array(participants.enumerated()), id: \.offset) { i, p in
                                HStack(spacing: 8) {
                                    Image(systemName: i == 0 ? "person.fill" : "person")
                                        .foregroundStyle(i == 0 ? Color.accentColor : .secondary)
                                        .frame(width: 18)
                                    Text(vm.displayNames[p.name] ?? p.name).font(.callout)
                                    if i == 0 {
                                        Text("Primary")
                                            .font(.caption2).padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let desc = team.description, !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        .task { await vm.loadOnCallForTeam(teamId: team.id, appState: appState) }
    }

    private var noFavoriteTeamsPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3").font(.title2).foregroundStyle(.secondary)
            Text("No favorite teams selected").font(.callout).foregroundStyle(.secondary)
            Text("Go to Settings → JSM Operations to discover and select your teams.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Button("Open JSM Settings") {
                appState.showSettings = true; appState.selectedReport = nil
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding()
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if message.contains("credentials") || message.contains("configured") {
                Button {
                    appState.showSettings = true; appState.selectedSettingsTab = "jira"
                } label: { Text("Fix in Settings").font(.caption) }
                .buttonStyle(.bordered).controlSize(.small)
            }
            Button { Task { await vm.load(appState: appState) } } label: {
                Text("Retry").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - Alerts WebView

struct AlertsWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var showSSO: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.isElementFullscreenEnabled = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Reload when URL changes (filter switch)
        if wv.url?.absoluteString != url.absoluteString {
            wv.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AlertsWebView
        init(_ parent: AlertsWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                let host = webView.url?.host ?? ""
                // Show SSO banner if we landed on a login page
                if host.contains("okta.com") || host.contains("login") || host.contains("auth") {
                    self.parent.showSSO = true
                } else if host.hasSuffix("atlassian.net") {
                    self.parent.showSSO = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // Allow all navigation for Okta/Atlassian SSO chain; external links open in browser
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let host = url.host ?? ""
            if action.navigationType == .linkActivated,
               !host.hasSuffix("atlassian.net"),
               !host.hasSuffix("atlassian.com"),
               !host.hasSuffix("okta.com"),
               !host.hasSuffix("google.com"),
               !host.hasSuffix("microsoft.com") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

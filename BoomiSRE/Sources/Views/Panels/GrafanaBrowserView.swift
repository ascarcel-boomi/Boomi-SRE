import SwiftUI
import WebKit

struct GrafanaBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = GrafanaBrowserViewModel()
    @State private var showAlerts = false
    @State private var dashboardTab = 0
    @State private var webViewLoading = true
    @State private var showGrafanaSSOBanner = false
    @State private var grafanaSignedIn = false
    @State private var collapsedFolders: Set<String> = []

    private let collapsedFoldersKey = "grafana_collapsed_folders"

    var body: some View {
        HSplitView {
            // Left: dashboard list
            VStack(spacing: 0) {
                BrowserSidebarHeader(title: "Grafana", isLoading: vm.isLoadingDashboards, lastRefreshed: vm.lastFetched) {
                    Task { await vm.loadDashboards(appState: appState) }
                }

                IntegrationHealthBadge(serviceName: "Grafana", status: appState.grafanaAuthStatus)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                // Search
                TextField("Search dashboards…", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12).padding(.bottom, 8)

                // Expand All / Collapse All
                HStack(spacing: 8) {
                    Button("Expand All") {
                        withAnimation { collapsedFolders.removeAll() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Collapse All") {
                        let allFolders = Set(Dictionary(grouping: vm.filteredDashboards, by: { $0.folderTitle }).keys)
                        withAnimation { collapsedFolders = allFolders }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                Divider()

                // Alerts toggle
                if !vm.alertRules.isEmpty {
                    Button {
                        showAlerts.toggle()
                        if showAlerts { vm.selectedDashboard = nil }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: vm.alertingCount > 0 ? "bell.badge.fill" : "bell")
                                .foregroundStyle(vm.alertingCount > 0 ? .red : .secondary)
                            Text("Alert Rules (\(vm.alertRules.count))")
                                .font(.callout)
                            if vm.alertingCount > 0 {
                                Text("\(vm.alertingCount) firing")
                                    .font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.red).clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(showAlerts ? Color.accentColor.opacity(0.1) : .clear)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }

                if vm.filteredDashboards.isEmpty && !vm.isLoadingDashboards {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.title).foregroundStyle(.secondary)
                        Text("No dashboards").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }.padding()
                } else {
                    let grouped = Dictionary(grouping: vm.filteredDashboards, by: { $0.folderTitle })
                    let folders = grouped.keys.sorted()

                    List(selection: $vm.selectedDashboard) {
                        ForEach(folders, id: \.self) { folder in
                            let dashes = grouped[folder] ?? []
                            Section(isExpanded: folderBinding(folder)) {
                                ForEach(Array(dashes.enumerated()), id: \.element.uid) { idx, dash in
                                    dashRow(dash)
                                        .listRowBackground(idx.isMultiple(of: 2)
                                            ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                            : Color.clear)
                                        .tag(dash)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(folder)
                                        .font(.callout.bold())
                                    Spacer()
                                    Text("\(dashes.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleFolder(folder) }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: vm.selectedDashboard) {
                        if vm.selectedDashboard != nil { showAlerts = false }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            .splitGrip()

            // Right: content
            VStack(spacing: 0) {
                if showAlerts {
                    alertsPane
                } else if let dash = vm.selectedDashboard {
                    dashboardDetailPane(dash: dash)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("Select a dashboard or view alert rules")
                            .font(.headline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Load persisted collapsed state; default to all collapsed on first visit
            if let saved = UserDefaults.standard.array(forKey: collapsedFoldersKey) as? [String] {
                collapsedFolders = Set(saved)
            } else {
                // Will be populated once dashboards load — see onChange(of: vm.dashboards)
                collapsedFolders = []
            }
            let stale = vm.lastFetched.map { Date().timeIntervalSince($0) > 60 } ?? true
            if vm.dashboards.isEmpty || stale { Task { await vm.loadDashboards(appState: appState) } }
        }
        .onChange(of: vm.dashboards) {
            // Collapse all folders on first load if no saved preference exists
            if UserDefaults.standard.object(forKey: collapsedFoldersKey) == nil {
                let allFolders = Set(Dictionary(grouping: vm.dashboards, by: { $0.folderTitle }).keys)
                collapsedFolders = allFolders
            }
        }
        .onChange(of: collapsedFolders) {
            UserDefaults.standard.set(Array(collapsedFolders), forKey: collapsedFoldersKey)
        }
        .onChange(of: vm.selectedDashboard) {
            if let dash = vm.selectedDashboard {
                Task { await vm.loadPanels(dashboard: dash, appState: appState) }
            }
        }
    }

    private func folderBinding(_ folder: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolders.contains(folder) },
            set: { isExpanded in
                if isExpanded { collapsedFolders.remove(folder) }
                else { collapsedFolders.insert(folder) }
            }
        )
    }

    private func toggleFolder(_ folder: String) {
        withAnimation {
            if collapsedFolders.contains(folder) {
                collapsedFolders.remove(folder)
            } else {
                collapsedFolders.insert(folder)
            }
        }
    }

    private func dashRow(_ dash: GrafanaDashboard) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dash.title).font(.callout).lineLimit(1)
            if !dash.tags.isEmpty {
                Text(dash.tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Dashboard Detail

    private func dashboardDetailPane(dash: GrafanaDashboard) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dash.title).font(.title2.bold())
                    HStack(spacing: 8) {
                        Label(dash.folderTitle, systemImage: "folder")
                        if !dash.tags.isEmpty {
                            Label(dash.tags.joined(separator: ", "), systemImage: "tag")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if grafanaSignedIn {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                let baseURL = appState.grafanaURL.hasSuffix("/")
                    ? String(appState.grafanaURL.dropLast()) : appState.grafanaURL
                let dashPath = dash.url.hasPrefix("/") ? dash.url : "/" + dash.url
                if let url = URL(string: baseURL + dashPath) {
                    Link(destination: url) { Label("Open in Grafana", systemImage: "safari") }
                }
            }
            .padding(12)

            // AI buttons
            HStack(spacing: 10) {
                Button { Task { await vm.explainDashboard() } } label: {
                    Label(vm.isAnalyzing ? "..." : "Explain Dashboard", systemImage: "sparkles")
                }
                .buttonStyle(.bordered).disabled(vm.isAnalyzing || vm.panels.isEmpty)

                if !vm.alertRules.isEmpty {
                    Button { Task { await vm.analyzeAlerts() } } label: {
                        Label("Analyze Alerts", systemImage: "bell.badge")
                    }
                    .buttonStyle(.bordered).disabled(vm.isAnalyzing)
                }
                if vm.isAnalyzing { ProgressView().scaleEffect(0.8) }
                if vm.aiAnalysis != nil {
                    Button { vm.aiAnalysis = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            if let err = vm.aiError {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            if let analysis = vm.aiAnalysis {
                AIAnalysisBox(text: analysis, tintColor: .orange)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }

            // Tab picker
            Picker("View", selection: $dashboardTab) {
                Text("Dashboard").tag(0)
                Text("Queries").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 8)

            Divider()

            if dashboardTab == 0 {
                // WebView — uses shared Safari cookie store for auth (Bearer token is API-only)
                let baseURL = appState.grafanaURL.hasSuffix("/")
                    ? String(appState.grafanaURL.dropLast()) : appState.grafanaURL
                let dashPath = dash.url.hasPrefix("/") ? dash.url : "/" + dash.url
                let dashURL = URL(string: baseURL + dashPath + "?kiosk")
                    ?? URL(string: baseURL.isEmpty ? "https://grafana.com" : baseURL)!

                VStack(spacing: 0) {
                    // SSO sign-in banner
                    if showGrafanaSSOBanner && !grafanaSignedIn {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.key").foregroundStyle(.orange)
                            Text("Sign in with your Okta SSO credentials below. You only need to do this once.")
                                .font(.caption)
                            Spacer()
                            Button("Dismiss") { showGrafanaSSOBanner = false }
                                .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        Divider()
                    }
                    // Reload bar
                    HStack(spacing: 8) {
                        Text(dashURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            webViewLoading = true
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    ZStack {
                        GrafanaWebView(url: dashURL, apiToken: appState.grafanaToken,
                                       webUsername: KeychainHelper.load(key: "grafana-web-username") ?? "",
                                       webPassword: KeychainHelper.load(key: "grafana-web-password") ?? "",
                                       isLoading: $webViewLoading,
                                       showSSOBanner: $showGrafanaSSOBanner,
                                       ssoSignedIn: $grafanaSignedIn)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if webViewLoading {
                            ProgressView("Loading dashboard...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: dash.uid) { webViewLoading = true }
            } else {
                // Panels / Queries text view
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.isLoadingPanels {
                            HStack { ProgressView().scaleEffect(0.8); Text("Loading panels...").font(.caption) }
                        } else if !vm.panels.isEmpty {
                            Text("Panels (\(vm.panels.count))").font(.subheadline.bold())
                            ForEach(vm.panels) { panel in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(panel.type).font(.caption2.monospaced())
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15)).clipShape(Capsule())
                                        Text(panel.title).font(.callout.bold())
                                    }
                                    if !panel.description.isEmpty {
                                        Text(panel.description).font(.caption).foregroundStyle(.secondary)
                                    }
                                    ForEach(panel.targets, id: \.self) { target in
                                        Text(target).font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(.background))
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Alerts pane

    private var alertsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Alert Rules (\(vm.alertRules.count))")
                    .font(.title2.bold())
                Spacer()
                if vm.alertingCount > 0 {
                    Label("\(vm.alertingCount) firing", systemImage: "bell.badge.fill")
                        .font(.callout.bold()).foregroundStyle(.red)
                }
                Button { Task { await vm.analyzeAlerts() } } label: {
                    Label(vm.isAnalyzing ? "…" : "Analyze with AI", systemImage: "sparkles")
                }
                .buttonStyle(.bordered).disabled(vm.isAnalyzing)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let analysis = vm.aiAnalysis {
                        AIAnalysisBox(text: analysis, tintColor: .orange)
                    }
                    ForEach(vm.alertRules.sorted { $0.state < $1.state }) { alert in
                        HStack(spacing: 10) {
                            Circle().fill(alertStateColor(alert.state)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.title).font(.callout)
                                if !alert.summary.isEmpty {
                                    Text(alert.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(alert.state.uppercased())
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(alertStateColor(alert.state).opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(.background))
                    }
                }
                .padding(16)
            }
        }
    }

    private func alertStateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "alerting": return .red; case "pending": return .orange
        case "normal", "ok": return .green; default: return .secondary
        }
    }
}

// MARK: - Grafana WebView
//
// Uses WKWebsiteDataStore.default() for a persistent session shared across launches.
// The navigation delegate allows the full Okta SSO redirect chain without blocking.
// Sign-in state is detected by watching for the URL returning to the Grafana host.

struct GrafanaWebView: NSViewRepresentable {
    let url: URL
    let apiToken: String
    let webUsername: String
    let webPassword: String
    @Binding var isLoading: Bool
    @Binding var showSSOBanner: Bool
    @Binding var ssoSignedIn: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()  // persistent session
        config.preferences.isElementFullscreenEnabled = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        if wv.url?.absoluteString != url.absoluteString {
            wv.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: GrafanaWebView

        init(_ parent: GrafanaWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                let currentURL = webView.url?.absoluteString ?? ""
                let host = webView.url?.host ?? ""
                let targetHost = URL(string: self.parent.url.absoluteString)?.host ?? ""

                // Auto-fill login form after React settles
                if !self.parent.webUsername.isEmpty, !self.parent.webPassword.isEmpty {
                    let user = self.parent.webUsername
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    let pass = self.parent.webPassword
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    // Wait 2s for React to fully render, then fill and keep re-filling every 500ms
                    let js = """
                    setTimeout(function() {
                        var filled = false;
                        var timer = setInterval(function() {
                            var u = document.querySelector('input[name="user"]');
                            var p = document.querySelector('input[name="password"]');
                            if (!u || !p) return;
                            var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                            s.call(u, '\(user)');
                            u.dispatchEvent(new Event('input', {bubbles:true}));
                            s.call(p, '\(pass)');
                            p.dispatchEvent(new Event('input', {bubbles:true}));
                            if (u.value === '\(user)' && p.value === '\(pass)') {
                                clearInterval(timer);
                            }
                        }, 500);
                        setTimeout(function() { clearInterval(timer); }, 10000);
                    }, 2000);
                    """
                    webView.evaluateJavaScript(js) { _, _ in }
                }

                if host.hasSuffix("okta.com") || host.contains("login") || host.contains("auth") {
                    self.parent.showSSOBanner = true
                    self.parent.ssoSignedIn = false
                } else if !targetHost.isEmpty && host.hasSuffix(targetHost) {
                    self.parent.showSSOBanner = false
                    self.parent.ssoSignedIn = true
                }
            }
        }


        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // Allow the full Okta SSO redirect chain; open external links in system browser
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let host = url.host ?? ""
            let targetHost = URL(string: self.parent.url.absoluteString)?.host ?? ""
            if action.navigationType == .linkActivated,
               !host.isEmpty,
               !host.hasSuffix(targetHost),
               !host.hasSuffix("okta.com"),
               !host.hasSuffix("google.com"),
               !host.hasSuffix("microsoft.com"),
               !host.hasSuffix("grafana.com") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

import SwiftUI
import WebKit

struct GrafanaBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = GrafanaBrowserViewModel()
    @State private var showAlerts = false
    @State private var dashboardTab = 0
    @State private var webViewLoading = true

    var body: some View {
        HSplitView {
            // Left: dashboard list
            VStack(spacing: 0) {
                HStack {
                    Text("Grafana").font(.headline)
                    Spacer()
                    if vm.isLoadingDashboards { ProgressView().scaleEffect(0.7) }
                    Button { Task { await vm.loadDashboards(appState: appState) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain)
                }
                .padding(12)

                // Search
                TextField("Search dashboards…", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12).padding(.bottom, 8)

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
                    List(vm.filteredDashboards, selection: $vm.selectedDashboard) { dash in
                        dashRow(dash).tag(dash)
                    }
                    .listStyle(.sidebar)
                    .onChange(of: vm.selectedDashboard) {
                        if vm.selectedDashboard != nil { showAlerts = false }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

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
            if vm.dashboards.isEmpty { Task { await vm.loadDashboards(appState: appState) } }
        }
        .onChange(of: vm.selectedDashboard) {
            if let dash = vm.selectedDashboard {
                Task { await vm.loadPanels(dashboard: dash, appState: appState) }
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
                if let url = URL(string: appState.grafanaURL + dash.url) {
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
                Text((try? AttributedString(markdown: analysis,
                      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(analysis))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2)))
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
                // WebView
                let dashURL = URL(string: appState.grafanaURL + dash.url + "?kiosk")
                    ?? URL(string: appState.grafanaURL.isEmpty ? "https://grafana.com" : appState.grafanaURL)!
                ZStack {
                    GrafanaWebView(url: dashURL, bearerToken: appState.grafanaToken, isLoading: $webViewLoading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if webViewLoading {
                        ProgressView("Loading dashboard...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
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
                                .background(RoundedRectangle(cornerRadius: 8).fill(.background))
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
                        Text((try? AttributedString(markdown: analysis,
                              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(analysis))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2)))
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
                        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
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

struct GrafanaWebView: NSViewRepresentable {
    let url: URL
    let bearerToken: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        wv.load(request)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) { }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: GrafanaWebView
        init(_ parent: GrafanaWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}

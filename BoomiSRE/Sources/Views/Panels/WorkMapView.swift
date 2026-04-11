import SwiftUI
import WebKit

// MARK: - WorkMapView

/// Full-panel view that hosts the D3.js work-map tree.
/// Top bar: title, stats, search, status filter, refresh.
/// Main area: WKWebView rendering work_map.html.
/// Legend overlay: bottom-left color key.
struct WorkMapView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = WorkMapViewModel()

    private let statusOptions = ["All", "To Do", "In Progress", "Done", "Stale"]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            ZStack(alignment: .bottomLeading) {
                WorkMapWebView(
                    treeJSON: vm.treeJSON,
                    statusFilter: vm.statusFilter,
                    searchText: vm.searchText,
                    onNodeClick: { key in
                        appState.pushNavigation()
                        appState.selectedTicketKey = key
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !vm.treeJSON.isEmpty {
                    legendOverlay
                        .padding(DesignTokens.sectionPadding)
                }
            }

            if vm.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading work map…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .task { await vm.loadTree(appState: appState) }
        .onChange(of: appState.activeProductIds) {
            Task { await vm.loadTree(appState: appState) }
        }
        .onChange(of: appState.refreshTrigger) {
            Task { await vm.loadTree(appState: appState) }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Work Map")
                .font(.title2.bold())

            if !vm.treeJSON.isEmpty {
                statsBar
            }

            Spacer()

            TextField("Search…", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Picker("Status", selection: $vm.statusFilter) {
                ForEach(statusOptions, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Button {
                Task { await vm.loadTree(appState: appState) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
            .help("Refresh work map")

            if let err = vm.error {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
                    .help(err)
            }
        }
        .padding(.horizontal, DesignTokens.panelPadding)
        .padding(.vertical, DesignTokens.sectionPadding)
    }

    private var statsBar: some View {
        HStack(spacing: 10) {
            statPill(value: "\(vm.epicCount)", label: "Epics", color: .purple)
            statPill(value: "\(vm.issueCount)", label: "Issues", color: .blue)
            statPill(value: String(format: "%.0f%%", vm.completionPct), label: "Done", color: .green)
        }
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.caption.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(DesignTokens.badgeFillOpacity)))
    }

    // MARK: - Legend Overlay

    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(color: .green, label: "Done")
            legendRow(color: .orange, label: "In Progress")
            legendRow(color: Color(nsColor: .systemGray), label: "To Do")
            legendRow(color: .red, label: "Stale (>30d)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                .strokeBorder(Color.secondary.opacity(DesignTokens.strokeOpacity))
        )
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - WorkMapWebView

/// NSViewRepresentable wrapping WKWebView that renders the D3.js tree from work_map.html.
///
/// Data flow:
///   1. `makeNSView` loads work_map.html from the bundle and registers `nodeClick` message handler.
///   2. `didFinish` navigation callback pushes tree data via `window.loadData(base64)` once the
///      page is ready — handles the race between `treeJSON` arriving before HTML has loaded.
///   3. `updateNSView` calls the appropriate JS bridge function whenever SwiftUI props change.
struct WorkMapWebView: NSViewRepresentable {
    let treeJSON: String
    let statusFilter: String
    let searchText: String
    let onNodeClick: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Register nodeClick message handler
        config.userContentController.add(context.coordinator, name: "nodeClick")

        let wv = WKWebView(frame: .zero, configuration: config)
        // Transparent background so macOS window chrome shows through
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv

        // Load work_map.html from the app bundle
        if let htmlURL = Bundle.main.url(forResource: "work_map", withExtension: "html") {
            wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Push tree data if it changed and page is already loaded
        if treeJSON != coordinator.lastPushedJSON, coordinator.pageDidLoad {
            coordinator.lastPushedJSON = treeJSON
            pushData(treeJSON, to: wv)
        }

        // Apply status filter changes
        if statusFilter != coordinator.lastStatusFilter {
            coordinator.lastStatusFilter = statusFilter
            let escaped = statusFilter
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("window.filterByStatus('\(escaped)')") { _, _ in }
        }

        // Apply search text changes
        if searchText != coordinator.lastSearchText {
            coordinator.lastSearchText = searchText
            let escaped = searchText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("window.searchNodes('\(escaped)')") { _, _ in }
        }
    }

    // MARK: - JS Bridge Helpers

    /// Passes potentially large JSON to the page via base64 to avoid any
    /// string-escaping issues with single/double quotes in Jira summary text.
    private func pushData(_ json: String, to wv: WKWebView) {
        guard !json.isEmpty else { return }
        let base64 = Data(json.utf8).base64EncodedString()
        wv.evaluateJavaScript("window.loadData(atob('\(base64)'))") { _, _ in }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: WorkMapWebView
        weak var webView: WKWebView?

        var pageDidLoad = false
        var lastPushedJSON = ""
        var lastStatusFilter = ""
        var lastSearchText = ""

        init(_ parent: WorkMapWebView) { self.parent = parent }

        // WKNavigationDelegate — called when work_map.html finishes loading
        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.pageDidLoad = true
                // Retry pushing data that may have arrived before the page was ready
                if !self.parent.treeJSON.isEmpty {
                    self.lastPushedJSON = self.parent.treeJSON
                    let base64 = Data(self.parent.treeJSON.utf8).base64EncodedString()
                    _ = try? await webView.evaluateJavaScript("window.loadData(atob('\(base64)'))")
                }
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Silently ignore load failures (e.g., during app teardown)
        }

        // WKScriptMessageHandler — receives nodeClick messages from D3.js
        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Capture body and name before hopping to MainActor to avoid
            // Swift 6 strict-concurrency warnings about nonisolated access.
            let msgName = message.name
            let msgBody = message.body
            Task { @MainActor in
                guard msgName == "nodeClick", let key = msgBody as? String else { return }
                self.parent.onNodeClick(key)
            }
        }
    }
}

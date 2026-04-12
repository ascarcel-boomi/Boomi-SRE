import SwiftUI
import WebKit

struct WorkMapView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = WorkMapViewModel()

    private let statusOptions = ["All", "new", "indeterminate", "done"]

    /// Map appState.appTheme to the JS theme name.
    private var jsTheme: String {
        if appState.appTheme == "boomi" { return "boomi" }
        // "system" — detect system appearance
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? "dark" : "light"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            WorkMapWebView(
                treeJSON: vm.treeJSON,
                statusFilter: vm.statusFilter,
                searchText: vm.searchText,
                theme: jsTheme,
                onNodeClick: { key in
                    appState.pushNavigation()
                    appState.selectedTicketKey = key
                }
            )
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
                    Text(opt == "All" ? "All" : opt == "new" ? "To Do" : opt == "indeterminate" ? "In Progress" : "Done").tag(opt)
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

    // MARK: - Stats Bar

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
}

// MARK: - WorkMapWebView

/// NSViewRepresentable wrapping WKWebView that renders the D3.js tree from work_map.html.
struct WorkMapWebView: NSViewRepresentable {
    let treeJSON: String
    let statusFilter: String
    let searchText: String
    let theme: String
    let onNodeClick: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "nodeClick")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv

        if let htmlURL = Bundle.module.url(forResource: "work_map", withExtension: "html") {
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

        // Apply theme changes
        if theme != coordinator.lastTheme {
            coordinator.lastTheme = theme
            wv.evaluateJavaScript("if(window.setTheme) window.setTheme('\(theme)')") { _, _ in }
        }

        // Apply status filter changes
        if statusFilter != coordinator.lastStatusFilter {
            coordinator.lastStatusFilter = statusFilter
            let escaped = statusFilter.replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("if(window.filterByStatus) window.filterByStatus('\(escaped)')") { _, _ in }
        }

        // Apply search text changes
        if searchText != coordinator.lastSearchText {
            coordinator.lastSearchText = searchText
            let escaped = searchText.replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("if(window.searchNodes) window.searchNodes('\(escaped)')") { _, _ in }
        }
    }

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
        var lastTheme = ""

        init(_ parent: WorkMapWebView) { self.parent = parent }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.pageDidLoad = true
                // Push theme first, then data
                let theme = self.parent.theme
                _ = try? await webView.evaluateJavaScript("if(window.setTheme) window.setTheme('\(theme)')")
                self.lastTheme = theme

                if !self.parent.treeJSON.isEmpty {
                    self.lastPushedJSON = self.parent.treeJSON
                    let base64 = Data(self.parent.treeJSON.utf8).base64EncodedString()
                    _ = try? await webView.evaluateJavaScript("window.loadData(atob('\(base64)'))")
                }
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let msgName = message.name
            let msgBody = message.body
            Task { @MainActor in
                guard msgName == "nodeClick", let key = msgBody as? String else { return }
                self.parent.onNodeClick(key)
            }
        }
    }
}

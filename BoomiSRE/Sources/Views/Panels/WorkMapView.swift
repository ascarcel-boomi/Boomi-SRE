import SwiftUI
import WebKit

struct WorkMapView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = WorkMapViewModel()
    @State private var jsCommand: String = ""

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
                assigneeFilter: vm.assigneeFilter,
                quarterFilter: vm.quarterFilter,
                jsCommand: $jsCommand,
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

            Picker("Assignee", selection: $vm.assigneeFilter) {
                Text("All").tag("All")
                ForEach(vm.uniqueAssignees, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Picker("Quarter", selection: $vm.quarterFilter) {
                Text("All Quarters").tag("All")
                ForEach(vm.uniqueQuarters, id: \.self) { q in
                    Text(q).tag(q)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Button { jsCommand = "expandAll" } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.plain)
            .help("Expand All")

            Button { jsCommand = "collapseAll" } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help("Collapse All")

            Button { jsCommand = "fitToView" } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Fit to View")

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
    let assigneeFilter: String
    let quarterFilter: String
    @Binding var jsCommand: String
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

        // Apply assignee filter changes
        if assigneeFilter != coordinator.lastAssigneeFilter {
            coordinator.lastAssigneeFilter = assigneeFilter
            let escaped = assigneeFilter.replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("if(window.filterByAssignee) window.filterByAssignee('\(escaped)')") { _, _ in }
        }

        // Apply quarter filter changes
        if quarterFilter != coordinator.lastQuarterFilter {
            coordinator.lastQuarterFilter = quarterFilter
            let escaped = quarterFilter.replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("if(window.filterByQuarter) window.filterByQuarter('\(escaped)')") { _, _ in }
        }

        // Execute JS commands (expand all, collapse all, fit to view)
        if !jsCommand.isEmpty {
            let cmd = jsCommand
            let binding = _jsCommand
            wv.evaluateJavaScript("if(window.\(cmd)) window.\(cmd)()") { _, _ in }
            DispatchQueue.main.async { binding.wrappedValue = "" }
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
        var lastAssigneeFilter = ""
        var lastQuarterFilter = ""
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

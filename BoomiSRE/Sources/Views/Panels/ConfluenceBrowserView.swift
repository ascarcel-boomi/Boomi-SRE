import SwiftUI
import WebKit

struct ConfluenceBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ConfluenceBrowserViewModel()
    @State private var confluenceRenderMode = 0  // 0=Rendered, 1=Plain Text
    @State private var showSSOBanner = false
    @State private var ssoSignedIn = false
    @State private var collapsedSections: Set<String> = []
    @State private var pageFilter: String = ""

    var body: some View {
        HSplitView {
            // Left: spaces + pages sidebar
            VStack(spacing: 0) {
                HStack {
                    Text("Confluence").font(.headline)
                    Spacer()
                    if vm.isLoadingSpaces || vm.isLoadingPages { ProgressView().scaleEffect(0.7) }
                    Button { Task { await vm.loadSpaces(appState: appState) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain)
                }
                .padding(12)

                // Search + Filter
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Search pages…", text: $vm.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await vm.search(appState: appState) } }
                        if vm.isSearching { ProgressView().scaleEffect(0.7) }
                    }
                    if !vm.pages.isEmpty || !vm.searchResults.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.secondary).font(.caption)
                            TextField("Filter pages…", text: $pageFilter)
                                .textFieldStyle(.roundedBorder)
                            if !pageFilter.isEmpty {
                                Button { pageFilter = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)

                Divider()

                if let err = vm.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                        .padding(8)
                }

                if vm.spaces.isEmpty && !vm.isLoadingSpaces {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "doc.richtext").font(.title).foregroundStyle(.secondary)
                        Text("No spaces found").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }.padding()
                } else {
                    List(selection: $vm.selectedPage) {
                        // Search results
                        if !vm.searchResults.isEmpty {
                            let filtered = filteredPages(vm.searchResults)
                            if !filtered.isEmpty {
                                Section(isExpanded: sectionBinding("search")) {
                                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, page in
                                        pageRow(page)
                                            .tag(page)
                                            .listRowBackground(idx.isMultiple(of: 2)
                                                ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                                : Color.clear)
                                    }
                                } header: {
                                    sectionHeader("magnifyingglass", "Search Results", filtered.count)
                                        .onTapGesture { toggleSection("search") }
                                }
                            }
                        }

                        // Spaces with pages nested underneath
                        ForEach(vm.spaces) { space in
                            let spacePages = vm.pagesForSpace(space.key)
                            let filtered = filteredPages(spacePages)
                            Section(isExpanded: sectionBinding(space.key)) {
                                if vm.isLoadingPages && vm.selectedSpace?.key == space.key && spacePages.isEmpty {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else if filtered.isEmpty && !pageFilter.isEmpty {
                                    Text("No matching pages").font(.caption).foregroundStyle(.tertiary)
                                } else {
                                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, page in
                                        pageRow(page)
                                            .tag(page)
                                            .listRowBackground(idx.isMultiple(of: 2)
                                                ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                                : Color.clear)
                                    }
                                }
                            } header: {
                                sectionHeader("doc.richtext", "\(space.key) — \(space.name)",
                                              spacePages.isEmpty ? nil : filtered.count)
                                    .onTapGesture {
                                        toggleSection(space.key)
                                        // Auto-load pages when expanding a space for the first time
                                        if !collapsedSections.contains(space.key) && vm.pagesForSpace(space.key).isEmpty {
                                            vm.selectedSpace = space
                                            Task { await vm.loadPages(space: space, appState: appState) }
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

            // Right: page content
            if let page = vm.selectedPage {
                pageContentPane(page: page)
            } else {
                // Empty state with AI draft
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.richtext").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Select a page from the left").font(.headline).foregroundStyle(.secondary)

                    // Draft page prompt
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or draft a new page with AI:").font(.subheadline.bold())
                        HStack(spacing: 8) {
                            TextField("Describe the page you need…", text: $vm.draftPrompt)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await vm.draftNewPage() } }
                            Button { Task { await vm.draftNewPage() } } label: {
                                Label(vm.isDrafting ? "Drafting…" : "Draft", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered).disabled(vm.isDrafting || vm.draftPrompt.isEmpty)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 500)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background))

                    if let aiErr = vm.aiError {
                        Label(aiErr, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if let draft = vm.draftedPage {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Drafted Page").font(.subheadline.bold())
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(draft, forType: .string)
                                } label: { Label("Copy", systemImage: "doc.on.doc") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                Button { vm.draftedPage = nil } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            ScrollView {
                                MarkdownView(markdown: draft)
                                    .frame(minHeight: 200).padding(12)
                            }
                            .frame(maxHeight: 400)
                        }
                        .padding()
                        .frame(maxWidth: 700)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.3)))
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .onAppear {
            let stale = vm.lastFetched.map { Date().timeIntervalSince($0) > 60 } ?? true
            if vm.spaces.isEmpty || stale { Task { await vm.loadSpaces(appState: appState) } }
        }
        .onChange(of: appState.activeProductIds) {
            Task { await vm.loadSpaces(appState: appState) }
        }
        .onChange(of: vm.selectedPage) {
            if let page = vm.selectedPage { Task { await vm.loadContent(page: page, appState: appState) } }
        }
    }

    // MARK: - Helpers

    private func filteredPages(_ pages: [ConfluenceService.ConfluencePage]) -> [ConfluenceService.ConfluencePage] {
        guard !pageFilter.isEmpty else { return pages }
        let q = pageFilter.lowercased()
        return pages.filter { $0.title.lowercased().contains(q) || $0.authorName.lowercased().contains(q) }
    }

    private func pageRow(_ page: ConfluenceService.ConfluencePage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(page.title).font(.callout).lineLimit(2)
            if !page.lastModified.isEmpty {
                Text("\(page.lastModified) · \(page.authorName)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func sectionHeader(_ icon: String, _ label: String, _ count: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(label).font(.caption.bold())
            Spacer()
            if let count {
                Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(key) },
            set: { if $0 { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
        )
    }

    private func toggleSection(_ key: String) {
        withAnimation { if collapsedSections.contains(key) { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
    }

    // MARK: - Page Content Pane

    private func pageContentPane(page: ConfluenceService.ConfluencePage) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title).font(.title3.bold())
                    if !page.lastModified.isEmpty {
                        Text("Updated \(page.lastModified) by \(page.authorName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if ssoSignedIn {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                if let url = URL(string: page.url) {
                    Link(destination: url) { Label("Open in Confluence", systemImage: "safari") }
                }
                Button { Task { await vm.summarizePage() } } label: {
                    Label(vm.isAnalyzing ? "…" : "Summarize", systemImage: "sparkles")
                }
                .buttonStyle(.bordered).disabled(vm.isAnalyzing || vm.pageContent.isEmpty)
            }
            .padding(16)
            Divider()

            if let err = vm.aiError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).padding(.horizontal, 16)
            }
            if let analysis = vm.aiAnalysis {
                HStack {
                    InlineMarkdownText(text: analysis)
                    Spacer()
                    Button { vm.aiAnalysis = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.2)))
                .padding(.horizontal, 16).padding(.top, 8)
            }

            // View mode picker
            Picker("View", selection: $confluenceRenderMode) {
                Text("Web View").tag(0)
                Text("Plain Text").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 8)
            Divider()

            if confluenceRenderMode == 0 {
                if let pageURL = URL(string: page.url) {
                    VStack(spacing: 0) {
                        if showSSOBanner && !ssoSignedIn {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.key").foregroundStyle(.orange)
                                Text("Sign in with Okta SSO below. You only need to do this once.").font(.caption)
                                Spacer()
                                Button("Dismiss") { showSSOBanner = false }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Color.orange.opacity(0.1))
                            Divider()
                        }
                        ConfluenceWebView(url: pageURL, showSSOBanner: $showSSOBanner, ssoSignedIn: $ssoSignedIn)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack { Spacer(); Text("Invalid page URL").foregroundStyle(.secondary); Spacer() }
                }
            } else {
                if vm.isLoadingContent {
                    VStack { Spacer(); ProgressView("Loading page content..."); Spacer() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(vm.pageContent.isEmpty ? "(No content loaded)" : vm.pageContent)
                            .font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                }
            }
        }
    }
}

// MARK: - Confluence WebView

struct ConfluenceWebView: NSViewRepresentable {
    let url: URL
    @Binding var showSSOBanner: Bool
    @Binding var ssoSignedIn: Bool

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
        if wv.url?.absoluteString != url.absoluteString { wv.load(URLRequest(url: url)) }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ConfluenceWebView
        init(_ parent: ConfluenceWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = webView.url?.host ?? ""
            DispatchQueue.main.async {
                if host.hasSuffix("okta.com") || host.contains("login") || host.contains("auth") {
                    self.parent.showSSOBanner = true; self.parent.ssoSignedIn = false
                } else if host.hasSuffix("atlassian.net") || host.hasSuffix("atlassian.com") {
                    self.parent.showSSOBanner = false; self.parent.ssoSignedIn = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let host = url.host ?? ""
            if action.navigationType == .linkActivated,
               !host.hasSuffix("atlassian.net"), !host.hasSuffix("atlassian.com"),
               !host.hasSuffix("okta.com"), !host.hasSuffix("google.com"), !host.hasSuffix("microsoft.com") {
                NSWorkspace.shared.open(url); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}

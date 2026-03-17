import SwiftUI
import WebKit

struct ConfluenceBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ConfluenceBrowserViewModel()
    @State private var confluenceRenderMode = 0  // 0=Rendered, 1=Plain Text
    @State private var showSSOBanner = false
    @State private var ssoSignedIn = false
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        HSplitView {
            // Left: space list
            VStack(spacing: 0) {
                HStack {
                    Text("Confluence").font(.headline)
                    Spacer()
                    if vm.isLoadingSpaces { ProgressView().scaleEffect(0.7) }
                    Button { Task { await vm.loadSpaces(appState: appState) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain)
                }
                .padding(12)

                // Search bar
                HStack(spacing: 6) {
                    TextField("Search pages…", text: $vm.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await vm.search(appState: appState) } }
                    if vm.isSearching { ProgressView().scaleEffect(0.7) }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)

                Divider()

                if vm.spaces.isEmpty && !vm.isLoadingSpaces {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "doc.richtext").font(.title).foregroundStyle(.secondary)
                        Text("No spaces found").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }.padding()
                } else {
                    List(selection: $vm.selectedSpace) {
                        // Search results (if any)
                        if !vm.searchResults.isEmpty {
                            Section(isExpanded: sectionBinding("search")) {
                                ForEach(Array(vm.searchResults.enumerated()), id: \.element.id) { idx, page in
                                    Button {
                                        Task {
                                            vm.selectedPage = page
                                            await vm.loadContent(page: page, appState: appState)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(page.title).font(.callout).lineLimit(1)
                                            Text(page.spaceKey).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(idx.isMultiple(of: 2)
                                        ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                        : Color.clear)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                    Text("Search Results").font(.caption.bold())
                                    Spacer()
                                    Text("\(vm.searchResults.count)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleSection("search") }
                            }
                        }
                        // Spaces
                        Section(isExpanded: sectionBinding("spaces")) {
                            ForEach(Array(vm.spaces.enumerated()), id: \.element.id) { idx, space in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(space.name).font(.callout)
                                    Text(space.key).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                                .tag(space)
                                .listRowBackground(idx.isMultiple(of: 2)
                                    ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                    : Color.clear)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                                Text("Spaces").font(.caption.bold())
                                Spacer()
                                Text("\(vm.spaces.count)").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSection("spaces") }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            // Right: pages + content
            VStack(spacing: 0) {
                if let space = vm.selectedSpace {
                    HSplitView {
                        // Page list
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(space.name).font(.headline)
                                    Text(space.key).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vm.isLoadingPages { ProgressView().scaleEffect(0.7) }
                                Text("\(vm.pages.count) pages").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            Divider()
                            List(vm.pages, id: \.id, selection: $vm.selectedPage) { page in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title).font(.callout).lineLimit(2)
                                    if !page.lastModified.isEmpty {
                                        Text("\(page.lastModified) · \(page.authorName)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .tag(page)
                            }
                            .listStyle(.plain)
                        }
                        .frame(minWidth: 220, maxWidth: 320)

                        // Page content
                        if let page = vm.selectedPage {
                            pageContentPane(page: page)
                                .frame(minWidth: 400)
                        } else {
                            VStack { Spacer(); Text("Select a page").foregroundStyle(.secondary); Spacer() }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "doc.richtext").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("Select a space").font(.headline).foregroundStyle(.secondary)

                        // Draft page prompt
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Or draft a new page with AI:").font(.subheadline.bold())
                            HStack(spacing: 8) {
                                TextField("Describe the page you need (e.g. \"RDS failover runbook\")…",
                                          text: $vm.draftPrompt)
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
                                        .frame(minHeight: 200)
                                        .padding(12)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            let stale = vm.lastFetched.map { Date().timeIntervalSince($0) > 60 } ?? true
            if vm.spaces.isEmpty || stale { Task { await vm.loadSpaces(appState: appState) } }
        }
        .onChange(of: appState.activeProductIds) {
            Task { await vm.loadSpaces(appState: appState) }
        }
        .onChange(of: vm.selectedSpace) {
            if let space = vm.selectedSpace { Task { await vm.loadPages(space: space, appState: appState) } }
        }
        .onChange(of: vm.selectedPage) {
            if let page = vm.selectedPage { Task { await vm.loadContent(page: page, appState: appState) } }
        }
    }

    // MARK: - Section Collapse

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
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider()

            // Page content
            if confluenceRenderMode == 0 {
                // Full Confluence page via WKWebView — in-WebView Okta SSO
                if let pageURL = URL(string: page.url) {
                    VStack(spacing: 0) {
                        // SSO sign-in banner (shown when WebView lands on login page)
                        if showSSOBanner && !ssoSignedIn {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.key").foregroundStyle(.orange)
                                Text("Sign in with your Okta SSO credentials below. You only need to do this once — your session will be remembered.")
                                    .font(.caption)
                                Spacer()
                                Button("Dismiss") { showSSOBanner = false }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            Divider()
                        }
                        // URL bar + reload
                        HStack(spacing: 8) {
                            Text(page.url)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                confluenceRenderMode = 1
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    confluenceRenderMode = 0
                                }
                            } label: {
                                Label("Reload", systemImage: "arrow.clockwise").font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        Divider()
                        ConfluenceWebView(url: pageURL,
                                         showSSOBanner: $showSSOBanner,
                                         ssoSignedIn: $ssoSignedIn)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack { Spacer(); Text("Invalid page URL").foregroundStyle(.secondary); Spacer() }
                }
            } else {
                // Plain text from API (used for AI summarization)
                if vm.isLoadingContent {
                    VStack { Spacer(); ProgressView("Loading page content..."); Spacer() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(vm.pageContent.isEmpty ? "(No content loaded)" : vm.pageContent)
                            .font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
        }
    }
}

// MARK: - Confluence WebView
//
// Uses WKWebsiteDataStore.default() for a persistent session shared across launches.
// The navigation delegate allows the full Okta SSO redirect chain
// (Confluence → Okta login → MFA → back to Confluence) without blocking.
// Sign-in state is detected by watching for the final redirect back to *.atlassian.net/wiki/*.

struct ConfluenceWebView: NSViewRepresentable {
    let url: URL
    @Binding var showSSOBanner: Bool
    @Binding var ssoSignedIn: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()  // persistent session
        config.preferences.isElementFullscreenEnabled = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        // Chrome-like UA helps Confluence render correctly
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
        let parent: ConfluenceWebView

        init(_ parent: ConfluenceWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = webView.url?.host ?? ""
            DispatchQueue.main.async {
                if host.hasSuffix("okta.com") || host.contains("login") || host.contains("auth") {
                    // Still on login/SSO page
                    self.parent.showSSOBanner = true
                    self.parent.ssoSignedIn = false
                } else if host.hasSuffix("atlassian.net") || host.hasSuffix("atlassian.com") {
                    // Back on Confluence — SSO complete
                    self.parent.showSSOBanner = false
                    self.parent.ssoSignedIn = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Ignore cancellation errors that happen during redirect chains
        }

        // Allow all navigation — the full Okta redirect chain must not be blocked.
        // External link-clicks open in the system browser instead.
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let host = url.host ?? ""
            // Open non-Atlassian/Okta link-clicks in the system browser
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

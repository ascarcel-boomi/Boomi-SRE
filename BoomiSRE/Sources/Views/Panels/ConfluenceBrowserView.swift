import SwiftUI
import WebKit

struct ConfluenceBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ConfluenceBrowserViewModel()
    @State private var confluenceRenderMode = 0  // 0=Rendered, 1=Plain Text

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
                            Section("Search Results (\(vm.searchResults.count))") {
                                ForEach(vm.searchResults) { page in
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
                                }
                            }
                        }
                        // Spaces
                        Section("Spaces") {
                            ForEach(vm.spaces) { space in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(space.name).font(.callout)
                                    Text(space.key).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                                .tag(space)
                            }
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
                                    Text((try? AttributedString(markdown: draft,
                                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                         ?? AttributedString(draft))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
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
            if vm.spaces.isEmpty { Task { await vm.loadSpaces(appState: appState) } }
        }
        .onChange(of: vm.selectedSpace) {
            if let space = vm.selectedSpace { Task { await vm.loadPages(space: space, appState: appState) } }
        }
        .onChange(of: vm.selectedPage) {
            if let page = vm.selectedPage { Task { await vm.loadContent(page: page, appState: appState) } }
        }
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
                // Login via Okta SSO in system browser — cookies flow back to the webview
                let baseURL = appState.jiraBaseURL.hasSuffix("/")
                    ? String(appState.jiraBaseURL.dropLast()) : appState.jiraBaseURL
                if let loginURL = URL(string: baseURL + "/login") {
                    Button {
                        NSWorkspace.shared.open(loginURL)
                    } label: {
                        Label("Log In", systemImage: "person.badge.key")
                    }
                    .buttonStyle(.bordered)
                    .help("Opens Confluence login (Okta SSO) in your browser. Come back and reload after signing in.")
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
                    Text((try? AttributedString(markdown: analysis,
                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                         ?? AttributedString(analysis))
                        .textSelection(.enabled).font(.callout)
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
                // Full Confluence page via WKWebView — Okta SSO via shared Safari cookie store
                if let pageURL = URL(string: page.url) {
                    VStack(spacing: 0) {
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
                        ConfluenceWebView(url: pageURL)
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
// Authentication note: Confluence (Atlassian Cloud) authenticates via Okta SSO cookies,
// not API tokens. WKWebsiteDataStore.default() shares the Safari cookie jar, so users
// who are logged into Confluence via Okta in Safari are automatically authenticated here.
// Use the "Log In" button to open /login in the system browser if not yet authenticated.

struct ConfluenceWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Share cookies/session with Safari so Okta SSO carries over
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        if wv.url?.absoluteString != url.absoluteString {
            wv.load(URLRequest(url: url))
        }
    }
}

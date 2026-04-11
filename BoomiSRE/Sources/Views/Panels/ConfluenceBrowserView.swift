import SwiftUI
import WebKit

struct ConfluenceBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = ConfluenceBrowserViewModel()
    @State private var collapsedSections: Set<String> = []
    @State private var pageFilter: String = ""
    @State private var selectedSpaceFilter: String? = nil  // nil = all spaces

    var body: some View {
        HSplitView {
            // Left: sidebar (matches KB layout)
            articleListPane
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 380)
                .splitGrip()
                .background(Color(nsColor: .controlBackgroundColor))

            // Right: page content
            if let page = vm.selectedPage {
                pageContentPane(page: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                emptyContentPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            Task { await vm.loadSpaces(appState: appState) }
        }
        .onChange(of: appState.activeProductIds) {
            Task { await vm.loadSpaces(appState: appState) }
        }
        .onChange(of: vm.selectedPage) {
            if let page = vm.selectedPage { Task { await vm.loadContent(page: page, appState: appState) } }
        }
    }

    // MARK: - Article List Pane (KB-style)

    private var articleListPane: some View {
        VStack(spacing: 0) {
            // Header
            BrowserSidebarHeader(title: "Confluence", isLoading: vm.isLoadingSpaces || vm.isLoadingPages) {
                Task { await vm.loadSpaces(appState: appState, forceRefresh: true) }
            }

            IntegrationHealthBadge(serviceName: "Confluence", status: appState.confluenceAuthStatus)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            IntegrationHealthBanner(service: "Confluence", status: appState.confluenceAuthStatus, settingsTab: "confluence", appState: appState)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search…", text: $pageFilter)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !pageFilter.isEmpty {
                    Button { pageFilter = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.caption)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
            .overlay(Divider(), alignment: .bottom)

            // Space filter chips
            if vm.spaces.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        spaceChip(nil, label: "All", tooltip: "Show all spaces")
                        ForEach(vm.spaces) { space in
                            spaceChip(space.key, label: space.key, tooltip: space.name)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }

            Divider()

            // Error
            if let err = vm.error {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .padding(8)
            }

            // Page list
            if vm.spaces.isEmpty && !vm.isLoadingSpaces {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.richtext").font(.title).foregroundStyle(.secondary)
                    Text("No spaces found").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }.padding()
            } else {
                let allPages = filteredPages
                if allPages.isEmpty && !vm.isLoadingPages {
                    VStack {
                        Spacer()
                        let trimmedFilter = pageFilter.trimmingCharacters(in: .whitespaces)
                        Text(trimmedFilter.isEmpty ? "Click a space to load pages" : "No results for \"\(trimmedFilter)\"")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(selection: $vm.selectedPage) {
                        // Group by space
                        let grouped = Dictionary(grouping: allPages, by: { $0.spaceKey })
                        let spaceKeys = grouped.keys.sorted()

                        ForEach(spaceKeys, id: \.self) { spaceKey in
                            let pages = grouped[spaceKey] ?? []
                            Section(isExpanded: sectionBinding(spaceKey)) {
                                ForEach(Array(pages.enumerated()), id: \.element.id) { idx, page in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(page.title).font(.callout).lineLimit(2)
                                        Text("\(page.lastModified.isEmpty ? "" : page.lastModified + " · ")\(page.authorName)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .tag(page)
                                    .listRowBackground(idx.isMultiple(of: 2)
                                        ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                        : Color.clear)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                                    Text(spaceName(for: spaceKey)).font(.caption.bold())
                                    Spacer()
                                    Text("\(pages.count)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleSection(spaceKey)
                                    // Auto-load pages when first expanding
                                    if !collapsedSections.contains(spaceKey) && vm.pagesForSpace(spaceKey).isEmpty {
                                        if let space = vm.spaces.first(where: { $0.key == spaceKey }) {
                                            vm.selectedSpace = space
                                            Task { await vm.loadPages(space: space, appState: appState) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
    }

    // MARK: - Filtered Pages

    private var filteredPages: [ConfluenceService.ConfluencePage] {
        let allPages: [ConfluenceService.ConfluencePage]
        if let spaceKey = selectedSpaceFilter {
            allPages = vm.pagesForSpace(spaceKey)
        } else {
            allPages = vm.pagesBySpace.values.flatMap { $0 }
        }
        let trimmed = pageFilter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allPages.sorted { $0.title < $1.title } }
        let q = trimmed.lowercased()
        return allPages.filter {
            $0.title.lowercased().contains(q) || $0.authorName.lowercased().contains(q)
        }.sorted { $0.title < $1.title }
    }

    // MARK: - Space Chip

    private func spaceChip(_ key: String?, label: String, tooltip: String) -> some View {
        Button {
            selectedSpaceFilter = key
            // Auto-load pages if selecting a specific space
            if let key, vm.pagesForSpace(key).isEmpty, let space = vm.spaces.first(where: { $0.key == key }) {
                vm.selectedSpace = space
                Task { await vm.loadPages(space: space, appState: appState) }
            }
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selectedSpaceFilter == key
                    ? Color.accentColor.opacity(0.15)
                    : Color.secondary.opacity(0.1)))
                .foregroundStyle(selectedSpaceFilter == key ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func spaceName(for key: String) -> String {
        if let space = vm.spaces.first(where: { $0.key == key }) {
            return "\(space.key) — \(space.name)"
        }
        return key
    }

    // MARK: - Section Helpers

    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(key) },
            set: { if $0 { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
        )
    }

    private func toggleSection(_ key: String) {
        withAnimation { if collapsedSections.contains(key) { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
    }

    // MARK: - Empty Content Pane

    private var emptyContentPane: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.richtext").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Select a page to read").font(.headline).foregroundStyle(.secondary)

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
            .padding().frame(maxWidth: 500)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))

            if let aiErr = vm.aiError {
                Label(aiErr, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
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
                    ScrollView { MarkdownView(markdown: draft).frame(minHeight: 200).padding(12) }
                        .frame(maxHeight: 400)
                }
                .padding().frame(maxWidth: 700)
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.3)))
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Page Content Pane

    private func pageContentPane(page: ConfluenceService.ConfluencePage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                AIAnalysisBox(text: analysis, onDismiss: { vm.aiAnalysis = nil })
                    .padding(.horizontal, 16).padding(.top, 8)
            }

            // Page content — HTML fetched via API, rendered locally (no SSO needed)
            if vm.isLoadingContent {
                VStack { Spacer(); ProgressView("Loading page…"); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.pageContent.isEmpty {
                ConfluenceHTMLView(html: vm.pageContent, baseURL: appState.jiraBaseURL)
                    .id(page.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack { Spacer(); Text("No content loaded").foregroundStyle(.secondary); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Confluence HTML Renderer
//
// Renders Confluence page HTML fetched via API in a local WKWebView.
// No SSO login needed — the API token handles authentication.
// Uses Atlassian-inspired CSS for a modern, native look.

struct ConfluenceHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        loadContent(into: wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        loadContent(into: wv)
    }

    private func loadContent(into wv: WKWebView) {
        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --text: #172B4D;
            --text-secondary: #626F86;
            --bg: #FFFFFF;
            --bg-subtle: #F7F8F9;
            --border: #DFE1E6;
            --link: #0052CC;
            --code-bg: #F4F5F7;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --text: #DEE4EA;
                --text-secondary: #9FADBC;
                --bg: #1D2125;
                --bg-subtle: #22272B;
                --border: #3B3F45;
                --link: #579DFF;
                --code-bg: #282E33;
            }
        }
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            font-size: 14px;
            line-height: 1.714;
            color: var(--text);
            background: var(--bg);
            margin: 0;
            padding: 24px 32px;
            -webkit-font-smoothing: antialiased;
        }
        h1 { font-size: 24px; font-weight: 600; margin: 24px 0 8px; }
        h2 { font-size: 20px; font-weight: 600; margin: 20px 0 8px; border-bottom: 1px solid var(--border); padding-bottom: 4px; }
        h3 { font-size: 16px; font-weight: 600; margin: 16px 0 6px; }
        h4 { font-size: 14px; font-weight: 600; margin: 12px 0 4px; }
        p { margin: 8px 0; }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; height: auto; border-radius: 4px; margin: 8px 0; }
        ul, ol { padding-left: 24px; margin: 8px 0; }
        li { margin: 2px 0; }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 12px 0;
            font-size: 13px;
        }
        th, td {
            border: 1px solid var(--border);
            padding: 8px 12px;
            text-align: left;
            vertical-align: top;
        }
        th {
            background: var(--bg-subtle);
            font-weight: 600;
            color: var(--text-secondary);
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.04em;
        }
        tr:nth-child(even) td { background: var(--bg-subtle); }
        code {
            background: var(--code-bg);
            padding: 1px 6px;
            border-radius: 3px;
            font-family: 'SF Mono', Menlo, Monaco, monospace;
            font-size: 12px;
        }
        pre {
            background: var(--code-bg);
            padding: 16px;
            border-radius: 6px;
            overflow-x: auto;
            font-family: 'SF Mono', Menlo, Monaco, monospace;
            font-size: 12px;
            line-height: 1.5;
            margin: 12px 0;
        }
        pre code { padding: 0; background: none; }
        blockquote {
            border-left: 3px solid var(--link);
            margin: 12px 0;
            padding: 4px 16px;
            color: var(--text-secondary);
        }
        hr { border: none; border-top: 1px solid var(--border); margin: 16px 0; }
        .confluence-information-macro,
        .confluence-information-macro-body,
        .panel { background: var(--bg-subtle); border-radius: 6px; padding: 12px 16px; margin: 12px 0; }
        .aui-lozenge, .status-lozenge { display: inline-block; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        wv.loadHTMLString(wrapped, baseURL: URL(string: baseURL))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        // Open clicked links in the system browser
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}


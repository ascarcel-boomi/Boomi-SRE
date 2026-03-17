import SwiftUI
import WebKit

struct ConfluenceBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ConfluenceBrowserViewModel()
    @State private var collapsedSections: Set<String> = []
    @State private var pageFilter: String = ""
    @State private var selectedSpaceFilter: String? = nil  // nil = all spaces

    var body: some View {
        HSplitView {
            // Left: sidebar (matches KB layout)
            articleListPane
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 380)
                .background(Color(nsColor: .controlBackgroundColor))

            // Right: page content
            if let page = vm.selectedPage {
                pageContentPane(page: page)
                    .frame(maxWidth: .infinity)
            } else {
                emptyContentPane
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

    // MARK: - Article List Pane (KB-style)

    private var articleListPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Confluence").font(.headline)
                Spacer()
                if vm.isLoadingSpaces || vm.isLoadingPages { ProgressView().scaleEffect(0.7) }
                Button { Task { await vm.loadSpaces(appState: appState) } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

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
                        spaceChip(nil, label: "All")
                        ForEach(vm.spaces) { space in
                            spaceChip(space.key, label: space.key)
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
                        Text(pageFilter.isEmpty ? "Click a space to load pages" : "No results for \"\(pageFilter)\"")
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
        guard !pageFilter.isEmpty else { return allPages.sorted { $0.title < $1.title } }
        let q = pageFilter.lowercased()
        return allPages.filter {
            $0.title.lowercased().contains(q) || $0.authorName.lowercased().contains(q)
        }.sorted { $0.title < $1.title }
    }

    // MARK: - Space Chip

    private func spaceChip(_ key: String?, label: String) -> some View {
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

            // Page content — rendered HTML from API (no SSO login needed)
            if vm.isLoadingContent {
                VStack { Spacer(); ProgressView("Loading page…"); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.pageContent.isEmpty {
                RenderedHTMLView(html: vm.pageContent, baseURL: appState.jiraBaseURL)
                    .id(page.id)  // force re-render when page changes
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack { Spacer(); Text("No content loaded").foregroundStyle(.secondary); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Rendered HTML View (from API content, no SSO needed)

private struct RenderedHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")  // transparent bg
        loadHTML(into: wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        loadHTML(into: wv)
    }

    private func loadHTML(into wv: WKWebView) {
        let styledHTML = """
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px;
               color: #e0e0e0; background: transparent; padding: 16px; line-height: 1.6; }
        @media (prefers-color-scheme: light) { body { color: #333; } }
        a { color: #5B8DEF; } img { max-width: 100%; height: auto; }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid #444; padding: 6px 10px; text-align: left; }
        th { background: rgba(128,128,128,0.15); }
        pre, code { background: rgba(128,128,128,0.1); padding: 2px 5px; border-radius: 3px; font-size: 13px; }
        pre { padding: 12px; overflow-x: auto; }
        h1, h2, h3, h4 { margin-top: 16px; }
        </style></head><body>\(html)</body></html>
        """
        wv.loadHTMLString(styledHTML, baseURL: URL(string: baseURL))
    }
}


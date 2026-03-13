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
                if let url = URL(string: page.url) {
                    Link(destination: url) { Label("Confluence", systemImage: "safari") }
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

            // Render mode picker
            Picker("View", selection: $confluenceRenderMode) {
                Text("Rendered").tag(0)
                Text("Plain Text").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider()

            // Page content
            if vm.isLoadingContent {
                VStack { Spacer(); ProgressView("Loading page..."); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if confluenceRenderMode == 0 {
                ConfluenceHTMLView(
                    html: vm.pageContent,
                    baseURL: URL(string: appState.jiraBaseURL + "/wiki")
                )
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

// MARK: - Confluence HTML WebView

struct ConfluenceHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero)
        loadContent(into: wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        loadContent(into: wv)
    }

    private func loadContent(into wv: WKWebView) {
        let wrapped = """
        <!DOCTYPE html><html><head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px; line-height: 1.6; padding: 20px; max-width: 900px; }
        @media (prefers-color-scheme: dark) { body { background: #1e1e1e; color: #d4d4d4; } a { color: #6cb6ff; } }
        code, pre { font-family: monospace; background: rgba(128,128,128,0.15); padding: 2px 6px; border-radius: 3px; }
        pre { padding: 12px; overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; }
        td, th { border: 1px solid rgba(128,128,128,0.3); padding: 8px; }
        </style></head><body>\(html)</body></html>
        """
        wv.loadHTMLString(wrapped, baseURL: baseURL)
    }
}

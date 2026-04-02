import SwiftUI
import WebKit

struct KnowledgeBaseView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var vm: KnowledgeBaseViewModel
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        HSplitView {
            // Left pane: article list
            articleListPane
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right pane: article content
            articleContentPane
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let stale = vm.lastFetched.map { Date().timeIntervalSince($0) > 300 } ?? true
            if vm.articles.isEmpty || stale {
                Task { await vm.loadArticles(appState: appState) }
            }
        }
        .onChange(of: appState.activeProductIds) {
            vm.applyProductFilter(appState: appState)
        }
        .sheet(isPresented: $vm.showSOPCreator) {
            SOPCreatorView()
                .environmentObject(appState)
        }
    }

    // MARK: - Article List Pane

    private var articleListPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Knowledge Base").font(.headline)
                Spacer()
                Button {
                    Task { await vm.refresh(appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
                .help("Refresh from GitHub")

                Button {
                    vm.showSOPCreator = true
                } label: {
                    Image(systemName: "plus").font(.caption)
                }
                .buttonStyle(.plain)
                .help("New SOP")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search…", text: $vm.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !vm.searchQuery.isEmpty {
                    Button { vm.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
            .overlay(Divider(), alignment: .bottom)

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, label: "All")
                    ForEach(KnowledgeBaseService.KBCategory.allCases, id: \.rawValue) { cat in
                        categoryChip(cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }

            Divider()

            if vm.isLoading {
                VStack { Spacer(); ProgressView("Loading KB…").scaleEffect(0.9); Spacer() }
            } else if let err = vm.error {
                VStack(spacing: 8) {
                    Spacer()
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.refresh(appState: appState) } }
                        .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }
                .padding()
            } else if vm.filteredArticles.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    if vm.articles.isEmpty {
                        Text("No articles loaded")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !vm.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("No results for \"\(vm.searchQuery)\"")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No articles match the current filter")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                List(selection: Binding(
                    get: { vm.selectedArticle?.id },
                    set: { id in vm.selectedArticle = vm.articles.first { $0.id == id } }
                )) {
                    ForEach(vm.articlesByCategory, id: \.0) { (category, articles) in
                        Section(isExpanded: sectionBinding(category.rawValue)) {
                            ForEach(Array(articles.enumerated()), id: \.element.id) { idx, article in
                                articleRow(article)
                                    .tag(article.id)
                                    .listRowBackground(idx.isMultiple(of: 2)
                                        ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                        : Color.clear)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon).font(.caption)
                                Text(category.rawValue)
                                    .font(.caption.bold())
                                Spacer()
                                Text("\(articles.count)").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSection(category.rawValue) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
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

    private func categoryChip(_ cat: KnowledgeBaseService.KBCategory?, label: String) -> some View {
        Button { vm.categoryFilter = cat } label: {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(
                    vm.categoryFilter == cat ? Color.accentColor : Color.secondary.opacity(0.1)
                ))
                .foregroundStyle(vm.categoryFilter == cat ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func articleRow(_ article: KnowledgeBaseService.KBArticle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(article.title)
                .font(.callout)
                .lineLimit(2)
            Text(article.category.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Article Content Pane

    private var articleContentPane: some View {
        Group {
            if let article = vm.selectedArticle {
                articleDetailView(article)
            } else {
                emptyContentView
            }
        }
    }

    private var emptyContentView: some View {
        Group {
            if vm.isLoadingReadme {
                VStack {
                    Spacer()
                    ProgressView("Loading README…").scaleEffect(0.9)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let readme = vm.readmeContent {
                // Show README as KB landing page
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("README")
                                .font(.title3.bold())
                            Text("\(appState.kbRepoOwner)/\(appState.kbRepoName)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            let url = "https://github.com/\(appState.kbRepoOwner)/\(appState.kbRepoName)/blob/main/README.md"
                            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                        } label: {
                            Label("Open on GitHub", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)

                    Divider()

                    ScrollView {
                        MarkdownView(markdown: readme)
                            .frame(minHeight: 300)
                            .padding(20)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "book.closed")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Select an article to read")
                        .font(.callout).foregroundStyle(.secondary)
                    if vm.articles.isEmpty && !vm.isLoading {
                        Button("Load Knowledge Base") {
                            Task { await vm.loadArticles(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func articleDetailView(_ article: KnowledgeBaseService.KBArticle) -> some View {
        VStack(spacing: 0) {
            // Article header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.title3.bold())
                    HStack(spacing: 8) {
                        Text(article.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        Text(article.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                // "Generate PCR from SOP" if it's a SOP
                if article.category == .sop {
                    Button {
                        vm.pcrSOP = article
                    } label: {
                        Label("Generate PCR", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Generate a PCR using this SOP as the procedure template")
                }

                Button {
                    NSWorkspace.shared.open(URL(string: article.htmlURL)!)
                } label: {
                    Label("Open on GitHub", systemImage: "safari")
                }
                .buttonStyle(.bordered)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(article.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy markdown")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider()

            // Article content
            ScrollView {
                MarkdownView(markdown: article.content)
                    .frame(minHeight: 300)
                    .padding(20)
            }
        }
    }
}

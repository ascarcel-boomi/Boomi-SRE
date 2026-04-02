import Foundation
import SwiftUI

@MainActor
final class KnowledgeBaseViewModel: ObservableObject {
    @Published var articles: [KnowledgeBaseService.KBArticle] = []
    @Published var filteredArticles: [KnowledgeBaseService.KBArticle] = []
    @Published var selectedArticle: KnowledgeBaseService.KBArticle?
    @Published var searchQuery: String = "" {
        didSet { applySearch() }
    }
    @Published var categoryFilter: KnowledgeBaseService.KBCategory? = nil {
        didSet { applySearch() }
    }
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastFetched: Date?

    // README landing page
    @Published var readmeContent: String?
    @Published var isLoadingReadme = false

    // SOP Creator
    @Published var showSOPCreator = false

    // PCR Generator — pre-selected SOP
    @Published var pcrSOP: KnowledgeBaseService.KBArticle? = nil

    private let service = KnowledgeBaseService()

    func loadArticles(appState: AppState) async {
        guard !appState.githubToken.isEmpty else {
            error = "GitHub token not configured — add it in Settings → GitHub"
            return
        }
        // Don't refetch if fresh (< 5 minutes old)
        if let last = lastFetched, Date().timeIntervalSince(last) < 300, !articles.isEmpty {
            return
        }
        isLoading = true
        error = nil
        do {
            articles = try await service.fetchArticles(
                owner: appState.kbRepoOwner,
                repo: appState.kbRepoName,
                token: appState.githubToken
            )
            lastFetched = Date()
            applySearch(appState: appState)
        } catch {
            self.error = "Failed to load KB from \(appState.kbRepoOwner)/\(appState.kbRepoName): \(error.localizedDescription)"
        }
        isLoading = false
        // Fetch README in the background if not already loaded
        if readmeContent == nil {
            await loadReadme(appState: appState)
        }
    }

    func loadReadme(appState: AppState) async {
        guard !appState.githubToken.isEmpty else { return }
        isLoadingReadme = true
        do {
            let readme = try await service.fetchArticle(
                owner: appState.kbRepoOwner,
                repo: appState.kbRepoName,
                path: "README.md",
                token: appState.githubToken
            )
            readmeContent = readme.content
        } catch {
            // README not found — not a hard error; just leave nil
            readmeContent = nil
        }
        isLoadingReadme = false
    }

    func refresh(appState: AppState) async {
        lastFetched = nil
        readmeContent = nil
        await loadArticles(appState: appState)
    }

    var articlesByCategory: [(KnowledgeBaseService.KBCategory, [KnowledgeBaseService.KBArticle])] {
        KnowledgeBaseService.KBCategory.allCases.compactMap { cat in
            let catArticles = filteredArticles.filter { $0.category == cat }
            return catArticles.isEmpty ? nil : (cat, catArticles)
        }
    }

    /// Apply product KB tag filter after loading articles.
    func applyProductFilter(appState: AppState) {
        applySearch(appState: appState)
    }

    private func applySearch(appState: AppState? = nil) {
        var result = articles
        // Product KB tag filter
        if let appState, !appState.activeProductIds.isEmpty {
            let kbTags = appState.products
                .filter { appState.activeProductIds.contains($0.id) }
                .flatMap { $0.kbTags }
            if !kbTags.isEmpty {
                result = result.filter { article in
                    kbTags.contains { tag in
                        article.title.lowercased().contains(tag.lowercased()) ||
                        article.path.lowercased().contains(tag.lowercased())
                    }
                }
            }
        }
        // Category filter
        if let cat = categoryFilter {
            result = result.filter { $0.category == cat }
        }
        // Text search
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.content.lowercased().contains(q)
            }
        }
        filteredArticles = result
    }
}

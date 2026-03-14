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
            applySearch()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh(appState: AppState) async {
        lastFetched = nil
        await loadArticles(appState: appState)
    }

    var articlesByCategory: [(KnowledgeBaseService.KBCategory, [KnowledgeBaseService.KBArticle])] {
        KnowledgeBaseService.KBCategory.allCases.compactMap { cat in
            let catArticles = filteredArticles.filter { $0.category == cat }
            return catArticles.isEmpty ? nil : (cat, catArticles)
        }
    }

    private func applySearch() {
        var result = articles
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

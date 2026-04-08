import Foundation
import SwiftUI

@Observable
@MainActor
final class ConfluenceBrowserViewModel: AIAnalyzable {
    var spaces: [ConfluenceSpaceSummary] = []
    var selectedSpace: ConfluenceSpaceSummary?
    var pages: [ConfluenceService.ConfluencePage] = []
    var pagesBySpace: [String: [ConfluenceService.ConfluencePage]] = [:]
    var selectedPage: ConfluenceService.ConfluencePage?
    var pageContent: String = ""         // raw HTML for WebView
    var pageContentPlainText: String = "" // stripped text for AI
    var searchQuery: String = ""
    var searchResults: [ConfluenceService.ConfluencePage] = []
    var isLoadingSpaces = false
    var isLoadingPages = false
    var isLoadingContent = false
    var isSearching = false
    var error: String?
    var lastFetched: Date?
    // AI
    var aiAnalysis: String?
    var isAnalyzing = false
    var aiError: String?
    var draftPrompt: String = ""
    var draftedPage: String?
    var isDrafting = false

    @ObservationIgnored private let confluenceService = ConfluenceService()
    @ObservationIgnored private let claudeService     = ClaudeService()
    @ObservationIgnored private var depthHint: String = ""
    @ObservationIgnored private let cacheTTL: TimeInterval = 300  // 5 minutes

    // Per-space page fetch timestamps
    @ObservationIgnored private var lastPagesFetched: [String: Date] = [:]
    // Per-page content cache: pageId -> (html, plainText)
    @ObservationIgnored private var contentCache: [String: (html: String, plainText: String, fetchedAt: Date)] = [:]

    func loadSpaces(appState: AppState, forceRefresh: Bool = false) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
        guard !appState.confluenceAPIToken.isEmpty else {
            error = "Confluence not configured. Add credentials in Settings."; return
        }
        // Skip if cache is fresh (unless force-refreshing)
        if !forceRefresh, !spaces.isEmpty,
           let fetched = lastFetched, Date().timeIntervalSince(fetched) < cacheTTL {
            return
        }
        isLoadingSpaces = true; error = nil
        do {
            var fetchedSpaces = try await confluenceService.fetchSpaces(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken
            )
            let activeSpaces = appState.activeConfluenceSpaces
            if !activeSpaces.isEmpty { fetchedSpaces = fetchedSpaces.filter { activeSpaces.contains($0.key) } }
            spaces = fetchedSpaces
        } catch { self.error = error.localizedDescription }
        isLoadingSpaces = false
        lastFetched = Date()
    }

    func loadPages(space: ConfluenceSpaceSummary, appState: AppState, forceRefresh: Bool = false) async {
        selectedSpace = space; aiAnalysis = nil
        // Skip if cache is fresh
        if !forceRefresh,
           let cached = pagesBySpace[space.key], !cached.isEmpty,
           let fetched = lastPagesFetched[space.key], Date().timeIntervalSince(fetched) < cacheTTL {
            pages = cached  // backward compat
            return
        }
        pageContent = ""
        isLoadingPages = true; error = nil
        do {
            let fetched = try await confluenceService.listPages(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken,
                spaceKey: space.key
            )
            pagesBySpace[space.key] = fetched
            lastPagesFetched[space.key] = Date()
            pages = fetched  // backward compat
            if fetched.isEmpty {
                self.error = "No pages found in \(space.key). The space may be empty or require additional permissions."
            }
        } catch {
            self.error = "Failed to load pages for \(space.key): \(error.localizedDescription)"
        }
        isLoadingPages = false
    }

    /// Get pages for a specific space (from cache).
    func pagesForSpace(_ spaceKey: String) -> [ConfluenceService.ConfluencePage] {
        pagesBySpace[spaceKey] ?? []
    }

    func loadContent(page: ConfluenceService.ConfluencePage, appState: AppState, forceRefresh: Bool = false) async {
        selectedPage = page; aiAnalysis = nil
        // Check content cache
        if !forceRefresh,
           let cached = contentCache[page.id],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            pageContent = cached.html
            pageContentPlainText = cached.plainText
            return
        }
        pageContent = ""; pageContentPlainText = ""
        isLoadingContent = true
        do {
            // pageContent stores HTML for rendered WebView display
            pageContent = try await confluenceService.getPageContent(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken,
                pageId: page.id
            )
            // Also compute plain text for AI summarization
            pageContentPlainText = try await confluenceService.getPageContentPlainText(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken,
                pageId: page.id
            )
            // Cache the result
            contentCache[page.id] = (html: pageContent, plainText: pageContentPlainText, fetchedAt: Date())
        } catch { self.error = error.localizedDescription }
        isLoadingContent = false
    }

    func search(appState: AppState) async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        do {
            searchResults = try await confluenceService.searchPages(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken,
                query: q
            )
        } catch { self.error = error.localizedDescription }
        isSearching = false
    }

    // MARK: - AI

    func summarizePage() async {
        guard let page = selectedPage, !pageContent.isEmpty else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        let content = String(pageContentPlainText.prefix(4000))

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Summarize this Confluence page for an SRE engineer.

            Page: \(page.title)
            Space: \(page.spaceKey)
            Last modified: \(page.lastModified) by \(page.authorName)
            URL: \(page.url)

            CONTENT:
            \(content)

            Provide:
            1. **TL;DR** — 2–3 sentence summary
            2. **Key Points** — bullet list of the most important information
            3. **Action Items** — any explicit tasks, follow-ups, or procedures described
            4. **Related Topics** — what other pages or systems this likely connects to
            """)],
            systemPrompt: "You are an SRE summarizing Confluence documentation. Be concise and focus on actionable information." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 768
        )
        if self.aiError == nil { ProductivityTracker.shared.log(.aiPageSummarize, source: "Confluence") }
    }

    func draftNewPage() async {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        isDrafting = true; aiError = nil; draftedPage = nil

        do {
            draftedPage = try await claudeService.chat(
                messages: [("user", """
                Draft a Confluence page for Boomi's APIM SRE team.

                Topic/Prompt: \(prompt)

                Write a well-structured Confluence page using markdown formatting:
                - Use ## for section headings
                - Use - for bullet lists
                - Use numbered lists for procedures
                - Use ``` for code blocks and commands
                - Include an overview, main content sections, and a footer with author/date placeholders

                The page should be ready to paste directly into Confluence.
                """)],
                systemPrompt: "You are an experienced SRE technical writer. Write clear, well-structured Confluence documentation.",
                maxTokens: 2048
            )
        } catch { aiError = error.localizedDescription }
        isDrafting = false
        if draftedPage != nil { ProductivityTracker.shared.log(.aiPageDraft, source: "Confluence") }
    }
}

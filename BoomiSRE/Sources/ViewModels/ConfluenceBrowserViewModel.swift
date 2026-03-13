import Foundation
import SwiftUI

@MainActor
final class ConfluenceBrowserViewModel: ObservableObject {
    @Published var spaces: [ConfluenceSpaceSummary] = []
    @Published var selectedSpace: ConfluenceSpaceSummary?
    @Published var pages: [ConfluenceService.ConfluencePage] = []
    @Published var selectedPage: ConfluenceService.ConfluencePage?
    @Published var pageContent: String = ""         // raw HTML for WebView
    @Published var pageContentPlainText: String = "" // stripped text for AI
    @Published var searchQuery: String = ""
    @Published var searchResults: [ConfluenceService.ConfluencePage] = []
    @Published var isLoadingSpaces = false
    @Published var isLoadingPages = false
    @Published var isLoadingContent = false
    @Published var isSearching = false
    @Published var error: String?
    // AI
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?
    @Published var draftPrompt: String = ""
    @Published var draftedPage: String?
    @Published var isDrafting = false

    private let confluenceService = ConfluenceService()
    private let claudeService     = ClaudeService()

    func loadSpaces(appState: AppState) async {
        guard !appState.confluenceAPIToken.isEmpty else {
            error = "Confluence not configured. Add credentials in Settings."; return
        }
        isLoadingSpaces = true; error = nil
        do {
            spaces = try await confluenceService.fetchSpaces(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken
            )
        } catch { self.error = error.localizedDescription }
        isLoadingSpaces = false
    }

    func loadPages(space: ConfluenceSpaceSummary, appState: AppState) async {
        selectedSpace = space; pages = []; selectedPage = nil; pageContent = ""; aiAnalysis = nil
        isLoadingPages = true
        do {
            pages = try await confluenceService.listPages(
                baseURL: appState.jiraBaseURL,
                email: appState.jiraEmail,
                apiToken: appState.confluenceAPIToken,
                spaceKey: space.key
            )
        } catch { self.error = error.localizedDescription }
        isLoadingPages = false
    }

    func loadContent(page: ConfluenceService.ConfluencePage, appState: AppState) async {
        selectedPage = page; pageContent = ""; pageContentPlainText = ""; aiAnalysis = nil
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
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."; return
        }
        isAnalyzing = true; aiError = nil; aiAnalysis = nil
        let content = String(pageContentPlainText.prefix(4000))

        do {
            aiAnalysis = try await claudeService.chat(
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
                systemPrompt: "You are an SRE summarizing Confluence documentation. Be concise and focus on actionable information.",
                maxTokens: 768
            )
        } catch { aiError = error.localizedDescription }
        isAnalyzing = false
    }

    func draftNewPage() async {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }
        guard claudeService.discoverAPIKey() != nil else {
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
    }
}

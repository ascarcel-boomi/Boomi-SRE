import Foundation

// MARK: - AIAnalyzable Protocol
//
// ViewModels that run AI analysis share the same boilerplate:
//   isAnalyzing = true; aiError = nil; aiAnalysis = nil
//   do { aiAnalysis = try await claudeService.chat(...) }
//   catch { aiError = error.localizedDescription }
//   isAnalyzing = false
//
// Conforming to this protocol + calling runAIAnalysis() replaces that boilerplate.

@MainActor
protocol AIAnalyzable: ObservableObject {
    var aiAnalysis: String? { get set }
    var isAnalyzing: Bool { get set }
    var aiError: String? { get set }
}

extension AIAnalyzable {
    /// Execute a Claude chat call and write the result into aiAnalysis.
    /// Manages isAnalyzing and aiError automatically.
    func runAIAnalysis(
        using claude: ClaudeService,
        messages: [(String, String)],
        systemPrompt: String,
        maxTokens: Int = 1024
    ) async {
        isAnalyzing = true
        aiError = nil
        aiAnalysis = nil
        do {
            aiAnalysis = try await claude.chat(
                messages: messages,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens
            )
        } catch {
            aiError = error.localizedDescription
        }
        isAnalyzing = false
    }
}

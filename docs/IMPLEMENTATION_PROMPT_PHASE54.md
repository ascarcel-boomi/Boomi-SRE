# Boomi SRE App — Phase 54: Rich Markdown Rendering Across the App

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Panels/CopilotChatView.swift` — AI copilot messages (markdown from Claude)
- `BoomiSRE/Sources/Views/Panels/ExecAssistantView.swift` — Executive briefings (markdown from Claude)
- `BoomiSRE/Sources/Views/Panels/TicketDetailView.swift` — Jira ticket descriptions and AI analysis
- `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift` — incident AI analysis, postmortem drafts
- `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift` — dashboard/alert AI analysis
- `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift` — PR descriptions, AI review
- `BoomiSRE/Sources/Views/Panels/KnowledgeBaseView.swift` — KB articles (full markdown files)
- `BoomiSRE/Sources/Views/Panels/CostExplorerView.swift` — cost AI analysis
- `BoomiSRE/Sources/Views/FeedView.swift` — feed item detail text
- `BoomiSRE/Sources/Views/Widgets/WidgetViews.swift` — AI daily summary widget

---

## Problem

Every markdown rendering in the app uses:
```swift
Text((try? AttributedString(markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
     ?? AttributedString(text))
```

The `inlineOnlyPreservingWhitespace` option only renders **inline** markdown: bold, italic, links, code spans. It does NOT render:
- `# Headings` (H1-H6)
- `- Bullet lists` and `1. Numbered lists`
- ` ```code blocks``` `
- `> Block quotes`
- `---` Horizontal rules
- `| Tables |`

The result: AI analysis, executive briefings, KB articles, PR descriptions — everything looks like a wall of plain text with occasional **bold** words.

**There are 20+ files** with this pattern (see the grep results above). All need to be updated.

---

## Solution: Create a Reusable MarkdownView Component

Instead of updating 20+ files individually with complex rendering logic, create ONE reusable component and replace all occurrences.

### Phase 54A: Create MarkdownView

Create `BoomiSRE/Sources/Views/Shared/MarkdownView.swift`:

```swift
import SwiftUI
import WebKit

/// Renders markdown as properly formatted rich text using a lightweight WKWebView.
/// This handles headings, lists, code blocks, tables, blockquotes — everything that
/// SwiftUI's AttributedString(markdown:) with inlineOnly does not.
///
/// For short inline text (one line, no block elements), use the simpler
/// Text(AttributedString(markdown:)) approach. Use MarkdownView for multi-line
/// content like AI analysis, ticket descriptions, KB articles, and briefings.
struct MarkdownView: NSViewRepresentable {
    let markdown: String
    var maxHeight: CGFloat? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")  // transparent background
        wv.navigationDelegate = context.coordinator
        loadContent(wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Reload if markdown content changed
        if context.coordinator.lastMarkdown != markdown {
            context.coordinator.lastMarkdown = markdown
            loadContent(wv)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadContent(_ wv: WKWebView) {
        let html = wrapInHTML(markdown: markdown)
        wv.loadHTMLString(html, baseURL: nil)
    }

    /// Convert markdown to HTML and wrap in a styled page that matches macOS appearance.
    private func wrapInHTML(markdown: String) -> String {
        let htmlBody = markdownToHTML(markdown)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                font-size: 13px;
                line-height: 1.5;
                color: \(isDark ? "#e0e0e0" : "#333333");
                background: transparent;
                padding: 4px 0;
                -webkit-font-smoothing: antialiased;
            }
            h1 { font-size: 20px; font-weight: 700; margin: 16px 0 8px 0; color: \(isDark ? "#ffffff" : "#1a1a1a"); }
            h2 { font-size: 17px; font-weight: 700; margin: 14px 0 6px 0; color: \(isDark ? "#ffffff" : "#1a1a1a"); }
            h3 { font-size: 15px; font-weight: 600; margin: 12px 0 4px 0; color: \(isDark ? "#f0f0f0" : "#222222"); }
            h4, h5, h6 { font-size: 14px; font-weight: 600; margin: 10px 0 4px 0; }
            p { margin: 6px 0; }
            ul, ol { margin: 6px 0 6px 20px; }
            li { margin: 3px 0; }
            strong { font-weight: 600; color: \(isDark ? "#ffffff" : "#000000"); }
            em { font-style: italic; }
            code {
                font-family: "SF Mono", Menlo, Monaco, monospace;
                font-size: 12px;
                background: \(isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)");
                padding: 1px 5px;
                border-radius: 4px;
            }
            pre {
                margin: 8px 0;
                padding: 10px 12px;
                background: \(isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)");
                border-radius: 8px;
                overflow-x: auto;
            }
            pre code {
                background: none;
                padding: 0;
                font-size: 12px;
                line-height: 1.4;
            }
            blockquote {
                margin: 8px 0;
                padding: 6px 12px;
                border-left: 3px solid \(isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.15)");
                color: \(isDark ? "#aaaaaa" : "#666666");
            }
            table {
                border-collapse: collapse;
                margin: 8px 0;
                width: 100%;
            }
            th, td {
                border: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.1)");
                padding: 6px 10px;
                text-align: left;
                font-size: 12px;
            }
            th {
                font-weight: 600;
                background: \(isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.03)");
            }
            hr {
                border: none;
                border-top: 1px solid \(isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)");
                margin: 12px 0;
            }
            a {
                color: \(isDark ? "#6eb5ff" : "#0066cc");
                text-decoration: none;
            }
            a:hover { text-decoration: underline; }
            img { max-width: 100%; border-radius: 6px; }
        </style>
        </head>
        <body>\(htmlBody)</body>
        </html>
        """
    }

    /// Basic markdown-to-HTML converter.
    /// Handles: headings, bold, italic, code blocks, inline code, lists, blockquotes, tables, links, horizontal rules.
    private func markdownToHTML(_ md: String) -> String {
        var lines = md.components(separatedBy: "\n")
        var html = ""
        var inCodeBlock = false
        var inList = false
        var inOrderedList = false
        var inTable = false

        for i in 0..<lines.count {
            var line = lines[i]

            // Code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    html += "<pre><code>"
                }
                continue
            }
            if inCodeBlock {
                html += escapeHTML(line) + "\n"
                continue
            }

            // Close lists if the line doesn't continue them
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inList && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("* ") && !trimmed.hasPrefix("+ ") && !trimmed.isEmpty {
                html += "</ul>\n"; inList = false
            }
            if inOrderedList && !trimmed.matches(of: /^\d+\.\s/).isEmpty == false && !trimmed.isEmpty {
                // Check properly
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html += "<hr>\n"; continue
            }

            // Headings
            if trimmed.hasPrefix("######ufeff") { /* ignore BOM issues */ }
            if let match = trimmed.range(of: #"^(#{1,6})\s+(.+)"#, options: .regularExpression) {
                let full = String(trimmed[match])
                let hashes = full.prefix(while: { $0 == "#" })
                let level = hashes.count
                let text = String(full.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                html += "<h\(level)>\(inlineMarkdown(text))</h\(level)>\n"
                continue
            }

            // Unordered list items
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                if !inList { html += "<ul>\n"; inList = true }
                let text = String(trimmed.dropFirst(2))
                html += "<li>\(inlineMarkdown(text))</li>\n"
                continue
            }

            // Ordered list items
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                if !inOrderedList { html += "<ol>\n"; inOrderedList = true }
                let text = trimmed.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                html += "<li>\(inlineMarkdown(text))</li>\n"
                continue
            }
            if inOrderedList && (trimmed.isEmpty || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) == nil) {
                html += "</ol>\n"; inOrderedList = false
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                let text = String(trimmed.dropFirst(2))
                html += "<blockquote>\(inlineMarkdown(text))</blockquote>\n"
                continue
            }

            // Table rows
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                // Skip separator rows (|---|---|)
                if trimmed.contains("---") { continue }
                if !inTable { html += "<table>\n"; inTable = true }
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let tag = html.contains("<table>\n") && !html.contains("<td>") ? "th" : "td"
                html += "<tr>" + cells.map { "<\(tag)>\(inlineMarkdown($0))</\(tag)>" }.joined() + "</tr>\n"
                continue
            }
            if inTable && !trimmed.hasPrefix("|") {
                html += "</table>\n"; inTable = false
            }

            // Empty line
            if trimmed.isEmpty {
                html += "<br>\n"; continue
            }

            // Regular paragraph
            html += "<p>\(inlineMarkdown(trimmed))</p>\n"
        }

        // Close any open blocks
        if inCodeBlock { html += "</code></pre>\n" }
        if inList { html += "</ul>\n" }
        if inOrderedList { html += "</ol>\n" }
        if inTable { html += "</table>\n" }

        return html
    }

    /// Render inline markdown: bold, italic, code, links
    private func inlineMarkdown(_ text: String) -> String {
        var result = escapeHTML(text)
        // Bold: **text** or __text__
        result = result.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic: *text* or _text_
        result = result.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<!\w)_(.+?)_(?!\w)"#, with: "<em>$1</em>", options: .regularExpression)
        // Inline code: `code`
        result = result.replacingOccurrences(of: #"`(.+?)`"#, with: "<code>$1</code>", options: .regularExpression)
        // Links: [text](url)
        result = result.replacingOccurrences(of: #"\[(.+?)\]\((.+?)\)"#, with: "<a href=\"$2\" target=\"_blank\">$1</a>", options: .regularExpression)
        return result
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String = ""

        // Open links in system browser, not the WebView
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
```

**Also create a simpler SwiftUI-native version** for short text where a WebView would be overkill:

```swift
/// For short markdown (1-3 lines), use SwiftUI's native AttributedString with FULL syntax.
/// This is lighter than MarkdownView but doesn't handle code blocks or tables well.
struct InlineMarkdownText: View {
    let text: String

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text,
              options: .init(interpretedSyntax: .full))) // ← .full, not .inlineOnlyPreservingWhitespace
        ?? AttributedString(text)
    }
}
```

**Key difference:** `.interpretedSyntax: .full` enables block-level rendering in SwiftUI's native Text. This handles headings, lists, and basic formatting. It's not as pretty as the WebView version but it's much better than `inlineOnlyPreservingWhitespace`. Use this for AI analysis panels, feed item details, and other medium-length content. Use the full `MarkdownView` (WebView) for KB articles, full ticket descriptions, and long-form content.

### Phase 54B: Replace All inlineOnlyPreservingWhitespace Occurrences

Search the entire `Sources/` directory for `inlineOnlyPreservingWhitespace` and replace each occurrence. Use this decision tree:

**Use `MarkdownView` (WebView) for:**
- KB article content (KnowledgeBaseView) — long documents with headings, code blocks, tables
- Full ticket descriptions (TicketDetailView description tab)
- AI postmortem drafts (IncidentCommandView)
- SOP drafts (SOPCreatorView)
- Confluence page content (already uses WebView for rendered mode)
- Executive briefing content (ExecAssistantView) — structured reports with headings

**Use `InlineMarkdownText` (`.full` syntax) for:**
- AI analysis panels in all browser views (Grafana, GitHub, Jenkins, Bitbucket, Cost Explorer)
- Copilot chat messages (CopilotChatView)
- Feed item detail text (FeedView)
- Notification detail text (NotificationDetailPane)
- Widget summary text (WidgetViews — AI daily summary)
- Board/filter view markdown (BoardsView)
- AI bar expanded chat messages (AIBar)

**For each replacement:**

```swift
// OLD (everywhere):
Text((try? AttributedString(markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
     ?? AttributedString(text))

// NEW (short/medium content — AI analysis, chat messages):
InlineMarkdownText(text: text)

// NEW (long-form content — KB articles, full descriptions, postmortems):
MarkdownView(markdown: text)
    .frame(minHeight: 200)  // give the WebView enough space
```

### Phase 54C: Handle Dark/Light Mode Switching

The `MarkdownView`'s HTML CSS uses `NSApp.effectiveAppearance` at render time. When the user switches macOS dark/light mode, the WebView should re-render:

```swift
// In MarkdownView, observe appearance changes:
func updateNSView(_ wv: WKWebView, context: Context) {
    let currentAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
    if context.coordinator.lastMarkdown != markdown || context.coordinator.lastAppearance != currentAppearance {
        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastAppearance = currentAppearance
        loadContent(wv)
    }
}
```

### Phase 54D: Style the Boomi Theme Colors in Markdown

When Boomi theme is active, use Boomi brand colors in the HTML CSS:
- Heading colors → `BoomiColors.deepNavy` (or white in dark mode)
- Link colors → `BoomiColors.boomiPurple`
- Code background → subtle Boomi Purple tint
- Blockquote border → `BoomiColors.boomiPurple`

Pass the theme info into `wrapInHTML()` and adjust the CSS accordingly.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Rich markdown rendering — headings, lists, code blocks, tables across all views"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

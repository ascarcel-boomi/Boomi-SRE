import SwiftUI
import WebKit

/// Renders markdown as properly formatted rich text using a lightweight WKWebView.
/// Handles headings, lists, code blocks, tables, blockquotes — everything that
/// SwiftUI's AttributedString(markdown:) with inlineOnly does not.
///
/// Use for long-form content: KB articles, ticket descriptions, AI postmortems, exec briefings.
/// For short inline text, use InlineMarkdownText instead.
/// WKWebView subclass that forwards scroll wheel events to its superview chain
/// when `forwardScrollEvents` is true, so a parent SwiftUI ScrollView handles scrolling.
class ScrollForwardingWebView: WKWebView {
    var forwardScrollEvents = false

    override func scrollWheel(with event: NSEvent) {
        if forwardScrollEvents {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

struct MarkdownView: NSViewRepresentable {
    let markdown: String
    var appTheme: String = "system"
    /// When true, WKWebView measures its content height and disables internal scrolling,
    /// allowing a parent ScrollView to handle scrolling. When false, WKWebView scrolls internally.
    var selfSizing: Bool = false
    @Binding var contentHeight: CGFloat

    /// Convenience init without height binding (for legacy callers that manage their own frame).
    init(markdown: String, appTheme: String = "system") {
        self.markdown = markdown
        self.appTheme = appTheme
        self.selfSizing = false
        self._contentHeight = .constant(0)
    }

    /// Self-sizing init — WKWebView reports its content height and disables internal scroll.
    init(markdown: String, appTheme: String = "system", contentHeight: Binding<CGFloat>) {
        self.markdown = markdown
        self.appTheme = appTheme
        self.selfSizing = true
        self._contentHeight = contentHeight
    }

    func makeNSView(context: Context) -> ScrollForwardingWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let wv = ScrollForwardingWebView(frame: .zero, configuration: config)
        wv.forwardScrollEvents = selfSizing
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        context.coordinator.selfSizing = selfSizing
        context.coordinator.heightChanged = { newHeight in
            DispatchQueue.main.async {
                self.contentHeight = newHeight
            }
        }
        loadContent(wv)
        return wv
    }

    func updateNSView(_ wv: ScrollForwardingWebView, context: Context) {
        wv.forwardScrollEvents = selfSizing
        let currentAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if context.coordinator.lastMarkdown != markdown || context.coordinator.lastAppearance != currentAppearance {
            context.coordinator.lastMarkdown = markdown
            context.coordinator.lastAppearance = currentAppearance
            loadContent(wv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func loadContent(_ wv: WKWebView) {
        wv.loadHTMLString(wrapInHTML(markdown: markdown), baseURL: nil)
    }

    private func wrapInHTML(markdown: String) -> String {
        let htmlBody = markdownToHTML(markdown)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isBoomi = appTheme == "boomi"

        let headingColor = isDark ? "#ffffff" : (isBoomi ? "#072B55" : "#1a1a1a")
        let linkColor    = isBoomi ? "#4B4FE2" : (isDark ? "#6eb5ff" : "#0066cc")
        let quoteBar     = isBoomi ? "#4B4FE2" : (isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.15)")
        let codeInlineBg = isBoomi
            ? (isDark ? "rgba(75,79,226,0.15)" : "rgba(75,79,226,0.08)")
            : (isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)")
        let textColor    = isDark ? "#e0e0e0" : "#333333"
        let codeBg       = isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)"
        let borderColor  = isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.1)"
        let thBg         = isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.03)"
        let hrColor      = isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)"

        return """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif;
               font-size: 13px; line-height: 1.55; color: \(textColor);
               background: transparent; padding: 4px 0; -webkit-font-smoothing: antialiased;
               \(selfSizing ? "overflow: hidden;" : "") }
        h1 { font-size: 20px; font-weight: 700; margin: 16px 0 8px; color: \(headingColor); }
        h2 { font-size: 17px; font-weight: 700; margin: 14px 0 6px; color: \(headingColor); }
        h3 { font-size: 15px; font-weight: 600; margin: 12px 0 4px; color: \(headingColor); }
        h4,h5,h6 { font-size: 14px; font-weight: 600; margin: 10px 0 4px; }
        p { margin: 6px 0; }
        ul,ol { margin: 6px 0 6px 20px; }
        li { margin: 3px 0; }
        strong { font-weight: 600; color: \(isDark ? "#ffffff" : "#000000"); }
        em { font-style: italic; }
        code { font-family: "SF Mono", Menlo, Monaco, monospace; font-size: 12px;
               background: \(codeInlineBg); padding: 1px 5px; border-radius: 4px; }
        pre { margin: 8px 0; padding: 10px 12px; background: \(codeBg);
              border-radius: 8px; overflow-x: auto; }
        pre code { background: none; padding: 0; font-size: 12px; line-height: 1.4; }
        blockquote { margin: 8px 0; padding: 6px 12px;
                     border-left: 3px solid \(quoteBar);
                     color: \(isDark ? "#aaaaaa" : "#666666"); }
        table { border-collapse: collapse; margin: 8px 0; width: 100%; }
        th,td { border: 1px solid \(borderColor); padding: 6px 10px; text-align: left; font-size: 12px; }
        th { font-weight: 600; background: \(thBg); }
        hr { border: none; border-top: 1px solid \(hrColor); margin: 12px 0; }
        a { color: \(linkColor); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; border-radius: 6px; }
        </style></head>
        <body>\(htmlBody)</body></html>
        """
    }

    private func markdownToHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html = ""
        var inCodeBlock = false
        var inList = false
        var inOrderedList = false
        var inTable = false

        for line in lines {
            // Code fence
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"; inCodeBlock = false
                } else {
                    if inList        { html += "</ul>\n"; inList = false }
                    if inOrderedList { html += "</ol>\n"; inOrderedList = false }
                    if inTable       { html += "</table>\n"; inTable = false }
                    inCodeBlock = true; html += "<pre><code>"
                }
                continue
            }
            if inCodeBlock { html += escapeHTML(line) + "\n"; continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Close list if line breaks it
            let isULItem = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
            let isOLItem = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            if inList && !isULItem && !trimmed.isEmpty { html += "</ul>\n"; inList = false }
            if inOrderedList && !isOLItem && !trimmed.isEmpty { html += "</ol>\n"; inOrderedList = false }

            // HR
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if inTable { html += "</table>\n"; inTable = false }
                html += "<hr>\n"; continue
            }

            // Heading
            if trimmed.hasPrefix("#") {
                let level = min(trimmed.prefix(while: { $0 == "#" }).count, 6)
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    if inTable { html += "</table>\n"; inTable = false }
                    html += "<h\(level)>\(inlineMarkdown(text))</h\(level)>\n"; continue
                }
            }

            // UL
            if isULItem {
                if !inList { html += "<ul>\n"; inList = true }
                html += "<li>\(inlineMarkdown(String(trimmed.dropFirst(2))))</li>\n"; continue
            }

            // OL
            if isOLItem {
                if !inOrderedList { html += "<ol>\n"; inOrderedList = true }
                let text = trimmed.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                html += "<li>\(inlineMarkdown(text))</li>\n"; continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                html += "<blockquote>\(inlineMarkdown(String(trimmed.dropFirst(2))))</blockquote>\n"; continue
            }

            // Table
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if trimmed.contains("---") { continue }  // separator row
                if !inTable { html += "<table>\n"; inTable = true }
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let isHeader = !html.contains("<td>") && html.contains("<table>")
                let tag = isHeader ? "th" : "td"
                html += "<tr>" + cells.map { "<\(tag)>\(inlineMarkdown($0))</\(tag)>" }.joined() + "</tr>\n"
                continue
            }
            if inTable { html += "</table>\n"; inTable = false }

            // Empty line
            if trimmed.isEmpty { html += "<br>\n"; continue }

            // Paragraph
            html += "<p>\(inlineMarkdown(trimmed))</p>\n"
        }

        if inCodeBlock   { html += "</code></pre>\n" }
        if inList        { html += "</ul>\n" }
        if inOrderedList { html += "</ol>\n" }
        if inTable       { html += "</table>\n" }
        return html
    }

    private func inlineMarkdown(_ text: String) -> String {
        var r = escapeHTML(text)
        r = r.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"(?<!\w)_(.+?)_(?!\w)"#, with: "<em>$1</em>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"`(.+?)`"#, with: "<code>$1</code>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\[(.+?)\]\((.+?)\)"#, with: "<a href=\"$2\" target=\"_blank\">$1</a>", options: .regularExpression)
        return r
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String = ""
        var lastAppearance: NSAppearance.Name? = nil
        var selfSizing: Bool = false
        var heightChanged: ((CGFloat) -> Void)?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard selfSizing else { return }
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? CGFloat, height > 0 {
                    self?.heightChanged?(height)
                }
            }
        }
    }
}

/// For short/medium markdown (AI analysis, chat messages, feed items).
/// Lighter than MarkdownView — uses SwiftUI Text with .full syntax.
struct InlineMarkdownText: View {
    let text: String
    var font: Font = .callout

    var body: some View {
        Text(rendered)
            .font(font)
            .textSelection(.enabled)
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text,
              options: .init(interpretedSyntax: .full)))
        ?? AttributedString(text)
    }
}

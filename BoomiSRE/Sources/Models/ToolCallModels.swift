import Foundation

// MARK: - Jira Tool Definitions (sent to Claude API)

enum JiraTools {
    static var definitions: [[String: Any]] {
        [getJiraTicket, postJiraComment]
    }

    static var getJiraTicket: [String: Any] {
        [
            "name": "get_jira_ticket",
            "description": "Fetch full details of a Jira ticket by key, including description, all comments, status, priority, assignee, and subtasks. Use this whenever a specific ticket key is mentioned (e.g. CAMSRE-123, INC-456, SRE-789) and you need more than a summary — for example to draft a PIR, analyze an incident, or write a comment.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "ticket_key": [
                        "type": "string",
                        "description": "The Jira ticket key, e.g. CAMSRE-123 or INC-456"
                    ]
                ],
                "required": ["ticket_key"]
            ]
        ]
    }

    static var postJiraComment: [String: Any] {
        [
            "name": "post_jira_comment",
            "description": "Post a comment to a Jira ticket. Use this when the user explicitly asks to post, add, or write a comment to a specific ticket. A confirmation dialog will be shown to the user before posting — do not assume the comment was posted until you receive a tool_result confirming success.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "ticket_key": [
                        "type": "string",
                        "description": "The Jira ticket key to post the comment on, e.g. CAMSRE-123"
                    ],
                    "comment_body": [
                        "type": "string",
                        "description": "The comment text in markdown format. Use **bold**, - bullet lists, and ``` code blocks ``` for formatting. Do not use HTML."
                    ]
                ],
                "required": ["ticket_key", "comment_body"]
            ]
        ]
    }
}

// MARK: - Claude Tool Use Response

struct ClaudeToolUse {
    let id: String
    let name: String
    let input: [String: Any]
}

enum ClaudeToolResponse {
    /// Claude finished responding with text (stop_reason = end_turn).
    case finalText(String)
    /// Claude wants to call one or more tools (stop_reason = tool_use).
    case toolUse(
        textBefore: String?,
        tools: [ClaudeToolUse],
        rawAssistantBlocks: [[String: Any]]
    )
}

// MARK: - Tool Call Event (inline UI indicator)

struct ToolCallEvent: Codable, Identifiable {
    var id: UUID
    let eventType: ToolEventType
    let ticketKey: String
    let succeeded: Bool
    let detail: String?  // error message or deep link URL

    init(id: UUID = UUID(), eventType: ToolEventType, ticketKey: String, succeeded: Bool, detail: String?) {
        self.id = id
        self.eventType = eventType
        self.ticketKey = ticketKey
        self.succeeded = succeeded
        self.detail = detail
    }
}

enum ToolEventType: String, Codable {
    case fetchedTicket    // get_jira_ticket succeeded
    case postedComment    // post_jira_comment succeeded
    case commentCancelled // user cancelled
    case commentFailed    // post failed
}

// MARK: - Pending Comment Confirmation (confirmation card data)

struct PendingCommentConfirmation: Codable {
    let toolUseId: String
    let ticketKey: String
    let commentMarkdown: String  // Claude's draft, in markdown
}

// MARK: - Markdown → ADF Converter

/// Converts a markdown string to Atlassian Document Format (ADF) for Jira API v3.
/// Handles: headings, bullet lists, numbered lists, code blocks, paragraphs,
/// and inline bold/italic/code marks.
enum MarkdownToADF {

    static func convert(_ markdown: String) -> [String: Any] {
        let lines = markdown.components(separatedBy: "\n")
        let contentNodes = parseBlocks(lines: lines)
        let nonEmpty = contentNodes.isEmpty
            ? [paragraph([textNode(markdown)])]
            : contentNodes
        return ["version": 1, "type": "doc", "content": nonEmpty]
    }

    // MARK: Block-level parsing

    private static func parseBlocks(lines: [String]) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }  // skip closing ```
                let code = codeLines.joined(separator: "\n")
                var attrs: [String: Any] = [:]
                if !lang.isEmpty { attrs["language"] = lang }
                nodes.append([
                    "type": "codeBlock",
                    "attrs": attrs,
                    "content": [["type": "text", "text": code]]
                ])
                continue
            }

            // Bullet list (- or *)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var items: [[String: Any]] = []
                while i < lines.count && (lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ")) {
                    let text = String(lines[i].dropFirst(2))
                    items.append([
                        "type": "listItem",
                        "content": [paragraph(parseInline(text))]
                    ])
                    i += 1
                }
                nodes.append(["type": "bulletList", "content": items])
                continue
            }

            // Numbered list (1. 2. etc.)
            if isNumberedListItem(line) {
                var items: [[String: Any]] = []
                while i < lines.count, isNumberedListItem(lines[i]) {
                    let l = lines[i]
                    // Strip "N. " prefix
                    let text: String
                    if let dotIdx = l.firstIndex(of: "."),
                       l.index(after: dotIdx) < l.endIndex {
                        text = String(l[l.index(dotIdx, offsetBy: 2)...])
                    } else {
                        text = l
                    }
                    items.append([
                        "type": "listItem",
                        "content": [paragraph(parseInline(text))]
                    ])
                    i += 1
                }
                if !items.isEmpty {
                    nodes.append(["type": "orderedList", "content": items])
                }
                continue
            }

            // Headings
            if line.hasPrefix("### ") {
                nodes.append(heading(String(line.dropFirst(4)), level: 3)); i += 1; continue
            }
            if line.hasPrefix("## ") {
                nodes.append(heading(String(line.dropFirst(3)), level: 2)); i += 1; continue
            }
            if line.hasPrefix("# ") {
                nodes.append(heading(String(line.dropFirst(2)), level: 1)); i += 1; continue
            }

            // Horizontal rule
            if line == "---" || line == "***" || line == "___" {
                nodes.append(["type": "rule"]); i += 1; continue
            }

            // Empty line — paragraph separator, skip
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1; continue
            }

            // Regular paragraph
            nodes.append(paragraph(parseInline(line)))
            i += 1
        }

        return nodes
    }

    // MARK: Inline parsing

    private static func parseInline(_ text: String) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        var buffer = ""
        var i = text.startIndex

        func flushBuffer() {
            if !buffer.isEmpty {
                nodes.append(textNode(buffer))
                buffer = ""
            }
        }

        while i < text.endIndex {
            // Bold **text**
            if text[i...].hasPrefix("**") {
                let afterOpen = text.index(i, offsetBy: 2)
                if afterOpen < text.endIndex,
                   let closeRange = text.range(of: "**", range: afterOpen..<text.endIndex) {
                    flushBuffer()
                    let bold = String(text[afterOpen..<closeRange.lowerBound])
                    nodes.append(textNode(bold, marks: [["type": "strong"]]))
                    i = closeRange.upperBound
                    continue
                }
            }

            // Italic *text* (single asterisk, not double)
            if text[i] == "*" && !text[i...].hasPrefix("**") {
                let afterOpen = text.index(after: i)
                if afterOpen < text.endIndex,
                   let closeRange = text.range(of: "*", range: afterOpen..<text.endIndex) {
                    // Verify close isn't **
                    let closeNext = closeRange.upperBound
                    let isDouble = closeNext < text.endIndex && text[closeNext] == "*"
                    if !isDouble {
                        flushBuffer()
                        let italic = String(text[afterOpen..<closeRange.lowerBound])
                        nodes.append(textNode(italic, marks: [["type": "em"]]))
                        i = closeRange.upperBound
                        continue
                    }
                }
            }

            // Inline code `code`
            if text[i] == "`" {
                let afterOpen = text.index(after: i)
                if afterOpen < text.endIndex,
                   let closeRange = text.range(of: "`", range: afterOpen..<text.endIndex) {
                    flushBuffer()
                    let code = String(text[afterOpen..<closeRange.lowerBound])
                    nodes.append(textNode(code, marks: [["type": "code"]]))
                    i = closeRange.upperBound
                    continue
                }
            }

            buffer.append(text[i])
            i = text.index(after: i)
        }

        flushBuffer()
        return nodes.isEmpty ? [textNode(text)] : nodes
    }

    // MARK: Helpers

    /// Returns true if the line starts with a number followed by ". ".
    private static func isNumberedListItem(_ line: String) -> Bool {
        guard let dotIdx = line.firstIndex(of: "."),
              dotIdx > line.startIndex else { return false }
        let prefix = line[line.startIndex..<dotIdx]
        let afterDot = line.index(after: dotIdx)
        return prefix.allSatisfy(\.isNumber) && !prefix.isEmpty
            && afterDot < line.endIndex && line[afterDot] == " "
    }

    private static func paragraph(_ content: [[String: Any]]) -> [String: Any] {
        ["type": "paragraph", "content": content]
    }

    private static func heading(_ text: String, level: Int) -> [String: Any] {
        ["type": "heading", "attrs": ["level": level], "content": parseInline(text)]
    }

    private static func textNode(_ text: String, marks: [[String: Any]] = []) -> [String: Any] {
        var node: [String: Any] = ["type": "text", "text": text]
        if !marks.isEmpty { node["marks"] = marks }
        return node
    }
}

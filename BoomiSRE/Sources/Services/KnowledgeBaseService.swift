import Foundation

/// Service that fetches and searches articles from the team Knowledge Base on GitHub.
actor KnowledgeBaseService {

    struct KBArticle: Identifiable, Sendable {
        let id: String          // file path in repo
        let title: String       // extracted from first # heading or filename
        let category: KBCategory
        let path: String        // e.g., "sops/creating-a-pcr.md"
        let content: String     // full markdown content
        let lastModified: String?
        let htmlURL: String
    }

    enum KBCategory: String, CaseIterable, Sendable {
        case sop       = "SOPs"
        case runbook   = "Runbooks"
        case guide     = "Guides"
        case reference = "Reference"

        var icon: String {
            switch self {
            case .sop:       return "checklist"
            case .runbook:   return "book"
            case .guide:     return "doc.text"
            case .reference: return "magnifyingglass.circle"
            }
        }

        static func categorize(path: String) -> KBCategory {
            let lower = path.lowercased()
            if lower.hasPrefix("sops/")     { return .sop }
            if lower.hasPrefix("runbooks/") { return .runbook }
            if lower.hasPrefix("guides/")   { return .guide }
            return .reference
        }
    }

    /// Fetch all Markdown articles from the GitHub repo.
    func fetchArticles(owner: String, repo: String, token: String) async throws -> [KBArticle] {
        let treeURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/main?recursive=1")!
        var req = URLRequest(url: treeURL, timeoutInterval: 20)
        req.addBearerAuth(token: token)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (treeData, treeResp) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = treeResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: treeData, encoding: .utf8) ?? ""
            let code = (treeResp as? HTTPURLResponse)?.statusCode ?? 0
            throw KBError.httpError(status: code, body: body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: treeData) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else {
            throw KBError.invalidResponse
        }

        // Filter to .md files only
        let mdPaths: [(path: String, sha: String)] = tree.compactMap { node in
            guard let path = node["path"] as? String,
                  path.hasSuffix(".md"),
                  let sha = node["sha"] as? String else { return nil }
            return (path, sha)
        }

        // Fetch content in parallel (limit concurrency to avoid rate limits)
        var articles: [KBArticle] = []
        let chunks = stride(from: 0, to: mdPaths.count, by: 5).map {
            Array(mdPaths[$0..<min($0 + 5, mdPaths.count)])
        }

        for chunk in chunks {
            await withTaskGroup(of: KBArticle?.self) { group in
                for item in chunk {
                    group.addTask {
                        try? await self.fetchSingleArticle(
                            owner: owner, repo: repo, path: item.path, token: token)
                    }
                }
                for await result in group {
                    if let article = result { articles.append(article) }
                }
            }
        }

        return articles.sorted { $0.title < $1.title }
    }

    /// Fetch a single article's content.
    func fetchArticle(owner: String, repo: String, path: String, token: String) async throws -> KBArticle {
        try await fetchSingleArticle(owner: owner, repo: repo, path: path, token: token)
    }

    /// Search articles by keyword (case-insensitive substring across title + content).
    func search(query: String, articles: [KBArticle]) -> [KBArticle] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return articles }
        let q = query.lowercased()
        return articles.filter {
            $0.title.lowercased().contains(q) ||
            $0.content.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }

    // MARK: - Private

    private func fetchSingleArticle(owner: String, repo: String, path: String, token: String) async throws -> KBArticle {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let contentURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath)")!
        var req = URLRequest(url: contentURL, timeoutInterval: 15)
        req.addBearerAuth(token: token)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw KBError.httpError(status: code, body: body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = json["content"] as? String else {
            throw KBError.invalidResponse
        }

        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let contentData = Data(base64Encoded: cleaned),
              let contentStr = String(data: contentData, encoding: .utf8) else {
            throw KBError.invalidResponse
        }

        // Extract title from first # heading, or derive from filename
        let title = extractTitle(from: contentStr, path: path)
        let category = KBCategory.categorize(path: path)
        let htmlURL = "https://github.com/\(owner)/\(repo)/blob/main/\(path)"
        let lastModified = json["last_modified"] as? String

        return KBArticle(
            id: path,
            title: title,
            category: category,
            path: path,
            content: contentStr,
            lastModified: lastModified,
            htmlURL: htmlURL
        )
    }

    private func extractTitle(from content: String, path: String) -> String {
        if let firstLine = content.components(separatedBy: "\n").first(where: { $0.hasPrefix("# ") }) {
            return String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

// MARK: - Errors

enum KBError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from GitHub"
        case .httpError(let status, let body):
            return "GitHub returned HTTP \(status): \(body.prefix(200))"
        }
    }
}

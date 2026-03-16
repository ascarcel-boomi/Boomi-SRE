import Foundation

/// Calls the Jira REST API v3 directly via URLSession.
actor JiraService {

    /// Verify credentials by calling GET /rest/api/3/myself.
    func checkAuth(baseURL: String, email: String, apiToken: String) async throws -> String {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/myself")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let user = try JSONDecoder().decode(JiraUser.self, from: data)
        return user.displayName
    }

    /// Search issues using JQL via GET /rest/api/3/search/jql.
    func searchIssues(
        baseURL: String, email: String, apiToken: String,
        jql: String,
        fields: [String] = ["summary", "status", "priority", "issuetype",
                             "duedate", "labels", "created", "updated"],
        maxResults: Int = 50
    ) async throws -> JiraSearchResult {
        let (data, _) = try await executeSearch(
            baseURL: baseURL, email: email, apiToken: apiToken,
            jql: jql, fields: fields, maxResults: maxResults
        )
        return try JSONDecoder().decode(JiraSearchResult.self, from: data)
    }

    /// Search issues and return raw JSON alongside decoded results.
    /// Use this when you need to extract dynamic custom fields (e.g. sprint).
    func searchIssuesRaw(
        baseURL: String, email: String, apiToken: String,
        jql: String, fields: [String], maxResults: Int = 200
    ) async throws -> (result: JiraSearchResult, rawIssues: [[String: Any]]) {
        let (data, _) = try await executeSearch(
            baseURL: baseURL, email: email, apiToken: apiToken,
            jql: jql, fields: fields, maxResults: maxResults
        )
        let decoded = try JSONDecoder().decode(JiraSearchResult.self, from: data)

        var rawIssues: [[String: Any]] = []
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issues = json["issues"] as? [[String: Any]] {
            rawIssues = issues
        }
        return (decoded, rawIssues)
    }

    /// Execute a JQL search via GET /rest/api/3/search/jql with query parameters.
    /// POST with JSON body is rejected by some Jira Cloud instances.
    private func executeSearch(
        baseURL: String, email: String, apiToken: String,
        jql: String, fields: [String], maxResults: Int
    ) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: fields.joined(separator: ",")),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        guard let url = components.url else {
            throw JiraError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)
        return (data, response)
    }

    /// Get all custom fields, returning (id, name) tuples.
    func getCustomFields(
        baseURL: String, email: String, apiToken: String
    ) async throws -> [(id: String, name: String)] {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/field")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let fields = try JSONDecoder().decode([JiraFieldMeta].self, from: data)
        return fields.map { ($0.id, $0.name) }
    }

    /// Discover available product element values by sampling recent incidents.
    /// Uses Method 2: query Jira for recent incidents and extract unique values.
    func discoverProductElements(
        baseURL: String, email: String, apiToken: String,
        productElementFieldId: String
    ) async throws -> [String] {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/search/jql")!
        let jql = "project = \"Boomi Incident Management\" ORDER BY created DESC"
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: "summary,\(productElementFieldId)"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        guard let url = components.url else { throw JiraError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issues = json["issues"] as? [[String: Any]] else { return [] }

        var values = Set<String>()
        for issue in issues {
            guard let fields = issue["fields"] as? [String: Any],
                  let fieldValue = fields[productElementFieldId] else { continue }
            // Multi-select: array of {value: "..."}
            if let arr = fieldValue as? [[String: Any]] {
                for item in arr {
                    if let v = item["value"] as? String { values.insert(v) }
                }
            } else if let single = fieldValue as? [String: Any],
                      let v = single["value"] as? String {
                values.insert(v)
            }
        }
        return values.sorted()
    }

    /// Get all comments for an issue.
    func getIssueComments(
        baseURL: String, email: String, apiToken: String,
        issueKey: String
    ) async throws -> [JiraComment] {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(issueKey)/comment")!
        components.queryItems = [
            URLQueryItem(name: "orderBy", value: "created"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        guard let url = components.url else { throw JiraError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let comments = json["comments"] as? [[String: Any]] else { return [] }

        return comments.compactMap { c in
            guard let id = c["id"] as? String,
                  let author = (c["author"] as? [String: Any])?["displayName"] as? String,
                  let created = c["created"] as? String else { return nil }
            let avatarURL = ((c["author"] as? [String: Any])?["avatarUrls"] as? [String: Any])?["24x24"] as? String
            let bodyText = c["body"].flatMap { extractADFText($0) } ?? ""
            return JiraComment(id: id, authorName: author, authorAvatarURL: avatarURL,
                               created: created, bodyText: bodyText)
        }
    }

    /// Extract plain text from an Atlassian Document Format (ADF) body.
    private func extractADFText(_ value: Any) -> String {
        guard let node = value as? [String: Any] else { return "" }
        let nodeType = node["type"] as? String ?? ""

        if nodeType == "text" {
            return node["text"] as? String ?? ""
        }
        if nodeType == "hardBreak" { return "\n" }

        guard let children = node["content"] as? [Any] else { return "" }
        var parts: [String] = []
        for child in children {
            let text = extractADFText(child)
            if !text.isEmpty { parts.append(text) }
        }
        let joined = parts.joined(separator: nodeType == "paragraph" ? " " : "")
        return nodeType == "paragraph" ? joined + "\n" : joined
    }

    /// Discover the custom field ID for "Sprint" by scanning all fields.
    func discoverSprintFieldId(
        baseURL: String, email: String, apiToken: String
    ) async throws -> String? {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/field")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let fields = try JSONDecoder().decode([JiraFieldMeta].self, from: data)
        return fields.first { $0.name == "Sprint" }?.id
    }

    /// Fetch the current user's favourite filters.
    func fetchFavouriteFilters(
        baseURL: String, email: String, apiToken: String
    ) async throws -> [JiraFilter] {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/filter/favourite")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        return try JSONDecoder().decode([JiraFilter].self, from: data)
    }

    // MARK: - Dev Info (PRs, Commits, Branches)

    /// Get development info (pull requests, commits, branches) for an issue.
    func getDevInfo(
        baseURL: String, email: String, apiToken: String, issueId: String
    ) async throws -> JiraDevInfo {
        // Summary first
        let summaryURL = URL(string: "\(baseURL.trimSlash)/rest/dev-status/latest/issue/summary?issueId=\(issueId)")!
        var request = URLRequest(url: summaryURL, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)
        let (summaryData, summaryResp) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira DevInfo", summaryResp, data: summaryData)

        let summaryJSON = (try? JSONSerialization.jsonObject(with: summaryData) as? [String: Any]) ?? [:]
        let summary = summaryJSON["summary"] as? [String: Any] ?? [:]

        let prCount = ((summary["pullrequest"] as? [String: Any])?["overall"] as? [String: Any])?["count"] as? Int ?? 0
        let branchCount = ((summary["branch"] as? [String: Any])?["overall"] as? [String: Any])?["count"] as? Int ?? 0

        var pullRequests: [JiraDevPR] = []
        var commits: [JiraDevCommit] = []

        // Only fetch details if there's something to show
        if prCount > 0 || branchCount > 0 {
            for appType in ["GitHub", "stash", "bitbucket"] {
                // PRs
                if let prs = try? await fetchDevDetail(baseURL: baseURL, email: email, apiToken: apiToken,
                                                       issueId: issueId, appType: appType, dataType: "pullrequest") {
                    pullRequests.append(contentsOf: prs.compactMap { parsePR($0) })
                }
                // Commits/repos
                if let repos = try? await fetchDevDetail(baseURL: baseURL, email: email, apiToken: apiToken,
                                                         issueId: issueId, appType: appType, dataType: "repository") {
                    for repo in repos {
                        if let repoCommits = repo["commits"] as? [[String: Any]] {
                            commits.append(contentsOf: repoCommits.compactMap { parseCommit($0) })
                        }
                    }
                }
            }
        }

        return JiraDevInfo(prCount: prCount, branchCount: branchCount,
                           pullRequests: pullRequests, commits: commits)
    }

    private func fetchDevDetail(
        baseURL: String, email: String, apiToken: String,
        issueId: String, appType: String, dataType: String
    ) async throws -> [[String: Any]]? {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/dev-status/latest/issue/detail")!
        components.queryItems = [
            URLQueryItem(name: "issueId", value: issueId),
            URLQueryItem(name: "applicationType", value: appType),
            URLQueryItem(name: "dataType", value: dataType),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira DevInfo", response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = json["detail"] as? [[String: Any]] else { return nil }

        // Flatten: each detail item may have pullRequests, repositories, etc.
        var results: [[String: Any]] = []
        for d in detail {
            if dataType == "pullrequest", let prs = d["pullRequests"] as? [[String: Any]] {
                results.append(contentsOf: prs)
            }
            if dataType == "repository", let repos = d["repositories"] as? [[String: Any]] {
                results.append(contentsOf: repos)
            }
        }
        return results.isEmpty ? nil : results
    }

    private func parsePR(_ raw: [String: Any]) -> JiraDevPR? {
        guard let name = raw["name"] as? String,
              let url = raw["url"] as? String,
              let status = raw["status"] as? String else { return nil }
        let author = (raw["author"] as? [String: Any])?["name"] as? String ?? ""
        let source = (raw["source"] as? [String: Any])?["name"] as? String ?? ""
        let dest = (raw["destination"] as? [String: Any])?["name"] as? String ?? ""
        return JiraDevPR(name: name, url: url, status: status, author: author,
                         sourceBranch: source, destBranch: dest)
    }

    private func parseCommit(_ raw: [String: Any]) -> JiraDevCommit? {
        guard let message = raw["message"] as? String,
              let url = raw["url"] as? String else { return nil }
        let author = (raw["author"] as? [String: Any])?["name"] as? String ?? ""
        let date = raw["authorTimestamp"] as? String ?? ""
        let hash = raw["id"] as? String ?? ""
        return JiraDevCommit(message: message, url: url, author: author,
                             date: String(date.prefix(16).replacingOccurrences(of: "T", with: " ")),
                             hash: String(hash.prefix(8)))
    }

    // MARK: - Ticket Actions

    /// Get full issue details including description, comments, subtasks, parent, and changelog.
    func getIssue(
        baseURL: String, email: String, apiToken: String, key: String
    ) async throws -> (issue: JiraIssue, raw: [String: Any]) {
        let fields = "summary,status,priority,issuetype,duedate,labels,created,updated,assignee,reporter,creator,comment,description,subtasks,parent,customfield_10020,customfield_10015"
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)?fields=\(fields)&expand=changelog")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        let issue = try JSONDecoder().decode(JiraIssue.self, from: data)
        let raw = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (issue, raw)
    }

    /// Get available transitions for an issue.
    func getTransitions(
        baseURL: String, email: String, apiToken: String, key: String
    ) async throws -> [JiraTransition] {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/transitions")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        // Parse manually since transitions are nested
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transitions = json["transitions"] as? [[String: Any]] else { return [] }

        return transitions.compactMap { t in
            guard let id = t["id"] as? String,
                  let name = t["name"] as? String,
                  let to = t["to"] as? [String: Any],
                  let toName = to["name"] as? String else { return nil }
            let catName = (to["statusCategory"] as? [String: Any])?["name"] as? String ?? ""
            return JiraTransition(id: id, name: name, toStatus: toName, toCategory: catName)
        }
    }

    /// Transition an issue to a new status.
    func transitionIssue(
        baseURL: String, email: String, apiToken: String,
        key: String, transitionId: String
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/transitions")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["transition": ["id": transitionId]])

        let (data, response) = try await URLSession.shared.data(for: request)
        // 204 No Content is success
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }

    /// Add a comment to an issue (Atlassian Document Format).
    func addComment(
        baseURL: String, email: String, apiToken: String,
        key: String, body: String
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/comment")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // ADF format for a simple text paragraph
        let adf: [String: Any] = [
            "body": [
                "version": 1,
                "type": "doc",
                "content": [
                    ["type": "paragraph", "content": [
                        ["type": "text", "text": body]
                    ]]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: adf)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)
    }

    /// Post a pre-built ADF document as a comment. Used by the AI Copilot tool flow.
    func addCommentADF(
        baseURL: String, email: String, apiToken: String,
        key: String, adfDoc: [String: Any]
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/comment")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["body": adfDoc]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }

    /// Assign an issue to a user by accountId. Pass nil to unassign.
    func assignIssue(
        baseURL: String, email: String, apiToken: String,
        key: String, accountId: String?
    ) async throws {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/issue/\(key)/assignee")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PUT"
        request.addBasicAuth(email: email, token: apiToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["accountId": accountId as Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }

    /// Search users by name/email for assignment.
    func searchUsers(
        baseURL: String, email: String, apiToken: String, query: String
    ) async throws -> [JiraAssignableUser] {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/user/search")!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        guard let users = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return users.compactMap { u in
            guard let id = u["accountId"] as? String,
                  let name = u["displayName"] as? String else { return nil }
            return JiraAssignableUser(accountId: id, displayName: name)
        }
    }

    /// Get the current user's accountId.
    func getMyAccountId(
        baseURL: String, email: String, apiToken: String
    ) async throws -> String {
        let url = URL(string: "\(baseURL.trimSlash)/rest/api/3/myself")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira", response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountId = json["accountId"] as? String else {
            throw JiraError.invalidResponse
        }
        return accountId
    }

    // MARK: - Agile / Sprint

    func listBoards(baseURL: String, email: String, apiToken: String, projectKey: String) async throws -> [AgileBoard] {
        let encoded = projectKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectKey
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/agile/1.0/board")!
        components.queryItems = [
            URLQueryItem(name: "projectKeyOrId", value: encoded),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        guard let url = components.url else { throw JiraError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira Agile", response, data: data)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = obj["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { d -> AgileBoard? in
            guard let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
            return AgileBoard(id: id, name: name, type: d["type"] as? String ?? "")
        }
    }

    func listSprints(baseURL: String, email: String, apiToken: String, boardId: Int, state: String = "active,closed") async throws -> [JiraSprint] {
        let encoded = state.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? state
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/agile/1.0/board/\(boardId)/sprint")!
        components.queryItems = [
            URLQueryItem(name: "state", value: encoded),
            URLQueryItem(name: "maxResults", value: "20"),
        ]
        guard let url = components.url else { throw JiraError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira Sprints", response, data: data)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = obj["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { d -> JiraSprint? in
            guard let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
            return JiraSprint(id: id, name: name,
                              state: d["state"] as? String ?? "",
                              startDate: d["startDate"] as? String,
                              endDate: d["endDate"] as? String)
        }
    }

    func listSprintIssues(baseURL: String, email: String, apiToken: String, sprintId: Int) async throws -> [SprintIssue] {
        var components = URLComponents(string: "\(baseURL.trimSlash)/rest/agile/1.0/sprint/\(sprintId)/issue")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "summary,status,assignee,customfield_10015,issuetype"),
            URLQueryItem(name: "maxResults", value: "200"),
        ]
        guard let url = components.url else { throw JiraError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.addBasicAuth(email: email, token: apiToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse("Jira Sprint Issues", response, data: data)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issues = obj["issues"] as? [[String: Any]] else { return [] }
        return issues.compactMap { issue -> SprintIssue? in
            guard let idVal = issue["id"] as? String, let id = Int(idVal),
                  let key = issue["key"] as? String else { return nil }
            let fields = issue["fields"] as? [String: Any] ?? [:]
            let status = (fields["status"] as? [String: Any])?["name"] as? String ?? ""
            let assignee = (fields["assignee"] as? [String: Any])?["displayName"] as? String ?? "Unassigned"
            let storyPoints = fields["customfield_10015"] as? Double
            let summary = fields["summary"] as? String ?? ""
            let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? ""
            return SprintIssue(id: id, key: key, summary: summary, status: status,
                               assignee: assignee, storyPoints: storyPoints, issueType: issueType)
        }
    }

    // MARK: - Projects

    /// Fetch all accessible projects via GET /rest/api/3/project/search (paginated).
    func fetchProjects(
        baseURL: String, email: String, apiToken: String
    ) async throws -> [JiraProjectSummary] {
        var all: [JiraProjectSummary] = []
        var startAt = 0
        let maxResults = 50

        while true {
            var components = URLComponents(string: "\(baseURL.trimSlash)/rest/api/3/project/search")!
            components.queryItems = [
                URLQueryItem(name: "startAt", value: String(startAt)),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "orderBy", value: "key"),
            ]
            var request = URLRequest(url: components.url!, timeoutInterval: 30)
            request.addBasicAuth(email: email, token: apiToken)

            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse("Jira", response, data: data)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["values"] as? [[String: Any]] else { break }

            for v in values {
                guard let id = v["id"] as? String,
                      let key = v["key"] as? String,
                      let name = v["name"] as? String else { continue }
                all.append(JiraProjectSummary(id: id, key: key, name: name))
            }

            let isLast = json["isLast"] as? Bool ?? true
            if isLast || values.count < maxResults { break }
            startAt += values.count
        }
        return all
    }

    // MARK: - Private

    private func validateResponse(_ service: String, _ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JiraError.httpError(status: code, body: body)
        }
    }
}

// MARK: - Agile structs

struct AgileBoard: Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String
}

struct SprintIssue: Identifiable, Sendable {
    let id: Int
    let key: String
    let summary: String
    let status: String
    let assignee: String
    let storyPoints: Double?
    let issueType: String
}

// MARK: - Errors

enum JiraError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Jira"
        case .httpError(let status, let body):
            return "Jira returned HTTP \(status):\n\(body.prefix(300))"
        case .notConfigured:
            return "Jira is not configured. Open Settings to add your credentials."
        }
    }
}

// Shared auth helpers: URLRequestExtensions.swift (addBasicAuth, trimSlash)

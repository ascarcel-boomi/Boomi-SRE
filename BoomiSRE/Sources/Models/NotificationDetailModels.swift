import Foundation

/// Detail data structures fetched on-demand when a notification row is expanded.

struct JiraIssueDetail {
    let key: String
    let summary: String
    let status: String
    let priority: String
    let description: String
}

struct GrafanaAlertDetail {
    let uid: String
    let title: String
    let state: String
    let labels: [String: String]
    let summary: String
}

struct GitHubPRDetail {
    let number: Int
    let title: String
    let state: String
    let authorLogin: String
    let headBranch: String
    let baseBranch: String
    let body: String
    let isDraft: Bool
}

import Foundation

struct BBRepo: Identifiable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BBRepo, rhs: BBRepo) -> Bool { lhs.id == rhs.id }
    let id: String
    let name: String
    let fullName: String
    let description: String
    let isPrivate: Bool
    let language: String
    let mainBranch: String
    let updatedOn: String
    let size: Int
    let htmlURL: String
}

struct BBPR: Identifiable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BBPR, rhs: BBPR) -> Bool { lhs.id == rhs.id }
    let id: Int
    let title: String
    let description: String
    let state: String
    let authorDisplayName: String
    let authorNickname: String
    let sourceBranch: String
    let destinationBranch: String
    let createdOn: String
    let updatedOn: String
    let commentCount: Int
    let taskCount: Int
    let htmlURL: String
}

struct BBBranch: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let target: String
}

struct BBPipeline: Identifiable, Sendable {
    let id: String
    let buildNumber: Int
    let state: String
    let result: String?
    let triggerName: String
    let targetBranch: String
    let createdOn: String
    let completedOn: String?
    let durationSeconds: Int?
    let htmlURL: String
}

struct BBCommit: Identifiable, Sendable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let message: String
    let authorName: String
    let date: String
}

struct BBComment: Identifiable, Sendable {
    let id: Int
    let authorDisplayName: String
    let content: String
    let createdOn: String
    let updatedOn: String
}

import Foundation

struct ProductContext: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var shortName: String
    var icon: String
    var color: String

    var jsmTeamIds: [String]
    var jiraProjectKeys: [String]
    var incidentProductElements: [String]
    var githubRepoPatterns: [String]
    var bitbucketRepoPatterns: [String]
    var jenkinsJobPatterns: [String]
    var grafanaDashboardTags: [String]
    var grafanaFolders: [String]
    var confluenceSpaceKeys: [String]
    var kbTags: [String]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ProductContext, rhs: ProductContext) -> Bool { lhs.id == rhs.id }
}

extension ProductContext {
    static let defaults: [ProductContext] = [
        ProductContext(
            id: "all",
            name: "All Products",
            shortName: "All",
            icon: "square.grid.2x2",
            color: "gray",
            jsmTeamIds: [],
            jiraProjectKeys: [],
            incidentProductElements: [],
            githubRepoPatterns: [],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: [],
            grafanaDashboardTags: [],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: []
        ),
        ProductContext(
            id: "cam-sre",
            name: "CAM SRE (Mashery)",
            shortName: "CAM",
            icon: "shield.checkmark",
            color: "orange",
            jsmTeamIds: ["og-90b86004-f391-4213-9742-3c0f47d8731b"],
            jiraProjectKeys: ["CAMSRE"],
            incidentProductElements: ["Cloud API Management (Mashery)"],
            githubRepoPatterns: ["apim-sre-*", "mashery-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mashery*", "*cam*", "*apim*"],
            grafanaDashboardTags: ["mashery", "cam", "apim"],
            grafanaFolders: [],
            confluenceSpaceKeys: ["camsre", "CAMSRE"],
            kbTags: ["cam", "mashery", "apim"]
        ),
        ProductContext(
            id: "mft-sre",
            name: "MFT SRE (Thru)",
            shortName: "MFT",
            icon: "doc.on.doc",
            color: "blue",
            jsmTeamIds: ["314953fc-b4e1-4be0-bc6a-3267a30e98e1"],
            jiraProjectKeys: ["MFTSRE", "MFT"],
            incidentProductElements: ["Managed File Transfer"],
            githubRepoPatterns: ["mft-*", "thru-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mft*", "*thru*"],
            grafanaDashboardTags: ["mft", "thru"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["mft", "thru"]
        ),
        ProductContext(
            id: "di-sre",
            name: "DI SRE (Rivery)",
            shortName: "DI",
            icon: "arrow.triangle.branch",
            color: "green",
            jsmTeamIds: ["c8007b3c-41c7-4135-ae9c-8a73f9e48576"],
            jiraProjectKeys: ["DISRE", "DI"],
            incidentProductElements: ["Data Integration"],
            githubRepoPatterns: ["di-*", "rivery-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*rivery*", "*data-integration*"],
            grafanaDashboardTags: ["rivery", "di"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["di", "rivery"]
        ),
        ProductContext(
            id: "mcs-sre",
            name: "MCS SRE",
            shortName: "MCS",
            icon: "cloud",
            color: "purple",
            jsmTeamIds: ["og-4b28ccc3-f6b6-436c-b18b-ce8e204f4465"],
            jiraProjectKeys: ["MCS"],
            incidentProductElements: ["Managed Cloud Services"],
            githubRepoPatterns: ["mcs-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mcs*"],
            grafanaDashboardTags: ["mcs"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["mcs"]
        ),
        ProductContext(
            id: "boomi-sre",
            name: "Boomi SRE (Platform)",
            shortName: "Platform",
            icon: "server.rack",
            color: "red",
            jsmTeamIds: ["og-d8192695-a28f-4cf5-96c9-8a806f5bc90a"],
            jiraProjectKeys: ["SRE"],
            incidentProductElements: ["Boomi Platform", "Boomi Runtime"],
            githubRepoPatterns: ["boomi-*", "platform-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*boomi*", "*platform*"],
            grafanaDashboardTags: ["boomi", "platform", "runtime"],
            grafanaFolders: [],
            confluenceSpaceKeys: [],
            kbTags: ["boomi", "platform", "runtime"]
        ),
    ]
}

import Foundation

struct EscalationContact: Codable, Hashable {
    var name: String
    var role: String
    var slackHandle: String
    var email: String
}

struct ProductContext: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var shortName: String
    var icon: String
    var color: String

    // Service filters
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

    // Knowledge & Escalation (NEW — backward-compatible via custom decoder)
    var productDescription: String
    var architectureNotes: String
    var escalationContacts: [EscalationContact]
    var keyRunbooks: [String]
    var commonAlertPatterns: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, shortName, icon, color
        case jsmTeamIds, jiraProjectKeys, incidentProductElements
        case githubRepoPatterns, bitbucketRepoPatterns, jenkinsJobPatterns
        case grafanaDashboardTags, grafanaFolders, confluenceSpaceKeys, kbTags
        case productDescription, architectureNotes, escalationContacts, keyRunbooks, commonAlertPatterns
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ProductContext, rhs: ProductContext) -> Bool { lhs.id == rhs.id }

    // Custom decoder for backward compat — new fields default to empty if missing
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shortName = try c.decode(String.self, forKey: .shortName)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        jsmTeamIds = try c.decodeIfPresent([String].self, forKey: .jsmTeamIds) ?? []
        jiraProjectKeys = try c.decodeIfPresent([String].self, forKey: .jiraProjectKeys) ?? []
        incidentProductElements = try c.decodeIfPresent([String].self, forKey: .incidentProductElements) ?? []
        githubRepoPatterns = try c.decodeIfPresent([String].self, forKey: .githubRepoPatterns) ?? []
        bitbucketRepoPatterns = try c.decodeIfPresent([String].self, forKey: .bitbucketRepoPatterns) ?? []
        jenkinsJobPatterns = try c.decodeIfPresent([String].self, forKey: .jenkinsJobPatterns) ?? []
        grafanaDashboardTags = try c.decodeIfPresent([String].self, forKey: .grafanaDashboardTags) ?? []
        grafanaFolders = try c.decodeIfPresent([String].self, forKey: .grafanaFolders) ?? []
        confluenceSpaceKeys = try c.decodeIfPresent([String].self, forKey: .confluenceSpaceKeys) ?? []
        kbTags = try c.decodeIfPresent([String].self, forKey: .kbTags) ?? []
        productDescription = try c.decodeIfPresent(String.self, forKey: .productDescription) ?? ""
        architectureNotes = try c.decodeIfPresent(String.self, forKey: .architectureNotes) ?? ""
        escalationContacts = try c.decodeIfPresent([EscalationContact].self, forKey: .escalationContacts) ?? []
        keyRunbooks = try c.decodeIfPresent([String].self, forKey: .keyRunbooks) ?? []
        commonAlertPatterns = try c.decodeIfPresent([String].self, forKey: .commonAlertPatterns) ?? []
    }

    // Memberwise init
    init(id: String, name: String, shortName: String, icon: String, color: String,
         jsmTeamIds: [String], jiraProjectKeys: [String], incidentProductElements: [String],
         githubRepoPatterns: [String], bitbucketRepoPatterns: [String], jenkinsJobPatterns: [String],
         grafanaDashboardTags: [String], grafanaFolders: [String], confluenceSpaceKeys: [String],
         kbTags: [String],
         productDescription: String = "", architectureNotes: String = "",
         escalationContacts: [EscalationContact] = [], keyRunbooks: [String] = [],
         commonAlertPatterns: [String] = []) {
        self.id = id; self.name = name; self.shortName = shortName; self.icon = icon; self.color = color
        self.jsmTeamIds = jsmTeamIds; self.jiraProjectKeys = jiraProjectKeys
        self.incidentProductElements = incidentProductElements
        self.githubRepoPatterns = githubRepoPatterns; self.bitbucketRepoPatterns = bitbucketRepoPatterns
        self.jenkinsJobPatterns = jenkinsJobPatterns; self.grafanaDashboardTags = grafanaDashboardTags
        self.grafanaFolders = grafanaFolders; self.confluenceSpaceKeys = confluenceSpaceKeys
        self.kbTags = kbTags
        self.productDescription = productDescription; self.architectureNotes = architectureNotes
        self.escalationContacts = escalationContacts; self.keyRunbooks = keyRunbooks
        self.commonAlertPatterns = commonAlertPatterns
    }
}

extension ProductContext {
    static let defaults: [ProductContext] = [
        ProductContext(
            id: "all", name: "All Products", shortName: "All",
            icon: "square.grid.2x2", color: "gray",
            jsmTeamIds: [], jiraProjectKeys: [], incidentProductElements: [],
            githubRepoPatterns: [], bitbucketRepoPatterns: [], jenkinsJobPatterns: [],
            grafanaDashboardTags: [], grafanaFolders: [], confluenceSpaceKeys: [], kbTags: [],
            productDescription: "All Boomi SRE products — no filtering applied.",
            architectureNotes: "", escalationContacts: [], keyRunbooks: [], commonAlertPatterns: []
        ),
        ProductContext(
            id: "cam-sre", name: "CAM SRE (Mashery)", shortName: "CAM",
            icon: "shield.checkmark", color: "orange",
            jsmTeamIds: ["og-90b86004-f391-4213-9742-3c0f47d8731b"],
            jiraProjectKeys: ["CAMSRE"],
            incidentProductElements: ["Cloud API Management (Mashery)"],
            githubRepoPatterns: ["apim-sre-*", "mashery-*"],
            bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mashery*", "*cam*", "*apim*"],
            grafanaDashboardTags: ["mashery", "cam", "apim"],
            grafanaFolders: [], confluenceSpaceKeys: ["camsre", "CAMSRE"],
            kbTags: ["cam", "mashery", "apim"],
            productDescription: "Cloud API Management (Mashery) — Boomi's API gateway platform. Handles API traffic management, analytics, and developer portals for enterprise customers worldwide.",
            architectureNotes: "Multi-region deployment (us-east-1, eu-west-1, us-west-2, ap-southeast). Stack: EC2 instances behind ALBs in ASGs, Aurora RDS, Elasticsearch clusters, Cassandra, Redis/ElastiCache. Managed via Terraform (apim-sre-terraform-iac), Ansible, and Puppet.",
            escalationContacts: [
                EscalationContact(name: "Adam Scarcella", role: "SRE Manager", slackHandle: "@ascarcel-boomi", email: "adam.scarcella@boomi.com"),
                EscalationContact(name: "James Beck", role: "Senior SRE", slackHandle: "@jbeck-tibco", email: "james.beck@boomi.com"),
            ],
            keyRunbooks: [
                "sops/creating-a-pcr.md",
                "sops/update-amis-cve-remediation.md",
                "sops/create-customer-load-balancer.md",
                "runbooks/api-v2-lb-500.md",
                "runbooks/tm-db-005-row-lock.md",
                "on-call-guide.md",
            ],
            commonAlertPatterns: [
                "ALB 5xx spikes — usually indicates backend instance health issues. Check ASG instance health and recent deployments.",
                "Aurora CPU/connection spikes — check for long-running queries, connection pool exhaustion, or traffic surge.",
                "Elasticsearch cluster red — check node health, disk space, and shard allocation.",
                "Cassandra repair failures — check disk space and compaction status.",
            ]
        ),
        ProductContext(
            id: "mft-sre", name: "MFT SRE (Thru)", shortName: "MFT",
            icon: "doc.on.doc", color: "blue",
            jsmTeamIds: ["314953fc-b4e1-4be0-bc6a-3267a30e98e1"],
            jiraProjectKeys: ["MFTSRE", "MFT"],
            incidentProductElements: ["Managed File Transfer"],
            githubRepoPatterns: ["mft-*", "thru-*"], bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mft*", "*thru*"],
            grafanaDashboardTags: ["mft", "thru"], grafanaFolders: [],
            confluenceSpaceKeys: [], kbTags: ["mft", "thru"],
            productDescription: "Managed File Transfer (Thru) — Boomi's secure file transfer platform including Advanced File Transfer (AFT) and File Sharing (FS).",
            architectureNotes: "Architecture details to be documented. Check the Knowledge Base for available runbooks.",
            escalationContacts: [], keyRunbooks: [], commonAlertPatterns: []
        ),
        ProductContext(
            id: "di-sre", name: "DI SRE (Rivery)", shortName: "DI",
            icon: "arrow.triangle.branch", color: "green",
            jsmTeamIds: ["c8007b3c-41c7-4135-ae9c-8a73f9e48576"],
            jiraProjectKeys: ["DISRE", "DI"],
            incidentProductElements: ["Data Integration"],
            githubRepoPatterns: ["di-*", "rivery-*"], bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*rivery*", "*data-integration*"],
            grafanaDashboardTags: ["rivery", "di"], grafanaFolders: [],
            confluenceSpaceKeys: [], kbTags: ["di", "rivery"],
            productDescription: "Data Integration (Rivery) — Boomi's cloud-native ELT/ETL data integration platform for ingesting, transforming, and orchestrating data pipelines.",
            architectureNotes: "Architecture details to be documented. Check the Knowledge Base for available runbooks.",
            escalationContacts: [], keyRunbooks: [], commonAlertPatterns: []
        ),
        ProductContext(
            id: "mcs-sre", name: "MCS SRE", shortName: "MCS",
            icon: "cloud", color: "purple",
            jsmTeamIds: ["og-4b28ccc3-f6b6-436c-b18b-ce8e204f4465"],
            jiraProjectKeys: ["MCS"],
            incidentProductElements: ["Managed Cloud Services"],
            githubRepoPatterns: ["mcs-*"], bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*mcs*"],
            grafanaDashboardTags: ["mcs"], grafanaFolders: [],
            confluenceSpaceKeys: [], kbTags: ["mcs"],
            productDescription: "Managed Cloud Services — Boomi's managed hosting and cloud operations for customer Boomi environments.",
            architectureNotes: "Architecture details to be documented. Check the Knowledge Base for available runbooks.",
            escalationContacts: [], keyRunbooks: [], commonAlertPatterns: []
        ),
        ProductContext(
            id: "boomi-sre", name: "Boomi SRE (Platform)", shortName: "Platform",
            icon: "server.rack", color: "red",
            jsmTeamIds: ["og-d8192695-a28f-4cf5-96c9-8a806f5bc90a"],
            jiraProjectKeys: ["SRE"],
            incidentProductElements: ["Boomi Platform", "Boomi Runtime"],
            githubRepoPatterns: ["boomi-*", "platform-*"], bitbucketRepoPatterns: [],
            jenkinsJobPatterns: ["*boomi*", "*platform*"],
            grafanaDashboardTags: ["boomi", "platform", "runtime"], grafanaFolders: [],
            confluenceSpaceKeys: [], kbTags: ["boomi", "platform", "runtime"],
            productDescription: "Boomi SRE (Platform) — Core Boomi Integration Platform and runtime infrastructure. Includes Boomi AtomSphere, connectors, and integration runtime environments.",
            architectureNotes: "Architecture details to be documented. Check the Knowledge Base for available runbooks.",
            escalationContacts: [], keyRunbooks: [], commonAlertPatterns: []
        ),
    ]
}

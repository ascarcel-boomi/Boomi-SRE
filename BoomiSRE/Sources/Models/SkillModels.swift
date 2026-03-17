import Foundation

// MARK: - Skill Variable

/// A placeholder variable in a skill prompt template (e.g., `{service}`, `{INCIDENT_KEY}`).
struct SkillVariable: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String          // e.g. "service"
    var placeholder: String   // e.g. "Enter service name"
    var defaultValue: String  // optional pre-fill

    enum CodingKeys: String, CodingKey {
        case id, name, placeholder, defaultValue
    }

    init(name: String, placeholder: String = "", defaultValue: String = "") {
        self.name = name
        self.placeholder = placeholder.isEmpty ? "Enter \(name)" : placeholder
        self.defaultValue = defaultValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
        defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue) ?? ""
    }
}

// MARK: - Skill Category

enum SkillCategory: String, Codable, CaseIterable, Identifiable {
    case incident   = "Incident"
    case operations = "Operations"
    case reporting  = "Reporting"
    case analysis   = "Analysis"
    case custom     = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .incident:   return "exclamationmark.shield"
        case .operations: return "gearshape.2"
        case .reporting:  return "doc.text"
        case .analysis:   return "chart.bar.xaxis"
        case .custom:     return "star"
        }
    }
}

// MARK: - Skill

/// A reusable AI prompt template with variable placeholders.
struct Skill: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var skillDescription: String
    var category: SkillCategory
    var promptTemplate: String          // Contains {variable_name} placeholders
    var variables: [SkillVariable]
    var icon: String                    // SF Symbol name
    var isBuiltIn: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, skillDescription, category, promptTemplate
        case variables, icon, isBuiltIn, createdAt, lastUsedAt, useCount
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Skill, rhs: Skill) -> Bool { lhs.id == rhs.id }

    /// Parse `{variable_name}` placeholders from the prompt template.
    static func extractVariables(from template: String) -> [SkillVariable] {
        var result: [SkillVariable] = []
        var seen = Set<String>()
        let pattern = try? NSRegularExpression(pattern: "\\{([a-zA-Z_][a-zA-Z0-9_]*)\\}")
        let range = NSRange(template.startIndex..., in: template)
        pattern?.enumerateMatches(in: template, range: range) { match, _, _ in
            guard let match, let nameRange = Range(match.range(at: 1), in: template) else { return }
            let name = String(template[nameRange])
            guard !seen.contains(name) else { return }
            seen.insert(name)
            result.append(SkillVariable(name: name))
        }
        return result
    }

    /// Replace `{variable_name}` placeholders with provided values.
    func resolve(values: [UUID: String]) -> String {
        var result = promptTemplate
        for variable in variables {
            let value = values[variable.id] ?? variable.defaultValue
            result = result.replacingOccurrences(of: "{\(variable.name)}", with: value)
        }
        return result
    }

    // MARK: - Bundled Defaults

    static let defaults: [Skill] = [
        Skill(
            name: "Create SOP",
            skillDescription: "Generate a Standard Operating Procedure for a service or process",
            category: .operations,
            promptTemplate: """
            Create a detailed Standard Operating Procedure (SOP) for {service}. Include:
            1. **Purpose & Scope** — what this SOP covers
            2. **Prerequisites** — required access, tools, knowledge
            3. **Step-by-step Procedure** — numbered steps with commands where applicable
            4. **Verification** — how to confirm each step succeeded
            5. **Rollback** — how to undo if something goes wrong
            6. **Escalation** — who to contact and when
            Format as markdown. Be specific to Boomi's infrastructure.
            """,
            variables: [SkillVariable(name: "service", placeholder: "e.g. Mashery Traffic Manager, Aurora failover")],
            icon: "doc.text.fill",
            isBuiltIn: true, createdAt: Date(), useCount: 0
        ),
        Skill(
            name: "Draft Post-Mortem",
            skillDescription: "Create a post-mortem document from an incident",
            category: .incident,
            promptTemplate: """
            Draft a post-mortem for incident {incident_key}. Use the following structure:
            1. **Summary** — one paragraph overview
            2. **Timeline** — chronological events with timestamps
            3. **Root Cause** — what caused the incident
            4. **Impact** — users affected, duration, SLA impact
            5. **What Went Well** — effective responses
            6. **What Could Be Improved** — process gaps
            7. **Action Items** — specific, assigned, with due dates
            Be candid and blameless. Focus on systemic improvements.
            """,
            variables: [SkillVariable(name: "incident_key", placeholder: "e.g. INC-1234 or CAMSRE-5678")],
            icon: "exclamationmark.shield",
            isBuiltIn: true, createdAt: Date(), useCount: 0
        ),
        Skill(
            name: "Summarize Jira Epic",
            skillDescription: "Get an executive summary of a Jira epic's progress",
            category: .reporting,
            promptTemplate: """
            Summarize the current state of Jira epic {epic_key}. Include:
            - Overall progress (% complete, stories done vs remaining)
            - Key blockers or risks
            - Recent activity highlights
            - Estimated completion outlook
            Keep it concise — suitable for a standup or leadership update.
            """,
            variables: [SkillVariable(name: "epic_key", placeholder: "e.g. CAMSRE-100, SRE-50")],
            icon: "list.bullet.clipboard",
            isBuiltIn: true, createdAt: Date(), useCount: 0
        ),
        Skill(
            name: "Weekly Status Report",
            skillDescription: "Generate a weekly SRE status report from current data",
            category: .reporting,
            promptTemplate: """
            Generate a weekly SRE status report for {team_name} covering the past week. Include:
            1. **Incidents** — any P1/P2 incidents, their status and resolution
            2. **Deployments** — notable releases or changes
            3. **Alerts & Monitoring** — firing alerts, trends, new monitors
            4. **On-Call Summary** — pages, response times, gaps
            5. **Project Updates** — sprint progress, key deliverables
            6. **Next Week** — planned work, risks, dependencies
            Use bullet points. Flag anything that needs leadership attention.
            """,
            variables: [SkillVariable(name: "team_name", placeholder: "e.g. CAM SRE, Platform SRE", defaultValue: "CAM SRE")],
            icon: "doc.text",
            isBuiltIn: true, createdAt: Date(), useCount: 0
        ),
        Skill(
            name: "Draft Runbook",
            skillDescription: "Create a runbook for a specific operational task",
            category: .operations,
            promptTemplate: """
            Create a concise runbook for: {topic}

            Include:
            - **When to use** — trigger conditions
            - **Quick steps** — the critical path (numbered, copy-pasteable commands)
            - **Verification** — how to confirm success
            - **Common issues** — troubleshooting tips
            - **Escalation** — who to call if stuck

            Keep it practical — an on-call engineer at 3am should be able to follow this.
            """,
            variables: [SkillVariable(name: "topic", placeholder: "e.g. Aurora read replica failover, cache flush")],
            icon: "book.closed.fill",
            isBuiltIn: true, createdAt: Date(), useCount: 0
        ),
        Skill(
            name: "Explain Alert Pattern",
            skillDescription: "Analyze and explain a Grafana alert pattern",
            category: .analysis,
            promptTemplate: """
            Explain this alert pattern and recommend actions:

            Alert: {alert_name}
            Behavior: {description}

            Include:
            - What this alert typically indicates
            - Common root causes
            - Immediate triage steps
            - When to escalate vs. self-resolve
            - Suggestions for tuning the alert threshold if it's noisy
            """,
            variables: [
                SkillVariable(name: "alert_name", placeholder: "e.g. High API Latency P99 > 500ms"),
                SkillVariable(name: "description", placeholder: "e.g. Firing intermittently for 2 hours, correlates with deploy"),
            ],
            icon: "bell.badge",
            isBuiltIn: true, createdAt: Date(), useCount: 0
        ),
    ]
}

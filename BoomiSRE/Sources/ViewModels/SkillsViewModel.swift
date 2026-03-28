import Foundation
import SwiftUI

@MainActor
final class SkillsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var skills: [Skill] = []
    @Published var selectedCategory: SkillCategory? = nil
    @Published var searchText: String = ""

    // Editor state
    @Published var isEditorPresented = false
    @Published var editingSkill: Skill?

    // Runner state
    @Published var isRunnerPresented = false
    @Published var runningSkill: Skill?
    @Published var variableValues: [UUID: String] = [:]

    // MARK: - Storage

    private let storageURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".boomi_sre_skills.json")
    }()

    init() {
        load()
        if skills.isEmpty { seedDefaults() }
        discoverClaudeCodeSkills()
    }

    // MARK: - Computed

    var filteredSkills: [Skill] {
        var result = skills
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.skillDescription.lowercased().contains(q) ||
                $0.category.rawValue.lowercased().contains(q)
            }
        }
        return result
    }

    /// Top skills by usage for quick-action display.
    var frequentSkills: [Skill] {
        Array(skills.sorted { ($0.useCount, $0.lastUsedAt ?? .distantPast) > ($1.useCount, $1.lastUsedAt ?? .distantPast) }.prefix(6))
    }

    // MARK: - CRUD

    func addSkill(_ skill: Skill) {
        skills.append(skill)
        save()
    }

    func updateSkill(_ skill: Skill) {
        if let idx = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[idx] = skill
            save()
        }
    }

    func deleteSkill(_ skill: Skill) {
        guard !skill.isBuiltIn else { return }
        skills.removeAll { $0.id == skill.id }
        save()
    }

    // MARK: - Execution

    /// Prepare to run a skill — populate variableValues with defaults.
    func prepareToRun(_ skill: Skill) {
        runningSkill = skill
        variableValues = Dictionary(uniqueKeysWithValues:
            skill.variables.map { ($0.id, $0.defaultValue) }
        )
        isRunnerPresented = true
    }

    /// Resolve the skill template with current variable values and record usage.
    func resolveAndRecord() -> String? {
        guard var skill = runningSkill else { return nil }
        let resolved = skill.resolve(values: variableValues)
        skill.useCount += 1
        skill.lastUsedAt = Date()
        updateSkill(skill)
        isRunnerPresented = false
        return resolved
    }

    // MARK: - Create from Conversation

    /// Create a new skill from an existing copilot conversation.
    func createSkillFromMessage(_ userMessage: String, name: String = "", category: SkillCategory = .custom) {
        let variables = Skill.extractVariables(from: userMessage)
        let skill = Skill(
            name: name.isEmpty ? String(userMessage.prefix(40)) : name,
            skillDescription: "",
            category: category,
            promptTemplate: userMessage,
            variables: variables,
            icon: category.icon,
            isBuiltIn: false,
            createdAt: Date(),
            useCount: 0
        )
        editingSkill = skill
        isEditorPresented = true
    }

    // MARK: - Editor

    func startNewSkill() {
        editingSkill = Skill(
            name: "", skillDescription: "", category: .custom,
            promptTemplate: "", variables: [], icon: "star",
            isBuiltIn: false, createdAt: Date(), useCount: 0
        )
        isEditorPresented = true
    }

    func saveEditingSkill() {
        guard var skill = editingSkill else { return }
        // Re-parse variables from template
        skill.variables = Skill.extractVariables(from: skill.promptTemplate)
        if skills.contains(where: { $0.id == skill.id }) {
            updateSkill(skill)
        } else {
            addSkill(skill)
        }
        isEditorPresented = false
        editingSkill = nil
    }

    // MARK: - Import / Export

    func exportSkills(_ subset: [Skill]? = nil) -> Data? {
        let toExport = subset ?? skills.filter { !$0.isBuiltIn }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(toExport)
    }

    func importSkills(from data: Data) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([Skill].self, from: data) else { return 0 }
        var count = 0
        for var skill in imported {
            if !skills.contains(where: { $0.name == skill.name && $0.promptTemplate == skill.promptTemplate }) {
                skill.isBuiltIn = false
                addSkill(skill)
                count += 1
            }
        }
        return count
    }

    // MARK: - Claude Code Skill Discovery

    /// Scan ~/.claude/skills/ for SKILL.md files and merge them into the skills list.
    func discoverClaudeCodeSkills() {
        let fm = FileManager.default
        let skillsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills")

        guard let entries = try? fm.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Remove previously discovered Claude Code skills so we get a fresh scan
        skills.removeAll { $0.isClaudeCodeSkill }

        for entry in entries {
            let skillFile = entry.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path),
                  let content = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }

            let parsed = parseSkillFrontmatter(content)
            let folderName = entry.lastPathComponent
            let name = parsed.name ?? folderName
            let description = parsed.description ?? ""
            let template = parsed.body

            let variables = Skill.extractVariables(from: template)
            let skill = Skill(
                name: name,
                skillDescription: description,
                category: .claudeCode,
                promptTemplate: template,
                variables: variables,
                icon: "terminal",
                isBuiltIn: true,
                isClaudeCodeSkill: true,
                createdAt: Date(),
                useCount: 0
            )
            skills.append(skill)
        }
    }

    /// Parse YAML frontmatter delimited by `---` markers. Returns name, description, and body.
    private func parseSkillFrontmatter(_ content: String) -> (name: String?, description: String?, body: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            return (nil, nil, content)
        }

        // Find the second --- marker
        let afterFirst = trimmed.dropFirst(3)
        guard let endRange = afterFirst.range(of: "\n---") else {
            return (nil, nil, content)
        }

        let frontmatter = String(afterFirst[afterFirst.startIndex..<endRange.lowerBound])
        let bodyStart = afterFirst[endRange.upperBound...]
        let body = String(bodyStart).trimmingCharacters(in: .whitespacesAndNewlines)

        var name: String?
        var description: String?

        for line in frontmatter.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "name":
                name = value
            case "description":
                description = value
            default:
                break
            }
        }

        return (name, description, body)
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(skills) {
            try? data.write(to: storageURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        skills = (try? decoder.decode([Skill].self, from: data)) ?? []
    }

    private func seedDefaults() {
        skills = Skill.defaults
        save()
    }
}

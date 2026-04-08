import SwiftUI

/// Compact sheet for filling in skill variables and running the skill.
struct SkillRunnerSheet: View {
    @EnvironmentObject var appState: AppState
    var skillsVM: SkillsViewModel
    var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let skill = skillsVM.runningSkill {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: skill.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(.headline)
                        if !skill.skillDescription.isEmpty {
                            Text(skill.skillDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(skill.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)
                }

                Divider()

                // Variable inputs
                if skill.variables.isEmpty {
                    Text("This skill has no variables — it will run as-is.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(skill.variables) { variable in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(variable.name)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            TextField(variable.placeholder,
                                      text: Binding(
                                        get: { skillsVM.variableValues[variable.id] ?? variable.defaultValue },
                                        set: { skillsVM.variableValues[variable.id] = $0 }
                                      ))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                // Preview — highlights unresolved placeholders
                let preview = skill.resolve(values: skillsVM.variableValues)
                let hasUnresolved = preview.range(of: "\\{[a-zA-Z_][a-zA-Z0-9_]*\\}", options: .regularExpression) != nil
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Preview").font(.caption.bold()).foregroundStyle(.secondary)
                        if hasUnresolved {
                            Label("Fill in all variables above", systemImage: "exclamationmark.triangle")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    previewText(preview)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                        .lineLimit(5)
                }

                Divider()

                // Actions
                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Run Skill") {
                        if let resolved = skillsVM.resolveAndRecord() {
                            chatVM.inputText = resolved
                            Task { await chatVM.send(appState: appState) }
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(skill.variables.contains { v in
                        (skillsVM.variableValues[v.id] ?? v.defaultValue).trimmingCharacters(in: .whitespaces).isEmpty
                    })
                }
            }
            .padding(20)
            .frame(width: 500)
        }
    }

    /// Renders preview text with unresolved `{variable}` placeholders highlighted in orange.
    private func previewText(_ text: String) -> Text {
        let pattern = try! NSRegularExpression(pattern: "\\{([a-zA-Z_][a-zA-Z0-9_]*)\\}")
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: nsRange)

        if matches.isEmpty {
            return Text(text).font(.caption).foregroundStyle(.primary)
        }

        var result = Text("")
        var lastEnd = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            // Append text before the match
            if lastEnd < range.lowerBound {
                result = result + Text(text[lastEnd..<range.lowerBound]).font(.caption).foregroundStyle(.primary)
            }
            // Append the placeholder in orange
            result = result + Text(text[range]).font(.caption.bold()).foregroundStyle(.orange)
            lastEnd = range.upperBound
        }
        // Append remaining text
        if lastEnd < text.endIndex {
            result = result + Text(text[lastEnd...]).font(.caption).foregroundStyle(.primary)
        }
        return result
    }
}

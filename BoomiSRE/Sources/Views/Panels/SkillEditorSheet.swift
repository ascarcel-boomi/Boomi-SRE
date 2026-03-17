import SwiftUI

/// Form for creating or editing a skill.
struct SkillEditorSheet: View {
    @ObservedObject var skillsVM: SkillsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let skill = Binding($skillsVM.editingSkill) {
            VStack(alignment: .leading, spacing: 16) {
                Text(skillsVM.skills.contains(where: { $0.id == skill.wrappedValue.id }) ? "Edit Skill" : "New Skill")
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField("Skill name", text: skill.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category").font(.caption.bold()).foregroundStyle(.secondary)
                        Picker("", selection: skill.category) {
                            ForEach(SkillCategory.allCases) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 160)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption.bold()).foregroundStyle(.secondary)
                    TextField("Brief description of what this skill does", text: skill.skillDescription)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Prompt Template").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Text("Use {variable_name} for placeholders")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    TextEditor(text: skill.promptTemplate)
                        .font(.body.monospaced())
                        .frame(minHeight: 150, maxHeight: 250)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                }

                // Detected variables
                let detected = Skill.extractVariables(from: skill.wrappedValue.promptTemplate)
                if !detected.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected Variables (\(detected.count))")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(detected) { v in
                                Text("{\(v.name)}")
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                // Icon picker (small selection)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon").font(.caption.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        let icons = ["star", "doc.text.fill", "book.closed.fill", "gearshape.2",
                                     "exclamationmark.shield", "bell.badge", "chart.bar.xaxis",
                                     "list.bullet.clipboard", "network", "server.rack",
                                     "bolt.fill", "wrench.and.screwdriver"]
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                skill.wrappedValue.icon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.body)
                                    .frame(width: 32, height: 32)
                                    .background(skill.wrappedValue.icon == iconName
                                                ? Color.accentColor.opacity(0.2)
                                                : Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(skill.wrappedValue.icon == iconName
                                             ? RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                                             : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                HStack {
                    Button("Cancel") {
                        skillsVM.editingSkill = nil
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Save Skill") {
                        skillsVM.saveEditingSkill()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(skill.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || skill.wrappedValue.promptTemplate.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 600)
        }
    }
}

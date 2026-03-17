import SwiftUI
import AppKit

/// Full skills management panel — list, create, edit, import/export.
struct SkillsManagerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var skillsVM: SkillsViewModel
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills Library").font(.title2.bold())
                    Text("\(skillsVM.skills.count) skills · \(skillsVM.skills.filter { !$0.isBuiltIn }.count) custom")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                // Import
                Button {
                    importSkills()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                // Export
                Button {
                    exportSkills()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(skillsVM.skills.filter { !$0.isBuiltIn }.isEmpty)

                // New
                Button {
                    skillsVM.startNewSkill()
                } label: {
                    Label("New Skill", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            // Category filter + search
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    categoryChip(nil, "All")
                    ForEach(SkillCategory.allCases) { cat in
                        categoryChip(cat, cat.rawValue)
                    }
                }
                Spacer()
                TextField("Search skills...", text: $skillsVM.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            // Skills grid
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // First-time intro — shown until the user has run at least one skill
                    if skillsVM.skills.allSatisfy({ $0.useCount == 0 }) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                Text("What are Skills?").font(.headline)
                            }
                            Text("Skills are **reusable AI prompts** for tasks you do repeatedly — drafting post-mortems, generating runbooks, summarizing epics, explaining alerts. Fill in a few variables, hit Run, and the AI Copilot does the rest.")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Text("Try one:").font(.caption.bold()).foregroundStyle(.secondary)
                                Button {
                                    if let runbook = skillsVM.skills.first(where: { $0.name == "Draft Runbook" }) {
                                        skillsVM.prepareToRun(runbook)
                                    }
                                } label: {
                                    Label("Draft a Runbook", systemImage: "book.closed.fill")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                Button {
                                    if let alert = skillsVM.skills.first(where: { $0.name == "Explain Alert Pattern" }) {
                                        skillsVM.prepareToRun(alert)
                                    }
                                } label: {
                                    Label("Explain an Alert", systemImage: "bell.badge")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        .padding(DesignTokens.cardPadding)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                            .fill(Color.yellow.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                            .strokeBorder(Color.yellow.opacity(0.2)))
                    }

                    if skillsVM.filteredSkills.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "sparkles").font(.system(size: DesignTokens.emptyIconSize)).foregroundStyle(.secondary)
                            Text("No skills found").font(.headline).foregroundStyle(.secondary)
                            Text("Create a new skill or adjust your filter.")
                                .font(.callout).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(skillsVM.filteredSkills) { skill in
                                skillCard(skill)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $skillsVM.isEditorPresented) {
            SkillEditorSheet(skillsVM: skillsVM)
        }
        .sheet(isPresented: $skillsVM.isRunnerPresented) {
            SkillRunnerSheet(skillsVM: skillsVM, chatVM: chatVM)
                .environmentObject(appState)
        }
    }

    // MARK: - Skill Card

    private func skillCard(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name).font(.callout.bold()).lineLimit(1)
                    Text(skill.category.rawValue)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if skill.isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !skill.skillDescription.isEmpty {
                Text(skill.skillDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !skill.variables.isEmpty {
                HStack(spacing: 4) {
                    ForEach(skill.variables.prefix(3)) { v in
                        Text("{\(v.name)}")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            .foregroundStyle(.secondary)
                    }
                    if skill.variables.count > 3 {
                        Text("+\(skill.variables.count - 3)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    skillsVM.prepareToRun(skill)
                } label: {
                    Label("Run in Copilot", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                if skill.useCount > 0 {
                    Text("Used \(skill.useCount)x")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                if !skill.isBuiltIn {
                    Button {
                        skillsVM.editingSkill = skill
                        skillsVM.isEditorPresented = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)

                    Button {
                        skillsVM.deleteSkill(skill)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }

    // MARK: - Category Chip

    private func categoryChip(_ cat: SkillCategory?, _ label: String) -> some View {
        Button {
            skillsVM.selectedCategory = cat
        } label: {
            HStack(spacing: 4) {
                if let cat { Image(systemName: cat.icon).font(.caption2) }
                Text(label).font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(skillsVM.selectedCategory == cat
                                       ? Color.accentColor.opacity(0.15)
                                       : Color.secondary.opacity(0.08)))
            .foregroundStyle(skillsVM.selectedCategory == cat ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import / Export

    private func exportSkills() {
        guard let data = skillsVM.exportSkills(),
              let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private func importSkills() {
        guard let json = NSPasteboard.general.string(forType: .string),
              let data = json.data(using: .utf8) else { return }
        let count = skillsVM.importSkills(from: data)
        if count > 0 {
            // Success feedback handled by the skills list updating
        }
    }
}

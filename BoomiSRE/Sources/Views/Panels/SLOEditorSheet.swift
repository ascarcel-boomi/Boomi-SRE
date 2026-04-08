import SwiftUI

/// Sheet for creating or editing an SLO definition.
struct SLOEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Bindable var vm: SLOViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let def = Binding($vm.editingDefinition) {
            VStack(alignment: .leading, spacing: 16) {
                Text(appState.sloDefinitions.contains(where: { $0.id == def.wrappedValue.id }) ? "Edit SLO" : "New SLO")
                    .font(.title2.bold())

                // Name + Category
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField("e.g. CAM API Availability", text: def.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category").font(.caption.bold()).foregroundStyle(.secondary)
                        Picker("", selection: def.category) {
                            ForEach(SLOCategory.allCases) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 160)
                }

                // Product
                VStack(alignment: .leading, spacing: 4) {
                    Text("Product").font(.caption.bold()).foregroundStyle(.secondary)
                    Picker("", selection: def.productId) {
                        Text("Not assigned").tag("")
                        ForEach(appState.products.filter { $0.id != "all" }) { product in
                            Label(product.name, systemImage: product.icon).tag(product.id)
                        }
                    }
                    .labelsHidden()
                }

                // Description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption.bold()).foregroundStyle(.secondary)
                    TextField("What does this SLO measure?", text: def.sloDescription)
                        .textFieldStyle(.roundedBorder)
                }

                // Target + Window
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target (e.g. 0.999 = 99.9%)").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField("0.999", value: def.target, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Window").font(.caption.bold()).foregroundStyle(.secondary)
                        Picker("", selection: def.windowDays) {
                            Text("7 days").tag(7)
                            Text("28 days").tag(28)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                // PromQL
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Metric Query (PromQL)").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Text("Should return a value between 0 and 1")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    TextEditor(text: def.metricQuery)
                        .font(.body.monospaced())
                        .frame(minHeight: 60, maxHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                }

                // Templates
                VStack(alignment: .leading, spacing: 4) {
                    Text("Or start from a template:").font(.caption.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(SLOTemplate.builtIn) { template in
                            Button {
                                def.wrappedValue.name = template.name
                                def.wrappedValue.sloDescription = template.description
                                def.wrappedValue.category = template.category
                                def.wrappedValue.target = template.defaultTarget
                                def.wrappedValue.windowDays = template.defaultWindowDays
                                def.wrappedValue.metricQuery = template.metricQueryTemplate
                            } label: {
                                Label(template.name, systemImage: template.category.icon)
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                // Enabled toggle
                Toggle("Enabled", isOn: def.enabled)
                    .toggleStyle(.switch)

                Divider()

                HStack {
                    Button("Cancel") { vm.showEditor = false; dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Save SLO") {
                        vm.saveEditingDefinition(appState: appState)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(def.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 600)
        }
    }
}

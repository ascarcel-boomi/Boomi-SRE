import SwiftUI

/// SLO Dashboard — shows all SLO definitions grouped by product with live status.
struct SLODashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = SLOViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SLO Dashboard").font(.title2.bold())
                    if let last = vm.lastRefreshed {
                        Text("Updated \(last, style: .relative) ago")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Health summary pills
                if !vm.statuses.isEmpty {
                    HStack(spacing: 8) {
                        healthPill(vm.healthyCount, "Healthy", .green)
                        healthPill(vm.warningCount, "Warning", .orange)
                        healthPill(vm.criticalCount, "Critical", .red)
                    }
                }

                // AI Analysis
                Button {
                    Task { await vm.analyzeSLOHealth(appState: appState) }
                } label: {
                    Label(vm.isAnalyzing ? "..." : "Analyze", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(vm.isAnalyzing || vm.statuses.isEmpty)

                // Refresh
                Button {
                    Task { await vm.refresh(appState: appState) }
                } label: {
                    if vm.isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(vm.isLoading)

                // Add SLO
                Button {
                    vm.startNewDefinition()
                } label: {
                    Label("Add SLO", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            // Product filter
            if Set(appState.sloDefinitions.map(\.productId)).count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        productChip(nil, "All")
                        ForEach(appState.products.filter { p in
                            p.id != "all" && appState.sloDefinitions.contains(where: { $0.productId == p.id })
                        }) { product in
                            productChip(product.id, product.shortName)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                Divider()
            }

            // Error / AI analysis
            if let err = vm.error {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            if let aiErr = vm.aiError {
                Label(aiErr, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.vertical, 4)
            }
            if let analysis = vm.aiAnalysis {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("AI Analysis", systemImage: "sparkles")
                            .font(.caption.bold()).foregroundStyle(.purple)
                        Spacer()
                        Button { vm.aiAnalysis = nil } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Dismiss analysis")
                    }
                    InlineMarkdownText(text: analysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.2)))
                .padding(.horizontal, 16).padding(.top, 8)
            }

            // Content
            if appState.sloDefinitions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.statusesByProduct, id: \.productId) { (productId, statuses) in
                            productSection(productId: productId, statuses: statuses)
                        }

                        // Show definitions without status (not yet refreshed)
                        let statusIds = Set(vm.statuses.map(\.id))
                        let unrefreshed = appState.sloDefinitions.filter { $0.enabled && !statusIds.contains($0.id) }
                        if !unrefreshed.isEmpty && vm.statuses.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(unrefreshed.count) SLOs defined — click Refresh to load live data")
                                    .font(.callout).foregroundStyle(.secondary)
                                ForEach(unrefreshed) { def in
                                    HStack(spacing: 8) {
                                        Image(systemName: def.category.icon).foregroundStyle(.secondary)
                                        Text(def.name).font(.callout)
                                        Spacer()
                                        Text(formatPercent(def.target))
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let stale = vm.lastRefreshed.map { Date().timeIntervalSince($0) > 300 } ?? true
            if stale && !appState.sloDefinitions.isEmpty {
                Task { await vm.refresh(appState: appState) }
            }
        }
        .sheet(isPresented: $vm.showEditor) {
            SLOEditorSheet(vm: vm).environmentObject(appState)
        }
    }

    // MARK: - Product Section

    private func productSection(productId: String, statuses: [SLOStatus]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let product = appState.products.first(where: { $0.id == productId }) {
                HStack(spacing: 6) {
                    Image(systemName: product.icon).foregroundStyle(.secondary)
                    Text(product.name).font(.headline)
                }
            } else if !productId.isEmpty {
                Text(productId).font(.headline)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(statuses) { status in
                    SLOCardView(
                        status: status,
                        onEdit: {
                            vm.editingDefinition = status.definition
                            vm.showEditor = true
                        },
                        onDelete: {
                            vm.deleteDefinition(id: status.id, appState: appState)
                            vm.statuses.removeAll { $0.id == status.id }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No SLOs Defined").font(.headline).foregroundStyle(.secondary)
            Text("Define Service Level Objectives to track reliability targets for your products.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                vm.startNewDefinition()
            } label: {
                Label("Create Your First SLO", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            // Quick-add from templates
            VStack(alignment: .leading, spacing: 8) {
                Text("Or start from a template:").font(.caption.bold()).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(SLOTemplate.builtIn.prefix(3)) { template in
                        Button {
                            vm.editingDefinition = SLODefinition(
                                name: template.name,
                                sloDescription: template.description,
                                productId: appState.products.first(where: { $0.id != "all" })?.id ?? "",
                                target: template.defaultTarget,
                                windowDays: template.defaultWindowDays,
                                metricQuery: template.metricQueryTemplate,
                                category: template.category
                            )
                            vm.showEditor = true
                        } label: {
                            Label(template.name, systemImage: template.category.icon)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func healthPill(_ count: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.caption.bold())
            Text(label).font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(count > 0 ? color.opacity(0.15) : Color.secondary.opacity(0.08)))
        .foregroundStyle(count > 0 ? color : .secondary)
    }

    private func productChip(_ id: String?, _ label: String) -> some View {
        Button {
            vm.selectedProductFilter = id
        } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(vm.selectedProductFilter == id
                                           ? Color.accentColor.opacity(0.15)
                                           : Color.secondary.opacity(0.08)))
                .foregroundStyle(vm.selectedProductFilter == id ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func formatPercent(_ value: Double) -> String {
        if value >= 0.9999 { return String(format: "%.4f%%", value * 100) }
        if value >= 0.999 { return String(format: "%.3f%%", value * 100) }
        return String(format: "%.2f%%", value * 100)
    }
}

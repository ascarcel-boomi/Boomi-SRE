import SwiftUI

// MARK: - ProductSettingsContent
// Replaces the old manual text-field settings with a discovery-driven,
// AI-assisted resource mapping UI.

struct ProductSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ProductMappingViewModel()

    // Which of the 5 products is selected in the tab bar
    @State private var selectedProductId: String = ""
    @State private var showTemplateSaved = false
    @State private var templateSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Products & Resource Mapping")
                        .font(.title2.bold())
                    Text("Discover and map infrastructure resources to each product. The app filters all views based on your active product selection.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    templateSaved = appState.saveAsDefaultTemplate()
                    showTemplateSaved = true
                } label: {
                    Label("Save as Team Template", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Save confirmed mappings as the default template for new users")
                .popover(isPresented: $showTemplateSaved) {
                    VStack(spacing: 8) {
                        Image(systemName: templateSaved ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(templateSaved ? .green : .red)
                        if templateSaved {
                            Text("Template saved! It will be bundled with the next build.")
                                .font(.caption)
                        } else if let err = appState.lastTemplateError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        } else {
                            Text("Failed to save template.").font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .padding(.bottom, 16)

            // Product tab bar
            productTabBar
                .padding(.bottom, 16)

            Divider()

            // Detail for selected product
            if let product = appState.products.first(where: { $0.id == selectedProductId }) {
                ProductMappingDetail(
                    product: product,
                    vm: vm
                )
            } else {
                Text("Select a product above.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Select first real product on appear
            if selectedProductId.isEmpty {
                selectedProductId = appState.products.first(where: { $0.id != "all" })?.id ?? ""
            }
        }
    }

    // MARK: Product Tab Bar

    private var productTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.products.filter { $0.id != "all" }) { product in
                    let map = appState.resourceMap(for: product.id)
                    let isSelected = selectedProductId == product.id
                    let pending = map.pendingCount

                    Button {
                        selectedProductId = product.id
                        vm.selectedProductId = product.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: product.icon)
                                .font(.caption)
                            Text(product.shortName)
                                .fontWeight(isSelected ? .semibold : .regular)
                            if pending > 0 {
                                Text("\(pending)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.85))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? productColor(product.color).opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? productColor(product.color) : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSelected ? productColor(product.color) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func productColor(_ colorName: String) -> Color {
        switch colorName {
        case "orange": return .orange
        case "blue":   return .blue
        case "green":  return .green
        case "purple": return .purple
        case "red":    return .red
        default:       return .accentColor
        }
    }
}

// MARK: - ProductMappingDetail

private struct ProductMappingDetail: View {
    let product: ProductContext
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState

    @State private var selectedIntegration: String = "Jira"

    private var map: ProductResourceMap {
        appState.resourceMap(for: product.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Product header + action row
            ProductHeaderCard(product: product, map: map, vm: vm, selectedIntegration: selectedIntegration)

            // Integration tabs
            integrationTabPicker

            Divider()

            // Resource list for selected integration
            IntegrationResourcePanel(
                integration: selectedIntegration,
                productId: product.id,
                map: map,
                vm: vm
            )

            // AI Chat
            AIMappingChat(productId: product.id, product: product, vm: vm)
        }
        .onChange(of: product.id) { _, _ in
            selectedIntegration = "Jira"
        }
    }

    private var integrationTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MappedResourceType.integrationNames, id: \.self) { integration in
                    let types = MappedResourceType.types(for: integration)
                    let confirmedCount = types.reduce(0) { $0 + map.confirmed($1).count }
                    let pendingCount = types.reduce(0) { $0 + map.pending($1).count }
                    let isSelected = selectedIntegration == integration

                    Button {
                        selectedIntegration = integration
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: types.first?.icon ?? "square")
                                .font(.caption2)
                            Text(integration)
                                .font(.callout)
                            if confirmedCount > 0 {
                                Text("\(confirmedCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                            if pendingCount > 0 {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - ProductHeaderCard

private struct ProductHeaderCard: View {
    let product: ProductContext
    let map: ProductResourceMap
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState
    let selectedIntegration: String

    private var resourceSummary: String {
        let parts = MappedResourceType.integrationNames.compactMap { integration -> String? in
            let types = MappedResourceType.types(for: integration)
            let count = types.reduce(0) { $0 + map.confirmed($1).count }
            guard count > 0 else { return nil }
            return "\(count) \(integration)"
        }
        return parts.isEmpty ? "No resources mapped yet" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: product.icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.headline)

                Text(resourceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastDiscovered = map.lastDiscoveredAt {
                    Text("Last discovered: \(lastDiscovered.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Action buttons
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    // Discover: fast API fetch only
                    Button {
                        Task { await vm.discoverIntegration(selectedIntegration, for: product.id, appState: appState) }
                    } label: {
                        if vm.isDiscovering {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text(vm.discoveryProgress.isEmpty ? "Discovering..." : vm.discoveryProgress)
                                    .lineLimit(1)
                            }
                        } else {
                            Label("Discover \(selectedIntegration)", systemImage: "sparkle.magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isDiscovering || vm.isAnalyzing)

                    // AI Suggest: runs Claude on discovered resources
                    let hasResources = !(vm.discoveredByIntegration[selectedIntegration]?.isEmpty ?? true)
                    Button {
                        Task { await vm.suggestMappings(integration: selectedIntegration, for: product.id, appState: appState) }
                    } label: {
                        if vm.isAnalyzing {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text(vm.discoveryProgress.isEmpty ? "Analyzing..." : vm.discoveryProgress)
                                    .lineLimit(1)
                            }
                        } else {
                            Label("AI Suggest", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasResources || vm.isDiscovering || vm.isAnalyzing)
                    .help(hasResources ? "Ask AI to suggest which resources belong to \(product.shortName)" : "Discover resources first")
                }

                if map.pendingCount > 0 {
                    Label("\(map.pendingCount) pending AI suggestions", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        if let err = vm.discoveryError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - IntegrationResourcePanel

private struct IntegrationResourcePanel: View {
    let integration: String
    let productId: String
    let map: ProductResourceMap
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState
    @State private var filterText: String = ""       // actual filter (debounced)
    @State private var debouncedFilter: String = ""  // what the user types (immediate)
    @State private var filterDebounceTask: Task<Void, Never>?

    private var types: [MappedResourceType] {
        MappedResourceType.types(for: integration)
    }

    /// Compute available resources ONCE, then split by type — not per-type-per-render.
    private var availableByType: [MappedResourceType: [MappedResource]] {
        Dictionary(grouping: vm.available(for: integration, in: map), by: \.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter resources…", text: $debouncedFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .onChange(of: debouncedFilter) {
                        // Debounce: update the actual filter after a brief pause
                        filterDebounceTask?.cancel()
                        filterDebounceTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                            guard !Task.isCancelled else { return }
                            filterText = debouncedFilter
                        }
                    }
                if !debouncedFilter.isEmpty {
                    Button { debouncedFilter = ""; filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            let grouped = availableByType
            ForEach(types, id: \.rawValue) { type in
                ResourceTypeSection(
                    type: type,
                    productId: productId,
                    map: map,
                    vm: vm,
                    available: grouped[type] ?? [],
                    filterText: filterText
                )
            }

            // Manual add
            ManualAddRow(productId: productId, vm: vm, types: types)
        }
        .padding(.vertical, 4)
        .onChange(of: integration) { debouncedFilter = ""; filterText = "" }
    }
}

// MARK: - ResourceTypeSection

private struct ResourceTypeSection: View {
    let type: MappedResourceType
    let productId: String
    let map: ProductResourceMap
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState

    let available: [MappedResource]
    var filterText: String = ""

    private var confirmed: [MappedResource] { map.confirmed(type) }
    private var pending: [MappedResource] { map.pending(type) }

    private func matches(_ resource: MappedResource) -> Bool {
        guard !filterText.isEmpty else { return true }
        let q = filterText.lowercased()
        return resource.name.lowercased().contains(q)
            || resource.id.lowercased().contains(q)
            || (resource.description?.lowercased().contains(q) ?? false)
    }

    var body: some View {
        let filteredConfirmed = confirmed.filter { matches($0) }
        let filteredPending = pending.filter { matches($0) }
        // For available: only filter when user is actively searching (avoid scanning thousands of items)
        let filteredAvailable: [MappedResource] = filterText.isEmpty
            ? Array(available.prefix(25))
            : available.lazy.filter { matches($0) }.prefix(200).map { $0 }

        // Hide entire section if filter eliminates everything
        let hasAnything = !filteredConfirmed.isEmpty || !filteredPending.isEmpty || !filteredAvailable.isEmpty
            || (filterText.isEmpty && confirmed.isEmpty && pending.isEmpty && available.isEmpty)

        if hasAnything {
            VStack(alignment: .leading, spacing: 6) {
                // Section header
                HStack {
                    Label(type.displayName, systemImage: type.icon)
                        .font(.subheadline.bold())
                    Spacer()
                    if !confirmed.isEmpty {
                        Text("\(confirmed.count) confirmed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if confirmed.isEmpty && pending.isEmpty && available.isEmpty {
                    Text("None mapped yet — run discovery or add manually below.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    // Confirmed
                    if !filteredConfirmed.isEmpty {
                        HStack {
                            Text("Confirmed (\(confirmed.count))")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Remove All") {
                                for r in confirmed {
                                    vm.removeResource(id: r.id, type: r.type, from: productId, appState: appState)
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }

                        ForEach(Array(filteredConfirmed.enumerated()), id: \.element.id) { idx, resource in
                            ConfirmedResourceRow(resource: resource, productId: productId, vm: vm, isEven: idx.isMultiple(of: 2))
                        }
                    }

                    // AI Suggestions
                    if !filteredPending.isEmpty {
                        HStack {
                            Label("AI Suggestions (\(pending.count))", systemImage: "sparkles")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Approve All") {
                                vm.confirmAll(type: type, in: productId, appState: appState)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            Button("Dismiss All") {
                                vm.dismissPending(type: type, in: productId, appState: appState)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)

                        ForEach(Array(filteredPending.enumerated()), id: \.element.id) { idx, resource in
                            SuggestionRow(resource: resource, productId: productId, vm: vm, isEven: idx.isMultiple(of: 2))
                        }
                    }

                    // Available from discovery
                    if !filteredAvailable.isEmpty {
                        let displayLimit = 25
                        let displayed = Array(filteredAvailable.prefix(displayLimit))
                        let remaining = filteredAvailable.count - displayed.count

                        HStack {
                            Text("Available (\(filteredAvailable.count) of \(available.count))")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !filteredAvailable.isEmpty {
                                Button("Add All\(filterText.isEmpty ? "" : " Filtered")") {
                                    for r in filteredAvailable {
                                        vm.addResource(r, to: productId, appState: appState)
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 4)

                        ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, resource in
                            AvailableResourceRow(resource: resource, productId: productId, vm: vm, isEven: idx.isMultiple(of: 2))
                        }
                        if remaining > 0 {
                            Text("Showing \(displayed.count) of \(filteredAvailable.count)\(filterText.isEmpty ? " — type in the filter to search" : "")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 2)
                        }
                    } else if filterText.isEmpty && !available.isEmpty {
                        Text("\(available.count) available — type in the filter above to browse")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Row Views

private struct ConfirmedResourceRow: View {
    let resource: MappedResource
    let productId: String
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState
    var isEven: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Remove button (left side)
            Button {
                vm.removeResource(id: resource.id, type: resource.type, from: productId, appState: appState)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Remove")

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(resource.name)
                    .font(.callout)
                if let desc = resource.description {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let url = resource.url, let u = URL(string: url) {
                Link(destination: u) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isEven ? Color(nsColor: .controlBackgroundColor).opacity(0.4) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct SuggestionRow: View {
    let resource: MappedResource
    let productId: String
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState
    var isEven: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Approve / Dismiss buttons (left side)
            Button {
                vm.confirmResource(id: resource.id, type: resource.type, in: productId, appState: appState)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .help("Approve")

            Button {
                vm.removeResource(id: resource.id, type: resource.type, from: productId, appState: appState)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Dismiss")

            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(resource.name)
                        .font(.callout)
                    if let conf = resource.confidence {
                        Text("\(Int(conf * 100))%")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(confidenceColor(conf).opacity(0.15))
                            .foregroundStyle(confidenceColor(conf))
                            .clipShape(Capsule())
                    }
                }
                if let desc = resource.description {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isEven ? Color.orange.opacity(0.06) : Color.orange.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func confidenceColor(_ c: Double) -> Color {
        c >= 0.8 ? .green : c >= 0.6 ? .orange : .red
    }
}

private struct AvailableResourceRow: View {
    let resource: MappedResource
    let productId: String
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState
    var isEven: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Add button (left side — replaces the empty circle)
            Button {
                vm.addResource(resource, to: productId, appState: appState)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Add to product")

            VStack(alignment: .leading, spacing: 1) {
                Text(resource.name)
                    .font(.callout)
                if let desc = resource.description {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isEven ? Color(nsColor: .controlBackgroundColor).opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - ManualAddRow

private struct ManualAddRow: View {
    let productId: String
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState

    let types: [MappedResourceType]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add Manually")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("", selection: $vm.manualAddType) {
                    ForEach(types, id: \.rawValue) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .fixedSize()

                TextField("Resource ID (e.g. CAMSRE)", text: $vm.manualAddId)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                    .onSubmit { vm.addManual(to: productId, appState: appState) }

                TextField("Display name (optional)", text: $vm.manualAddName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                    .onSubmit { vm.addManual(to: productId, appState: appState) }

                Button("Add") {
                    vm.addManual(to: productId, appState: appState)
                }
                .buttonStyle(.bordered)
                .disabled(vm.manualAddId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 8)
        .onAppear {
            vm.manualAddType = types.first ?? .jiraProject
        }
    }
}

// MARK: - AIMappingChat

private struct AIMappingChat: View {
    let productId: String
    let product: ProductContext
    @ObservedObject var vm: ProductMappingViewModel
    @EnvironmentObject var appState: AppState

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chat toggle header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("AI Resource Assistant")
                        .font(.subheadline.bold())
                    Spacer()
                    if !vm.chatHistory.isEmpty {
                        Text("\(vm.chatHistory.count) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Chat history
                    if !vm.chatHistory.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(vm.chatHistory.indices, id: \.self) { idx in
                                    let msg = vm.chatHistory[idx]
                                    ChatBubble(role: msg.role, text: msg.text)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Pending operations preview
                    if !vm.pendingOps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Proposed changes (\(vm.pendingOps.count)):")
                                .font(.caption.bold())
                            ForEach(vm.pendingOps.indices, id: \.self) { i in
                                let op = vm.pendingOps[i]
                                let icon = op.action == "add" ? "plus.circle.fill" : "minus.circle.fill"
                                let color: Color = op.action == "add" ? .green : .red
                                HStack(spacing: 6) {
                                    Image(systemName: icon).foregroundStyle(color).font(.caption)
                                    Text("\(op.action) \(op.id) (\(op.type))")
                                        .font(.caption.monospaced())
                                    if let reason = op.reason {
                                        Text("— \(reason)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                Button("Apply Changes") {
                                    vm.applyPendingOps(for: productId, appState: appState)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Dismiss") {
                                    vm.dismissPendingOps()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Example prompts
                    if vm.chatHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Try:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach([
                                "Add all repos with '\(product.shortName.lowercased())' in their name",
                                "Map the CAMSRE Jira project to this product",
                                "Remove any test or staging resources",
                                "What Grafana dashboards should belong here?"
                            ], id: \.self) { prompt in
                                Button {
                                    vm.chatInput = prompt
                                } label: {
                                    Text("\"\(prompt)\"")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                        .multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Input field
                    HStack(spacing: 8) {
                        TextField("Ask AI to add or remove resources...", text: $vm.chatInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await vm.submitChat(for: productId, appState: appState) }
                            }
                        Button {
                            Task { await vm.submitChat(for: productId, appState: appState) }
                        } label: {
                            if vm.isProcessingChat {
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(vm.chatInput.trimmingCharacters(in: .whitespaces).isEmpty || vm.isProcessingChat)
                    }

                    if let err = vm.chatError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(Color.purple.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - ChatBubble

private struct ChatBubble: View {
    let role: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: role == "user" ? "person.circle" : "sparkles")
                .font(.caption)
                .foregroundStyle(role == "user" ? Color.secondary : Color.purple)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

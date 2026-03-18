import SwiftUI
import Charts

/// Native AWS Cost Explorer dashboard — replaces the Python-bridge cost reports.
struct CostExplorerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CostExplorerViewModel()
    @State private var awsProfiles: [AWSProfile] = []

    // Table state
    @State private var selectedRowName: String?
    @State private var sortOrder = [KeyPathComparator(\CostDisplayRow.amount, order: .reverse)]
    @State private var detailPaneHeight: CGFloat = 380

    private let awsAuth = AWSAuthService()
    private static let minDetailHeight: CGFloat = 200
    private static let maxDetailHeight: CGFloat = 800

    /// Filter profiles to product-relevant AWS accounts when a product is selected.
    /// When a product is selected: ONLY show that product's accounts — no fallback.
    /// When no product filter is active (All Products): show all profiles.
    private var filteredProfiles: [AWSProfile] {
        let activeAccounts = appState.activeAWSAccounts
        guard !activeAccounts.isEmpty else { return awsProfiles }
        return awsProfiles.filter { profile in
            activeAccounts.contains { profile.name.contains($0) || profile.accountId == $0 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if vm.isLoading {
                loadingView
            } else if let error = vm.errorMessage {
                errorView(error)
            } else if vm.costResult != nil {
                resultView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: appState.refreshTrigger) {
            vm.fetch(profile: appState.awsSSOProfile)
        }
        .onChange(of: appState.activeProductIds) {
            // Auto-select first product-relevant profile when product changes
            if let first = filteredProfiles.first, appState.awsSSOProfile != first.name {
                appState.awsSSOProfile = first.name
                appState.saveConfig()
                refetchIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AWS Cost Explorer")
                        .font(.title2.bold())
                    if let accountLabel = currentAccountLabel {
                        Text(accountLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                authBadge

                Button {
                    vm.fetch(profile: appState.awsSSOProfile)
                } label: {
                    Label(vm.isLoading ? "Loading..." : "Fetch Costs",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading || appState.awsSSOProfile.isEmpty)
            }

            HStack(spacing: 16) {
                Picker("Account", selection: $appState.awsSSOProfile) {
                    ForEach(filteredProfiles) { profile in
                        Text(profile.displayName).tag(profile.name)
                    }
                }
                .frame(minWidth: 250, maxWidth: 400)
                .onChange(of: appState.awsSSOProfile) {
                    appState.saveConfig()
                    refetchIfNeeded()
                }

                Picker("Period", selection: $vm.timeRange) {
                    ForEach(CostTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .frame(width: 180)
                .onChange(of: vm.timeRange) { refetchIfNeeded() }

                Picker("Group by", selection: $vm.groupBy) {
                    ForEach(CostGroupBy.allCases, id: \.self) { g in
                        Text(g.label).tag(g)
                    }
                }
                .frame(width: 160)
                .onChange(of: vm.groupBy) {
                    selectedRowName = nil
                    vm.clearDrillDown()
                    refetchIfNeeded()
                }

                Picker("View", selection: $appState.viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue,
                              systemImage: mode == .table ? "tablecells" : "chart.bar.fill")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear { loadProfiles() }
    }

    /// Re-fetch cost data if the user has already fetched at least once.
    private func refetchIfNeeded() {
        guard vm.costResult != nil || vm.errorMessage != nil else { return }
        vm.fetch(profile: appState.awsSSOProfile)
    }

    private func loadProfiles() {
        var list = awsAuth.listProfiles()
        for i in list.indices {
            if !list[i].accountId.isEmpty,
               let name = appState.awsAccountNames[list[i].accountId] {
                list[i].friendlyName = name
            }
        }
        awsProfiles = list

        // Resolve unknown names in the background
        let unknowns = list.filter { !$0.accountId.isEmpty && $0.friendlyName.isEmpty }
        for profile in unknowns {
            Task {
                if let alias = await awsAuth.resolveAccountName(profile: profile.name, accountId: profile.accountId) {
                    await MainActor.run {
                        appState.awsAccountNames[profile.accountId] = alias.uppercased()
                        appState.saveConfig()
                        // Reload to pick up the new name
                        var updated = awsAuth.listProfiles()
                        for i in updated.indices {
                            if !updated[i].accountId.isEmpty,
                               let name = appState.awsAccountNames[updated[i].accountId] {
                                updated[i].friendlyName = name
                            }
                        }
                        awsProfiles = updated
                    }
                }
            }
        }
    }

    /// Human-readable label for the currently selected account.
    private var currentAccountLabel: String? {
        let profile = appState.awsSSOProfile
        guard !profile.isEmpty else { return nil }
        if let p = awsProfiles.first(where: { $0.name == profile }) {
            if !p.friendlyName.isEmpty && !p.accountId.isEmpty {
                return "\(p.friendlyName) (\(p.accountId))"
            }
            if !p.accountId.isEmpty {
                return "Account \(p.accountId)"
            }
        }
        return nil
    }

    private var authBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.awsAuthStatus.color)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusLabel: String {
        switch appState.awsAuthStatus {
        case .authenticated: return "Authenticated"
        case .expired: return "Session expired"
        case .checking: return "Checking..."
        default: return "Not connected"
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("Querying AWS Cost Explorer...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Profile: \(appState.awsSSOProfile)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Cost Explorer Error")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 600)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retry") {
                    vm.fetch(profile: appState.awsSSOProfile)
                }
                .buttonStyle(.borderedProminent)
                if !appState.awsAuthStatus.isOK {
                    Button("Open Settings") {
                        appState.selectedReport = nil
                        appState.selectedTicketKey = nil
                        appState.showSettings = true
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("AWS Cost Explorer")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select a time range and click \"Fetch Costs\" to query Cost Explorer for the active profile.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if appState.awsSSOProfile.isEmpty {
                Text("No AWS profile selected — configure one in Settings first.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !appState.awsAuthStatus.isOK {
                Text("AWS session may be expired. Authenticate first.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultView: some View {
        let rows = vm.displayRows()

        return VStack(alignment: .leading, spacing: 0) {
            // Summary cards — always visible
            summaryCards
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            // AI Analysis panel
            aiPanel
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            // Main content area (fills available space above detail pane)
            Group {
                switch appState.viewMode {
                case .chart:
                    chartContent
                case .table:
                    tableContentBody(rows: rows)
                }
            }
            .frame(maxHeight: .infinity)

            // Shared detail pane (both chart and table modes)
            if let name = selectedRowName,
               let row = rows.first(where: { $0.name == name }) {
                resizeHandle
                detailPane(row: row, totalCost: vm.costResult?.totalCost ?? 0)
                    .frame(height: detailPaneHeight)
            }
        }
        .onChange(of: selectedRowName) {
            if let name = selectedRowName {
                vm.fetchDrillDown(name: name)
            } else {
                vm.clearDrillDown()
            }
        }
    }

    // MARK: - AI Analysis Panel

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Buttons + query row
            HStack(spacing: 10) {
                Button {
                    Task { await vm.analyzeCosts() }
                } label: {
                    if vm.isAnalyzingCosts {
                        Label("Analyzing…", systemImage: "sparkles")
                    } else {
                        Label("Analyze Costs", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(vm.isAnalyzingCosts)

                if vm.aiAnalysis != nil {
                    Button {
                        vm.aiAnalysis = nil
                        vm.aiError = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear analysis")
                }

                Spacer()

                // Natural language query
                TextField("Ask a question about these costs…", text: $vm.naturalLanguageQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                    .onSubmit { Task { await vm.askCostQuestion() } }
                    .disabled(vm.isAnalyzingCosts)

                Button {
                    Task { await vm.askCostQuestion() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(vm.naturalLanguageQuery.isEmpty ? Color.secondary : Color.accentColor)
                .disabled(vm.naturalLanguageQuery.trimmingCharacters(in: .whitespaces).isEmpty || vm.isAnalyzingCosts)
            }

            // Loading
            if vm.isAnalyzingCosts {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Claude is analyzing your AWS costs…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error
            if let err = vm.aiError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Analysis result
            if let analysis = vm.aiAnalysis {
                ScrollView {
                    InlineMarkdownText(text: analysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 260)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.2)))
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard(
                title: "Total Cost",
                value: vm.formatCurrency(vm.costResult?.totalCost ?? 0),
                icon: "dollarsign.circle.fill",
                color: .blue
            )

            summaryCard(
                title: "Services",
                value: "\(vm.costResult?.aggregated.count ?? 0)",
                icon: "square.stack.3d.up.fill",
                color: .purple
            )

            summaryCard(
                title: "Period",
                value: vm.timeRange.rawValue,
                icon: "calendar",
                color: .orange
            )

            if vm.forecast > 0 {
                summaryCard(
                    title: "This Month Forecast",
                    value: vm.formatCurrency(vm.forecast),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green
                )
            }

            Spacer()
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .padding(12)
        .frame(minWidth: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
    }

    // MARK: - Chart Content (interactive, clickable)

    private var chartContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Bar chart (left) + Pie chart (right) side by side
                if let result = vm.costResult {
                    HStack(alignment: .top, spacing: 20) {
                        interactiveBarChart(items: Array(result.aggregated.prefix(15)),
                                            title: "Top \(min(result.aggregated.count, 15)) by \(vm.groupBy.label)")
                            .frame(maxWidth: .infinity)

                        interactivePieChart(items: result.aggregated)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Monthly trend (full width, not clickable)
                if vm.monthlyTotals.count > 1 {
                    trendChart
                }
            }
            .padding(20)
        }
    }

    // MARK: - Interactive Horizontal Bar Chart

    private func interactiveBarChart(items: [CostItem], title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Chart(items, id: \.name) { item in
                BarMark(
                    x: .value("Cost", item.amount),
                    y: .value(vm.groupBy.label, vm.shortenServiceName(item.name))
                )
                .foregroundStyle(selectedRowName == item.name ? Color.accentColor : Color.blue)
                .opacity(selectedRowName == nil || selectedRowName == item.name ? 1 : 0.4)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatCompactAxis(v))
                                .font(.caption)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption)
                }
            }
            .chartPlotStyle { plot in
                plot.frame(height: CGFloat(max(items.count * 28, 150)))
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotOrigin = geo[plotFrame].origin
                            let relativeY = location.y - plotOrigin.y
                            let plotHeight = geo[plotFrame].height
                            let barHeight = plotHeight / CGFloat(items.count)
                            let index = Int(relativeY / barHeight)
                            if index >= 0 && index < items.count {
                                let tapped = items[index].name
                                selectedRowName = (selectedRowName == tapped) ? nil : tapped
                            }
                        }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    // MARK: - Monthly Trend Chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Trend")
                .font(.headline)

            Chart(vm.monthlyTotals) { period in
                BarMark(
                    x: .value("Month", period.displayMonth),
                    y: .value("Cost", period.amount)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if period.amount > 0 {
                        Text(vm.formatCurrency(period.amount))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatCompactAxis(v))
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(minHeight: 250)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    // MARK: - Interactive Pie Chart

    private func interactivePieChart(items: [CostItem]) -> some View {
        let top10 = Array(items.prefix(10))
        let othersAmount = items.dropFirst(10).reduce(0.0) { $0 + $1.amount }

        struct PieSlice: Identifiable {
            var id: String { name }
            let name: String
            let originalName: String  // full name for selection
            let amount: Double
        }
        var slices = top10.map { PieSlice(name: vm.shortenServiceName($0.name), originalName: $0.name, amount: $0.amount) }
        if othersAmount > 0 {
            slices.append(PieSlice(name: "Others", originalName: "", amount: othersAmount))
        }
        let totalAmount = slices.reduce(0.0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Cost Distribution")
                .font(.headline)

            HStack(spacing: 20) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Cost", slice.amount),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Item", slice.name))
                    .cornerRadius(4)
                    .opacity(selectedRowName == nil || selectedRowName == slice.originalName ? 1 : 0.4)
                    .annotation(position: .overlay) {
                        let pct = totalAmount > 0 ? (slice.amount / totalAmount) * 100 : 0
                        if pct > 5 {
                            Text(String(format: "%.0f%%", pct))
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(minWidth: 300, minHeight: 300)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let center = CGPoint(
                                    x: geo[plotFrame].midX,
                                    y: geo[plotFrame].midY
                                )
                                let dx = location.x - center.x
                                let dy = location.y - center.y
                                var angle = atan2(dy, dx) * 180 / .pi + 90
                                if angle < 0 { angle += 360 }
                                // Map angle to slice
                                var cumulative = 0.0
                                for slice in slices {
                                    let sliceAngle = (slice.amount / totalAmount) * 360
                                    if angle >= cumulative && angle < cumulative + sliceAngle {
                                        if !slice.originalName.isEmpty {
                                            selectedRowName = (selectedRowName == slice.originalName) ? nil : slice.originalName
                                        }
                                        return
                                    }
                                    cumulative += sliceAngle
                                }
                            }
                    }
                }

                // Legend (clickable)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(slices) { slice in
                        Button {
                            if !slice.originalName.isEmpty {
                                selectedRowName = (selectedRowName == slice.originalName) ? nil : slice.originalName
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(slice.name)
                                    .font(.callout)
                                    .foregroundStyle(selectedRowName == slice.originalName ? .primary : .secondary)
                                Spacer()
                                Text(vm.formatCurrency(slice.amount))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selectedRowName == slice.originalName
                                          ? Color.accentColor.opacity(0.1)
                                          : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 200, maxWidth: 300)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    }

    private func formatCompactAxis(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: - Table Content (sortable, selectable, resizable detail pane)

    private func tableContentBody(rows: [CostDisplayRow]) -> some View {
        let sorted = rows.sorted(using: sortOrder)
        return costTable(sorted: sorted)
    }

    private func costTable(sorted: [CostDisplayRow]) -> some View {
        Table(sorted, selection: $selectedRowName, sortOrder: $sortOrder) {
            TableColumn(vm.groupBy.label, value: \.name) { row in
                Text(vm.shortenServiceName(row.name))
                    .font(.body)
                    .lineLimit(1)
                    .help(row.name)
            }
            .width(min: 180, ideal: 300)

            TableColumn("Cost", value: \.amount) { row in
                Text(vm.formatCurrency(row.amount))
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 100, ideal: 140)

            TableColumn("% of Total", value: \.percentOfTotal) { row in
                HStack(spacing: 6) {
                    // Mini progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: geo.size.width * min(row.percentOfTotal / 100, 1))
                        }
                    }
                    .frame(width: 60, height: 8)

                    Text(String(format: "%.1f%%", row.percentOfTotal))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .width(min: 130, ideal: 150)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .overlay {
                // Wider hit area with visual grip
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
            }
            .frame(height: 9)
            .contentShape(Rectangle())
            .cursor(.resizeUpDown)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newHeight = detailPaneHeight - value.translation.height
                        detailPaneHeight = min(max(newHeight, Self.minDetailHeight), Self.maxDetailHeight)
                    }
            )
    }

    // MARK: - Detail Pane

    private func detailPane(row: CostDisplayRow, totalCost: Double) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header row
                detailHeader(row: row, totalCost: totalCost)

                // Two-column layout: monthly trend on left, drill-down on right
                HStack(alignment: .top, spacing: 20) {
                    // Left column: monthly breakdown
                    if row.monthlyBreakdown.count > 1 {
                        monthlyBreakdownSection(row: row)
                            .frame(maxWidth: .infinity)
                    }

                    // Right column: drill-down breakdown
                    drillDownSection(row: row)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Detail Header

    private func detailHeader(row: CostDisplayRow, totalCost: Double) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Name and type
            VStack(alignment: .leading, spacing: 4) {
                Text(detailTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(row.name)
                    .font(.headline)
                    .textSelection(.enabled)
                if vm.shortenServiceName(row.name) != row.name {
                    Text(vm.shortenServiceName(row.name))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Cost summary cards
            HStack(spacing: 16) {
                miniCard(label: "Total Cost", value: vm.formatCurrency(row.amount))
                miniCard(label: "% of Total", value: String(format: "%.1f%%", row.percentOfTotal))
                if row.monthlyBreakdown.count > 1 {
                    let avg = row.amount / Double(row.monthlyBreakdown.count)
                    miniCard(label: "Monthly Avg", value: vm.formatCurrency(avg))
                    // Month-over-month change
                    if let mom = monthOverMonthChange(row: row) {
                        miniCard(label: "MoM Change", value: mom.label, color: mom.color)
                    }
                }
            }
        }
    }

    private var detailTitle: String {
        switch vm.groupBy {
        case .service: return "Service"
        case .region: return "Region"
        case .linkedAccount: return "Linked Account"
        }
    }

    private func miniCard(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private struct MoMResult {
        let label: String
        let color: Color
    }

    private func monthOverMonthChange(row: CostDisplayRow) -> MoMResult? {
        let nonZero = row.monthlyBreakdown.filter { $0.amount > 0 }
        guard nonZero.count >= 2 else { return nil }
        let prev = nonZero[nonZero.count - 2].amount
        let curr = nonZero[nonZero.count - 1].amount
        guard prev > 0 else { return nil }
        let pct = ((curr - prev) / prev) * 100
        let sign = pct >= 0 ? "+" : ""
        let color: Color = pct > 5 ? .red : (pct < -5 ? .green : .primary)
        return MoMResult(label: "\(sign)\(String(format: "%.1f%%", pct))", color: color)
    }

    // MARK: - Monthly Breakdown Section

    private func monthlyBreakdownSection(row: CostDisplayRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly Trend")
                .font(.subheadline.bold())

            // Bar chart
            Chart(row.monthlyBreakdown) { m in
                BarMark(
                    x: .value("Month", m.month),
                    y: .value("Cost", m.amount)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if m.amount > 0 {
                        Text(vm.formatCurrency(m.amount))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.caption)
                }
            }
            .frame(height: 130)

            // Monthly table
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("Month").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Cost").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("% of Month").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                ForEach(row.monthlyBreakdown) { m in
                    GridRow {
                        Text(m.month).font(.callout)
                        Text(vm.formatCurrency(m.amount))
                            .font(.callout.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(monthPercentLabel(itemName: row.name, month: m.month))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
    }

    private func monthPercentLabel(itemName: String, month: String) -> String {
        guard let result = vm.costResult,
              let period = result.periods.first(where: { $0.displayMonth == month }) else { return "-" }
        let monthTotal = period.total
        guard monthTotal > 0,
              let item = period.items.first(where: { $0.name == itemName }) else { return "-" }
        return String(format: "%.1f%%", (item.amount / monthTotal) * 100)
    }

    // MARK: - Drill-Down Section

    private func drillDownSection(row: CostDisplayRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Breakdown by \(vm.drillDownGroupLabel)")
                .font(.subheadline.bold())

            if vm.isLoadingDrillDown {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading \(vm.drillDownGroupLabel.lowercased()) breakdown...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = vm.drillDownError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { vm.fetchDrillDown(name: row.name) }
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else if let drillDown = vm.drillDownResult {
                drillDownContent(drillDown: drillDown, parentAmount: row.amount)
            } else {
                Text("Select a row to see the \(vm.drillDownGroupLabel.lowercased()) breakdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
    }

    private func drillDownContent(drillDown: CostResult, parentAmount: Double) -> some View {
        let items = drillDown.aggregated
        let top = Array(items.prefix(15))

        return VStack(alignment: .leading, spacing: 10) {
            // Horizontal bar chart of top items
            Chart(top, id: \.name) { item in
                BarMark(
                    x: .value("Cost", item.amount),
                    y: .value(vm.drillDownGroupLabel, vm.shortenServiceName(item.name))
                )
                .foregroundStyle(.purple.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 4) {
                    Text(vm.formatCurrency(item.amount))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.caption)
                }
            }
            .frame(height: CGFloat(max(top.count * 24, 100)))

            Divider()

            // Full table
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text(vm.drillDownGroupLabel)
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Cost").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("% of Item").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                ForEach(items, id: \.name) { item in
                    GridRow {
                        Text(vm.shortenServiceName(item.name))
                            .font(.callout)
                            .lineLimit(1)
                            .help(item.name)
                        Text(vm.formatCurrency(item.amount))
                            .font(.callout.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(parentAmount > 0
                             ? String(format: "%.1f%%", (item.amount / parentAmount) * 100)
                             : "-")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            if items.count > 15 {
                Text("\(items.count - 15) more items not shown")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

}


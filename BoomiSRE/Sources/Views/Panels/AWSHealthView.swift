import SwiftUI
import Charts

// MARK: - Main View

struct AWSHealthView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = AWSHealthViewModel()

    /// AWS profiles filtered by the active product context.
    /// When a product is selected: ONLY show profiles matching that product's AWS accounts.
    /// When no product filter is active (All Products): show all profiles.
    private var filteredProfiles: [String] {
        let allProfiles = appState.favoriteAWSProfiles.isEmpty
            ? ["default"]
            : appState.favoriteAWSProfiles
        let activeAccounts = appState.activeAWSAccounts
        guard !activeAccounts.isEmpty else { return allProfiles }
        return allProfiles.filter { profile in
            activeAccounts.contains { accountId in
                profile.contains(accountId) || profile.lowercased() == accountId.lowercased()
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                headerBar
                if viewModel.sessionExpired {
                    sessionExpiredBanner
                }
                if viewModel.crossAccountMode {
                    crossAccountBody
                } else {
                    singleAccountBody
                }
            }
            .background(Color(NSColor.windowBackgroundColor))

            // Resource detail slide-over panel
            if let resource = activeDetailResource {
                Divider()
                AWSResourceDetailView(
                    resource: resource,
                    profile: viewModel.selectedProfile,
                    region: viewModel.selectedRegion
                ) { clearDetailResource() }
                .frame(width: 380)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear { initialLoad() }
        .onChange(of: appState.activeProductIds) {
            // Re-load with the first profile matching the new product filter
            let profiles = filteredProfiles
            if let first = profiles.first {
                Task { await viewModel.refreshAll(profile: first, region: nil) }
            }
        }
    }

    private var activeDetailResource: AWSResourceDetailView.Resource? {
        if let ec2 = viewModel.selectedEC2 { return .ec2(ec2) }
        if let alb = viewModel.selectedALB { return .alb(alb) }
        if let cluster = viewModel.selectedCluster { return .rdsCluster(cluster) }
        if let rds = viewModel.selectedRDS { return .rdsInstance(rds) }
        if let fn = viewModel.selectedLambda { return .lambda(fn) }
        if let alarm = viewModel.selectedAlarm { return .alarm(alarm) }
        return nil
    }

    private func clearDetailResource() {
        viewModel.selectedEC2 = nil
        viewModel.selectedALB = nil
        viewModel.selectedCluster = nil
        viewModel.selectedRDS = nil
        viewModel.selectedLambda = nil
        viewModel.selectedAlarm = nil
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Account picker
                accountPicker
                Spacer()
                // Cross-account toggle
                Toggle("Cross-Account", isOn: $viewModel.crossAccountMode)
                    .toggleStyle(.checkbox)
                    .onChange(of: viewModel.crossAccountMode) { _, enabled in
                        if enabled {
                            Task { await viewModel.fetchCrossAccount(profiles: filteredProfiles, region: viewModel.selectedRegion) }
                        }
                    }
                // AI Analyze button
                Button { Task { await viewModel.analyzeInfrastructure() } } label: {
                    Label("Analyze", systemImage: "sparkles")
                        .font(.caption)
                }
                .disabled(viewModel.selectedProfile.isEmpty)
                // Refresh
                Button { Task { await viewModel.refreshAll(profile: viewModel.selectedProfile, region: viewModel.selectedRegion) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.selectedProfile.isEmpty)
                .help("Refresh all sections")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Region filter chips
            if !viewModel.availableRegions.isEmpty && !viewModel.crossAccountMode {
                regionFilter
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            // NLQ bar
            if !viewModel.crossAccountMode {
                naturalLanguageBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var accountPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let profiles = filteredProfiles
                ForEach(profiles, id: \.self) { profile in
                    Button(action: {
                        Task { await viewModel.refreshAll(profile: profile, region: nil) }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(viewModel.selectedProfile == profile ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(appState.awsAccountNames[profile] ?? profile)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                                .fill(viewModel.selectedProfile == profile
                                      ? Color.accentColor.opacity(0.15)
                                      : Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall)
                                        .stroke(viewModel.selectedProfile == profile
                                                ? Color.accentColor
                                                : Color(NSColor.separatorColor), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                if profiles.isEmpty && !appState.activeAWSAccounts.isEmpty {
                    Text("No AWS accounts mapped to this product")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Manage Products") { appState.showSettings = true; appState.selectedSettingsTab = "products" }
                        .font(.caption).foregroundColor(.accentColor)
                } else if appState.favoriteAWSProfiles.isEmpty {
                    Button("Manage Accounts") { appState.showSettings = true }
                        .font(.caption).foregroundColor(.accentColor)
                }
            }
        }
    }

    private var regionFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                regionChip(label: "All Regions", region: nil)
                ForEach(viewModel.availableRegions, id: \.self) { region in
                    regionChip(label: region, region: region)
                }
            }
        }
    }

    private func regionChip(label: String, region: String?) -> some View {
        let selected = viewModel.selectedRegion == region
        return Button(action: {
            viewModel.selectedRegion = region
        }) {
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        .overlay(Capsule().stroke(selected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1))
                )
                .foregroundColor(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var naturalLanguageBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("Ask about your infrastructure…", text: $viewModel.naturalLanguageQuery)
                .font(.caption)
                .onSubmit { Task { await viewModel.submitNLQuery() } }
            if viewModel.isQueryingNLQ {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(DesignTokens.cornerRadiusSmall)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall).stroke(Color(NSColor.separatorColor), lineWidth: 1))
    }

    // MARK: - Session Expired Banner

    private var sessionExpiredBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text("AWS session expired.")
            Button("Re-login in Settings") { appState.showSettings = true }
                .foregroundColor(.accentColor)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.15))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Single Account Body

    private var singleAccountBody: some View {
        ScrollView {
            VStack(spacing: 12) {
                if viewModel.selectedProfile.isEmpty {
                    emptyState
                } else {
                    summaryCards
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    if let analysis = viewModel.aiAnalysis {
                        aiAnalysisPanel(analysis)
                            .padding(.horizontal, 12)
                    }

                    if let answer = viewModel.nlqResult {
                        nlqAnswerPanel(answer)
                            .padding(.horizontal, 12)
                    }

                    Group {
                        ec2Section
                        asgSection
                        albSection
                        rdsSection
                        alarmsSection
                        lambdaSection
                        activitySection
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            SummaryCard(
                icon: "server.rack",
                title: "EC2 Instances",
                subtitle: ec2Summary,
                status: viewModel.ec2HealthStatus,
                isLoading: viewModel.isLoadingEC2
            ) { toggleSection("ec2") }

            SummaryCard(
                icon: "arrow.trianglehead.2.clockwise.rotate.90",
                title: "Auto Scaling",
                subtitle: asgSummary,
                status: viewModel.asgHealthStatus,
                isLoading: viewModel.isLoadingASG
            ) { toggleSection("asg") }

            SummaryCard(
                icon: "network",
                title: "Load Balancers",
                subtitle: albSummary,
                status: viewModel.albHealthStatus,
                isLoading: viewModel.isLoadingALB
            ) { toggleSection("alb") }

            SummaryCard(
                icon: "cylinder.split.1x2",
                title: "Databases",
                subtitle: rdsSummary,
                status: viewModel.rdsHealthStatus,
                isLoading: viewModel.isLoadingRDS
            ) { toggleSection("rds") }

            SummaryCard(
                icon: "bell.badge",
                title: "CW Alarms",
                subtitle: alarmsSummary,
                status: viewModel.alarmsHealthStatus,
                isLoading: viewModel.isLoadingAlarms
            ) { toggleSection("alarms") }

            SummaryCard(
                icon: "function",
                title: "Lambda",
                subtitle: lambdaSummary,
                status: viewModel.lambdaHealthStatus,
                isLoading: viewModel.isLoadingLambda
            ) { toggleSection("lambda") }
        }
    }

    // MARK: - Summary text helpers

    private var ec2Summary: String {
        let running = viewModel.filteredEC2.filter { $0.isRunning }.count
        let stopped = viewModel.filteredEC2.filter { $0.state == "stopped" }.count
        if running == 0 && stopped == 0 { return "No instances" }
        var parts = ["\(running) running"]
        if stopped > 0 { parts.append("\(stopped) stopped") }
        return parts.joined(separator: ", ")
    }

    private var asgSummary: String {
        let total = viewModel.filteredASG.count
        let unhealthy = viewModel.filteredASG.filter { !$0.isHealthy }.count
        if total == 0 { return "No ASGs" }
        if unhealthy == 0 { return "\(total) ASGs, all healthy" }
        return "\(total) ASGs, \(unhealthy) unhealthy"
    }

    private var albSummary: String {
        let total = viewModel.filteredALB.count
        let unhealthyTargets = viewModel.unhealthyTargetsCount
        if total == 0 { return "No load balancers" }
        if unhealthyTargets == 0 { return "\(total) ALBs, targets healthy" }
        return "\(total) ALBs, \(unhealthyTargets) unhealthy targets"
    }

    private var rdsSummary: String {
        let clusters = viewModel.auroraClusters.count
        let instances = viewModel.rdsInstances.count
        if clusters == 0 && instances == 0 { return "No databases" }
        var parts: [String] = []
        if clusters > 0 { parts.append("\(clusters) cluster\(clusters == 1 ? "" : "s")") }
        if instances > 0 { parts.append("\(instances) instance\(instances == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    private var alarmsSummary: String {
        let firing = viewModel.firingAlarmsCount
        let total = viewModel.alarms.count
        if total == 0 { return "No alarms" }
        if firing == 0 { return "\(total) alarms, all OK" }
        return "\(firing) firing"
    }

    private var lambdaSummary: String {
        let count = viewModel.lambdaFunctions.count
        let errors = viewModel.totalLambdaErrors
        if count == 0 { return "No functions" }
        if errors == 0 { return "\(count) functions, 0 errors" }
        return "\(count) functions, \(errors) errors (24h)"
    }

    // MARK: - EC2 Section

    private var ec2Section: some View {
        InfraSection(
            id: "ec2",
            title: "EC2 Instances",
            count: viewModel.filteredEC2.count,
            status: viewModel.ec2HealthStatus,
            isLoading: viewModel.isLoadingEC2,
            error: viewModel.ec2Error,
            isExpanded: viewModel.expandedSections.contains("ec2"),
            profile: viewModel.selectedProfile
        ) { toggleSection("ec2") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            EC2ListView(
                instances: viewModel.filteredEC2,
                selectedInstance: $viewModel.selectedEC2
            )
        }
    }

    // MARK: - ASG Section

    private var asgSection: some View {
        InfraSection(
            id: "asg",
            title: "Auto Scaling Groups",
            count: viewModel.filteredASG.count,
            status: viewModel.asgHealthStatus,
            isLoading: viewModel.isLoadingASG,
            error: viewModel.asgError,
            isExpanded: viewModel.expandedSections.contains("asg"),
            profile: viewModel.selectedProfile
        ) { toggleSection("asg") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            ASGListView(groups: viewModel.filteredASG)
        }
    }

    // MARK: - ALB Section

    private var albSection: some View {
        InfraSection(
            id: "alb",
            title: "Load Balancers",
            count: viewModel.filteredALB.count,
            status: viewModel.albHealthStatus,
            isLoading: viewModel.isLoadingALB,
            error: viewModel.albError,
            isExpanded: viewModel.expandedSections.contains("alb"),
            profile: viewModel.selectedProfile
        ) { toggleSection("alb") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            ALBListView(
                albs: viewModel.filteredALB,
                targetHealth: viewModel.targetHealthByGroup,
                targetGroups: viewModel.targetGroupsByALB,
                profile: viewModel.selectedProfile,
                region: viewModel.selectedRegion
            ) { arn in
                Task { await viewModel.loadTargetHealth(albArn: arn, profile: viewModel.selectedProfile, region: viewModel.selectedRegion) }
            }
        }
    }

    // MARK: - RDS Section

    private var rdsSection: some View {
        InfraSection(
            id: "rds",
            title: "Databases",
            count: viewModel.auroraClusters.count + viewModel.rdsInstances.count,
            status: viewModel.rdsHealthStatus,
            isLoading: viewModel.isLoadingRDS,
            error: viewModel.rdsError,
            isExpanded: viewModel.expandedSections.contains("rds"),
            profile: viewModel.selectedProfile
        ) { toggleSection("rds") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            RDSListView(
                clusters: viewModel.auroraClusters,
                instances: viewModel.rdsInstances,
                selectedCluster: $viewModel.selectedCluster,
                selectedInstance: $viewModel.selectedRDS
            )
        }
    }

    // MARK: - Alarms Section

    private var alarmsSection: some View {
        InfraSection(
            id: "alarms",
            title: "CloudWatch Alarms",
            count: viewModel.alarms.count,
            status: viewModel.alarmsHealthStatus,
            isLoading: viewModel.isLoadingAlarms,
            error: viewModel.alarmsError,
            isExpanded: viewModel.expandedSections.contains("alarms"),
            profile: viewModel.selectedProfile
        ) { toggleSection("alarms") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            AlarmsListView(
                alarms: viewModel.alarms,
                selectedAlarm: $viewModel.selectedAlarm
            ) {
                Task {
                    let result = await viewModel.analyzeAlarms()
                    viewModel.aiAnalysis = result
                    viewModel.showAIPanel = true
                }
            }
        }
    }

    // MARK: - Lambda Section

    private var lambdaSection: some View {
        InfraSection(
            id: "lambda",
            title: "Lambda Functions",
            count: viewModel.lambdaFunctions.count,
            status: viewModel.lambdaHealthStatus,
            isLoading: viewModel.isLoadingLambda,
            error: viewModel.lambdaError,
            isExpanded: viewModel.expandedSections.contains("lambda"),
            profile: viewModel.selectedProfile
        ) { toggleSection("lambda") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            LambdaListView(
                functions: viewModel.lambdaFunctions,
                errorCounts: viewModel.lambdaErrorCounts,
                selectedFunction: $viewModel.selectedLambda
            )
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        InfraSection(
            id: "activity",
            title: "Recent Activity",
            count: viewModel.cloudTrailEvents.count,
            status: HealthStatus.unknown,
            isLoading: viewModel.isLoadingActivity,
            error: viewModel.activityError,
            isExpanded: viewModel.expandedSections.contains("activity"),
            profile: viewModel.selectedProfile
        ) { toggleSection("activity") } explainAction: { s in
            await viewModel.explainSection(s)
        } content: {
            CloudTrailView(events: viewModel.cloudTrailEvents)
        }
    }

    // MARK: - Cross-Account Body

    private var crossAccountBody: some View {
        VStack(spacing: 12) {
            if viewModel.isLoadingCrossAccount {
                VStack(spacing: 8) {
                    ProgressView()
                    if !viewModel.crossAccountProgress.isEmpty {
                        Text(viewModel.crossAccountProgress).font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else if viewModel.crossAccountResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.fill").font(.largeTitle).foregroundColor(.secondary)
                    Text("No AWS accounts mapped to this product.")
                    Button("Manage Accounts") { appState.showSettings = true }
                        .foregroundColor(.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else {
                crossAccountTable
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var crossAccountTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Aggregate summary
            let critical = viewModel.crossAccountResults.values.filter { $0.overallStatus == .critical }.count
            let warning = viewModel.crossAccountResults.values.filter { $0.overallStatus == .warning }.count
            if critical > 0 || warning > 0 {
                HStack(spacing: 6) {
                    if critical > 0 {
                        Label("\(critical) account\(critical == 1 ? "" : "s") critical", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red).font(.caption)
                    }
                    if warning > 0 {
                        Label("\(warning) account\(warning == 1 ? "" : "s") with warnings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow).font(.caption)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall).fill(Color(NSColor.controlBackgroundColor)))
            }

            // Column headers
            HStack(spacing: 0) {
                Text("Account").font(.caption.bold()).frame(width: 180, alignment: .leading)
                Spacer()
                Text("EC2").font(.caption.bold()).frame(width: 70, alignment: .center)
                Text("ASG").font(.caption.bold()).frame(width: 70, alignment: .center)
                Text("ALB").font(.caption.bold()).frame(width: 70, alignment: .center)
                Text("Alarms").font(.caption.bold()).frame(width: 70, alignment: .center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)

            let sortedSummaries = viewModel.crossAccountResults.values
                .sorted { $0.overallStatus.rawValue < $1.overallStatus.rawValue }
            ForEach(sortedSummaries, id: \.profile) { summary in
                CrossAccountRow(summary: summary) { profile in
                    viewModel.crossAccountMode = false
                    Task { await viewModel.refreshAll(profile: profile, region: nil) }
                }
            }
        }
    }

    // MARK: - AI Panel

    private func aiAnalysisPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI Analysis", systemImage: "sparkles").font(.caption.bold())
                Spacer()
                if viewModel.isAnalyzing { ProgressView().controlSize(.mini) }
                Button { viewModel.aiAnalysis = nil } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.purple.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.purple.opacity(0.3), lineWidth: 1)))
    }

    private func nlqAnswerPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(viewModel.naturalLanguageQuery, systemImage: "magnifyingglass")
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()
                Button { viewModel.nlqResult = nil; viewModel.naturalLanguageQuery = "" } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
            Text(text).font(.caption).textSelection(.enabled)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.blue.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.blue.opacity(0.2), lineWidth: 1)))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select an AWS account to view infrastructure health")
                .font(.headline)
                .foregroundColor(.secondary)
            if appState.favoriteAWSProfiles.isEmpty {
                Button("Add Accounts in Settings") { appState.showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func toggleSection(_ id: String) {
        if viewModel.expandedSections.contains(id) {
            viewModel.expandedSections.remove(id)
        } else {
            viewModel.expandedSections.insert(id)
        }
    }

    private func initialLoad() {
        let profile = filteredProfiles.first ?? appState.awsSSOProfile
        guard !profile.isEmpty else { return }
        Task { await viewModel.refreshAll(profile: profile, region: nil) }
    }
}

// MARK: - InfraSection

struct InfraSection<Content: View>: View {
    let id: String
    let title: String
    let count: Int
    let status: HealthStatus
    let isLoading: Bool
    let error: String?
    let isExpanded: Bool
    let profile: String
    let toggleAction: () -> Void
    let explainAction: (String) async -> String
    @ViewBuilder let content: Content

    @State private var explanation: String?
    @State private var isLoadingExplanation = false

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            Button(action: toggleAction) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: status.icon)
                        .foregroundColor(status.color)
                        .font(.caption)
                    Text(title)
                        .font(.subheadline.bold())
                    if isLoading {
                        ProgressView().controlSize(.mini).padding(.leading, 2)
                    } else {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                    }
                    Spacer()
                    if let err = error {
                        Label(err.prefix(50) + "…", systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                    // Explain button
                    Button {
                        Task {
                            isLoadingExplanation = true
                            explanation = await explainAction(title)
                            isLoadingExplanation = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            if isLoadingExplanation { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "questionmark.circle") }
                            Text("Explain").font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Explain this section to me (junior SRE mode)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if let exp = explanation {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.caption)
                            Text(exp).font(.caption).textSelection(.enabled)
                            Spacer()
                            Button { explanation = nil } label: { Image(systemName: "xmark").font(.caption2) }
                                .buttonStyle(.plain).foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.yellow.opacity(0.06))
                        Divider()
                    }
                    content
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color(NSColor.separatorColor), lineWidth: 1))
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: HealthStatus
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(status.color)
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: status.icon)
                            .font(.caption)
                            .foregroundColor(status.color)
                    }
                }
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                    .fill(status.color.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(status.color.opacity(0.2), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EC2 List

struct EC2ListView: View {
    let instances: [EC2Instance]
    @Binding var selectedInstance: EC2Instance?

    @State private var sortKey: EC2SortKey = .name
    @State private var sortAscending = true
    @State private var filterText = ""

    enum EC2SortKey { case name, type, state, az, launchTime }

    private var filtered: [EC2Instance] {
        let base = instances.filter { $0.state != "terminated" }
        let f = filterText.lowercased()
        let searched = f.isEmpty ? base : base.filter {
            $0.name.lowercased().contains(f) || $0.instanceId.lowercased().contains(f)
        }
        return searched.sorted { a, b in
            let result: Bool
            switch sortKey {
            case .name: result = a.name < b.name
            case .type: result = a.instanceType < b.instanceType
            case .state: result = a.state < b.state
            case .az: result = a.availabilityZone < b.availabilityZone
            case .launchTime: result = (a.launchTime ?? .distantPast) < (b.launchTime ?? .distantPast)
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                TextField("Filter by name or ID…", text: $filterText).font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Header
            HStack(spacing: 0) {
                SortHeader("Name", key: .name, current: $sortKey, asc: $sortAscending).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                SortHeader("Type", key: .type, current: $sortKey, asc: $sortAscending).frame(width: 100, alignment: .leading)
                SortHeader("State", key: .state, current: $sortKey, asc: $sortAscending).frame(width: 80, alignment: .leading)
                SortHeader("AZ", key: .az, current: $sortKey, asc: $sortAscending).frame(width: 110, alignment: .leading)
                Text("Private IP").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 110, alignment: .leading)
                SortHeader("Launched", key: .launchTime, current: $sortKey, asc: $sortAscending).frame(width: 120, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ForEach(filtered) { instance in
                EC2Row(instance: instance, isSelected: selectedInstance?.instanceId == instance.instanceId) {
                    selectedInstance = selectedInstance?.instanceId == instance.instanceId ? nil : instance
                }
                Divider()
            }

            if filtered.isEmpty {
                Text(filterText.isEmpty ? "No instances" : "No matches for '\(filterText)'")
                    .font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }
}

struct EC2Row: View {
    let instance: EC2Instance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 0) {
                    Text(instance.name)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                    Text(instance.instanceType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Label(instance.state, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(ec2StateColor(instance.state))
                        .frame(width: 80, alignment: .leading)
                    Text(instance.availabilityZone)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(instance.privateIpAddress.isEmpty ? "—" : instance.privateIpAddress)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(instance.launchTime.map { relativeTime($0) } ?? "—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Copy Instance ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(instance.instanceId, forType: .string) }
                Button("Open in AWS Console") {
                    let region = instance.region
                    let url = "https://\(region).console.aws.amazon.com/ec2/home?region=\(region)#InstanceDetails:instanceId=\(instance.instanceId)"
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
            }

            if isSelected {
                EC2DetailExpanded(instance: instance)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.05))
            }
        }
    }
}

struct EC2DetailExpanded: View {
    let instance: EC2Instance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailRow("Instance ID", instance.instanceId)
            DetailRow("VPC", instance.vpcId.isEmpty ? "—" : instance.vpcId)
            DetailRow("Subnet", instance.subnetId.isEmpty ? "—" : instance.subnetId)
            DetailRow("Platform", instance.platform)
            if !instance.publicIpAddress.isEmpty {
                DetailRow("Public IP", instance.publicIpAddress)
            }
            HStack(spacing: 8) {
                Button("Copy ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(instance.instanceId, forType: .string)
                }
                .font(.caption2)
                Button("Open Console") {
                    let r = instance.region
                    let url = "https://\(r).console.aws.amazon.com/ec2/home?region=\(r)#InstanceDetails:instanceId=\(instance.instanceId)"
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
                .font(.caption2)
            }
        }
        .font(.caption)
    }
}

// MARK: - ASG List

struct ASGListView: View {
    let groups: [ASGInfo]
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(groups) { asg in
                VStack(spacing: 0) {
                    Button { toggleExpand(asg.name) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: asg.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(asg.isHealthy ? .green : .red)
                                .font(.caption)
                            Text(asg.name)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(asg.runningCount)/\(asg.desiredCapacity)")
                                .font(.caption.monospaced())
                                .foregroundColor(asg.isHealthy ? .green : .red)
                            Text("min:\(asg.minSize) max:\(asg.maxSize)")
                                .font(.caption2).foregroundColor(.secondary)
                            Image(systemName: expanded.contains(asg.name) ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expanded.contains(asg.name) {
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow("Launch Template", asg.launchTemplateName.isEmpty ? "Launch Config" : asg.launchTemplateName)
                            DetailRow("AZs", asg.availabilityZones.joined(separator: ", "))
                            if !asg.targetGroupARNs.isEmpty {
                                DetailRow("Target Groups", "\(asg.targetGroupARNs.count) attached")
                            }
                            if asg.unhealthyCount > 0 {
                                Label("\(asg.unhealthyCount) unhealthy instance(s)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundColor(.red)
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                }
                Divider()
            }
            if groups.isEmpty {
                Text("No ASGs found").font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }

    private func toggleExpand(_ name: String) {
        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
    }
}

// MARK: - ALB List

struct ALBListView: View {
    let albs: [ALBInfo]
    let targetHealth: [String: [TargetHealthInfo]]
    let targetGroups: [String: [TargetGroupInfo]]
    let profile: String
    let region: String?
    let loadHealth: (String) -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(albs) { alb in
                VStack(spacing: 0) {
                    Button { toggle(alb.arn) } label: {
                        HStack(spacing: 8) {
                            let tgs = targetGroups[alb.arn] ?? []
                            let allTargets = tgs.flatMap { targetHealth[$0.arn] ?? [] }
                            let unhealthy = allTargets.filter { !$0.isHealthy }.count
                            Image(systemName: unhealthy > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(unhealthy > 0 ? .red : .green).font(.caption)
                            Text(alb.name).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(alb.scheme == "internet-facing" ? "Public" : "Internal")
                                .font(.caption2).foregroundColor(.secondary)
                            if !allTargets.isEmpty {
                                Text("\(allTargets.count - unhealthy)/\(allTargets.count)")
                                    .font(.caption.monospaced())
                                    .foregroundColor(unhealthy > 0 ? .red : .green)
                            }
                            Text(alb.state).font(.caption2).foregroundColor(alb.state == "active" ? .green : .orange)
                            Image(systemName: expanded.contains(alb.arn) ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expanded.contains(alb.arn) {
                        ALBDetailExpanded(alb: alb, targetGroups: targetGroups[alb.arn] ?? [], targetHealth: targetHealth, loadHealth: loadHealth)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                    }
                }
                Divider()
            }
            if albs.isEmpty {
                Text("No load balancers found").font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }

    private func toggle(_ arn: String) {
        if expanded.contains(arn) {
            expanded.remove(arn)
        } else {
            expanded.insert(arn)
            if targetGroups[arn] == nil { loadHealth(arn) }
        }
    }
}

struct ALBDetailExpanded: View {
    let alb: ALBInfo
    let targetGroups: [TargetGroupInfo]
    let targetHealth: [String: [TargetHealthInfo]]
    let loadHealth: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailRow("DNS", alb.dnsName)
            DetailRow("VPC", alb.vpcId.isEmpty ? "—" : alb.vpcId)
            DetailRow("AZs", alb.availabilityZones.joined(separator: ", "))
            if targetGroups.isEmpty {
                HStack { ProgressView().controlSize(.mini); Text("Loading target groups…").font(.caption2) }
            } else {
                ForEach(targetGroups) { tg in
                    let health = targetHealth[tg.arn] ?? []
                    let unhealthy = health.filter { !$0.isHealthy }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(tg.name).font(.caption.bold())
                            Spacer()
                            Text("\(health.count - unhealthy.count)/\(health.count) healthy")
                                .font(.caption2)
                                .foregroundColor(unhealthy.isEmpty ? .green : .red)
                        }
                        ForEach(unhealthy) { t in
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption2)
                                Text("\(t.targetId):\(t.port) — \(t.description)").font(.caption2).foregroundColor(.red)
                            }
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(unhealthy.isEmpty ? Color.green.opacity(0.06) : Color.red.opacity(0.06)))
                }
            }
            Button("Copy DNS") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(alb.dnsName, forType: .string) }
                .font(.caption2)
        }
    }
}

// MARK: - RDS List

struct RDSListView: View {
    let clusters: [AuroraCluster]
    let instances: [RDSInstance]
    @Binding var selectedCluster: AuroraCluster?
    @Binding var selectedInstance: RDSInstance?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(clusters) { cluster in
                VStack(spacing: 0) {
                    Button { selectedCluster = selectedCluster?.identifier == cluster.identifier ? nil : cluster } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cluster.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(rdsStatusColor(cluster.status)).font(.caption)
                            Text(cluster.identifier).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(cluster.engine).font(.caption2).foregroundColor(.secondary)
                            Text(cluster.status).font(.caption2).foregroundColor(rdsStatusColor(cluster.status))
                            Text("w:\(cluster.writerCount) r:\(cluster.readerCount)").font(.caption2).foregroundColor(.secondary)
                            if cluster.storageEncrypted {
                                Image(systemName: "lock.fill").font(.caption2).foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if selectedCluster?.identifier == cluster.identifier {
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow("Engine", "\(cluster.engine) \(cluster.engineVersion)")
                            DetailRow("Endpoint", cluster.endpoint)
                            if !cluster.readerEndpoint.isEmpty {
                                DetailRow("Reader", cluster.readerEndpoint)
                            }
                            DetailRow("Backup Retention", "\(cluster.backupRetentionPeriod) days")
                            if let t = cluster.latestRestorableTime {
                                DetailRow("Latest Restore", relativeTime(t))
                            }
                            DetailRow("AZs", cluster.availabilityZones.joined(separator: ", "))
                            HStack(spacing: 8) {
                                Button("Copy Endpoint") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cluster.endpoint, forType: .string) }.font(.caption2)
                            }
                        }
                        .padding(8).background(Color(NSColor.controlBackgroundColor))
                    }
                }
                Divider()
            }
            ForEach(instances) { instance in
                HStack(spacing: 8) {
                    Image(systemName: "cylinder").font(.caption).foregroundColor(.secondary)
                    Text(instance.identifier).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(instance.engine).font(.caption2).foregroundColor(.secondary)
                    Text(instance.status).font(.caption2).foregroundColor(rdsStatusColor(instance.status))
                    Text(instance.instanceClass).font(.caption2).foregroundColor(.secondary)
                    if instance.multiAZ {
                        Text("Multi-AZ").font(.caption2).foregroundColor(.green)
                    } else {
                        Text("Single-AZ").font(.caption2).foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                Divider()
            }
            if clusters.isEmpty && instances.isEmpty {
                Text("No databases found").font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }
}

// MARK: - Alarms List

struct AlarmsListView: View {
    let alarms: [CloudWatchAlarm]
    @Binding var selectedAlarm: CloudWatchAlarm?
    let triageAction: () -> Void

    private var firingAlarms: [CloudWatchAlarm] { alarms.filter { $0.stateValue == "ALARM" } }
    private var insufficientAlarms: [CloudWatchAlarm] { alarms.filter { $0.stateValue == "INSUFFICIENT_DATA" } }
    private var okAlarms: [CloudWatchAlarm] { alarms.filter { $0.stateValue == "OK" } }

    var body: some View {
        VStack(spacing: 0) {
            if !firingAlarms.isEmpty {
                HStack {
                    Text("ALARM (\(firingAlarms.count))").font(.caption.bold()).foregroundColor(.red)
                    Spacer()
                    Button("AI Triage", action: triageAction).font(.caption).foregroundColor(.accentColor)
                }
                .padding(.horizontal, 10).padding(.vertical, 6).background(Color.red.opacity(0.08))
                ForEach(firingAlarms) { alarm in
                    AlarmRow(alarm: alarm, isSelected: selectedAlarm?.alarmName == alarm.alarmName) {
                        selectedAlarm = selectedAlarm?.alarmName == alarm.alarmName ? nil : alarm
                    }
                    Divider()
                }
            }
            if !insufficientAlarms.isEmpty {
                Text("INSUFFICIENT DATA (\(insufficientAlarms.count))").font(.caption.bold()).foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Color.yellow.opacity(0.08))
                ForEach(insufficientAlarms) { alarm in
                    AlarmRow(alarm: alarm, isSelected: selectedAlarm?.alarmName == alarm.alarmName) {
                        selectedAlarm = selectedAlarm?.alarmName == alarm.alarmName ? nil : alarm
                    }
                    Divider()
                }
            }
            if !okAlarms.isEmpty {
                Text("OK (\(okAlarms.count))").font(.caption.bold()).foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Color.green.opacity(0.06))
                ForEach(okAlarms.prefix(10)) { alarm in
                    AlarmRow(alarm: alarm, isSelected: selectedAlarm?.alarmName == alarm.alarmName) {
                        selectedAlarm = selectedAlarm?.alarmName == alarm.alarmName ? nil : alarm
                    }
                    Divider()
                }
                if okAlarms.count > 10 {
                    Text("… \(okAlarms.count - 10) more OK alarms").font(.caption2).foregroundColor(.secondary).padding(8)
                }
            }
            if alarms.isEmpty {
                Text("No alarms found").font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }
}

struct AlarmRow: View {
    let alarm: CloudWatchAlarm
    let isSelected: Bool
    let action: () -> Void

    var color: Color {
        switch alarm.stateValue {
        case "ALARM": return .red
        case "INSUFFICIENT_DATA": return .yellow
        default: return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill").font(.caption2).foregroundColor(color)
                    Text(alarm.alarmName).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(alarm.metricName).font(.caption2).foregroundColor(.secondary)
                    if let ts = alarm.stateUpdatedTimestamp {
                        Text(relativeTime(ts)).font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow("Reason", alarm.stateReason)
                    DetailRow("Metric", "\(alarm.namespace)/\(alarm.metricName)")
                    DetailRow("Threshold", "\(alarm.comparisonOperator) \(alarm.threshold)")
                    DetailRow("Period", "\(alarm.evaluationPeriods) × \(alarm.period)s")
                    if !alarm.dimensions.isEmpty {
                        DetailRow("Dimensions", alarm.dimensions.map { "\($0.name)=\($0.value)" }.joined(separator: ", "))
                    }
                    if !alarm.alarmActions.isEmpty {
                        DetailRow("Actions", "\(alarm.alarmActions.count) configured")
                    }
                }
                .padding(8).background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
}

// MARK: - Lambda List

struct LambdaListView: View {
    let functions: [LambdaFunction]
    let errorCounts: [String: Int]
    @Binding var selectedFunction: LambdaFunction?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Function").font(.caption2.bold()).foregroundColor(.secondary).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                Text("Runtime").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                Text("Memory").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                Text("Timeout").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                Text("Errors 24h").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 4).background(Color(NSColor.controlBackgroundColor))
            Divider()
            ForEach(functions) { fn in
                let errors = errorCounts[fn.functionName] ?? 0
                VStack(spacing: 0) {
                    Button { selectedFunction = selectedFunction?.functionName == fn.functionName ? nil : fn } label: {
                        HStack(spacing: 0) {
                            Text(fn.functionName).font(.caption).lineLimit(1).frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                            Text(fn.runtime).font(.caption).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                            Text("\(fn.memorySize) MB").font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                            Text("\(fn.timeout)s").font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                            Text(errors == 0 ? "0" : "\(errors)")
                                .font(.caption.monospaced())
                                .foregroundColor(errors == 0 ? .green : errors < 10 ? .yellow : .red)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if selectedFunction?.functionName == fn.functionName {
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow("Handler", fn.handler)
                            DetailRow("Code Size", "\(fn.codeSize / 1024) KB")
                            DetailRow("State", fn.state)
                            DetailRow("Last Modified", fn.lastModified)
                            if !fn.description.isEmpty {
                                DetailRow("Description", fn.description)
                            }
                        }
                        .padding(8).background(Color(NSColor.controlBackgroundColor))
                    }
                }
                Divider()
            }
            if functions.isEmpty {
                Text("No Lambda functions found").font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }
}

// MARK: - CloudTrail

struct CloudTrailView: View {
    let events: [CloudTrailEvent]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                HStack(spacing: 8) {
                    Image(systemName: eventIcon(event))
                        .font(.caption2)
                        .foregroundColor(eventColor(event))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.eventName).font(.caption.bold()).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(event.eventSource).font(.caption2).foregroundColor(.secondary)
                            if !event.username.isEmpty {
                                Text("by \(event.username)").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if let t = event.eventTime {
                        Text(relativeTime(t)).font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                Divider()
            }
            if events.isEmpty {
                Text("No recent activity").font(.caption).foregroundColor(.secondary).padding(12)
            }
        }
    }

    private func eventIcon(_ e: CloudTrailEvent) -> String {
        if e.isDestructive { return "trash.fill" }
        if e.isModification { return "pencil.circle.fill" }
        return "eye.fill"
    }
    private func eventColor(_ e: CloudTrailEvent) -> Color {
        if e.isDestructive { return .red }
        if e.isModification { return .yellow }
        return .blue
    }
}

// MARK: - Cross-Account Row

struct CrossAccountRow: View {
    let summary: AccountHealthSummary
    let selectAccount: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { selectAccount(summary.profile) } label: {
                HStack(spacing: 6) {
                    Image(systemName: summary.overallStatus.icon)
                        .foregroundColor(summary.overallStatus.color).font(.caption)
                    Text(summary.profile).font(.caption).lineLimit(1)
                }
                .frame(width: 180, alignment: .leading)
            }
            .buttonStyle(.plain)
            Spacer()
            StatusCell(count: summary.ec2Count, status: summary.ec2Status).frame(width: 70)
            StatusCell(count: summary.asgCount, status: summary.asgStatus).frame(width: 70)
            StatusCell(count: summary.albCount, status: summary.albStatus).frame(width: 70)
            StatusCell(count: summary.firingAlarms, status: summary.firingAlarms > 0 ? .critical : .healthy).frame(width: 70)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(summary.overallStatus == .critical ? Color.red.opacity(0.05) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}

struct StatusCell: View {
    let count: Int
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(status.color)
            Text("\(count)").font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sort Header helper

struct SortHeader: View {
    let title: String
    let key: EC2ListView.EC2SortKey
    @Binding var current: EC2ListView.EC2SortKey
    @Binding var asc: Bool

    init(_ title: String, key: EC2ListView.EC2SortKey, current: Binding<EC2ListView.EC2SortKey>, asc: Binding<Bool>) {
        self.title = title
        self.key = key
        _current = current
        _asc = asc
    }

    var body: some View {
        Button {
            if current == key { asc.toggle() }
            else { current = key; asc = true }
        } label: {
            HStack(spacing: 2) {
                Text(title).font(.caption2.bold()).foregroundColor(.secondary)
                if current == key {
                    Image(systemName: asc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7)).foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared helpers

private func ec2StateColor(_ state: String) -> Color {
    switch state {
    case "running": return .green
    case "stopped": return .yellow
    case "terminated": return .red
    default: return .orange
    }
}

private func rdsStatusColor(_ status: String) -> Color {
    switch status {
    case "available": return .green
    case "backing-up", "modifying", "maintenance": return .yellow
    default: return .red
    }
}

private func relativeTime(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    if diff < 3600 { return "\(Int(diff / 60))m ago" }
    if diff < 86400 { return "\(Int(diff / 3600))h ago" }
    return "\(Int(diff / 86400))d ago"
}

private struct DetailRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":").font(.caption2).foregroundColor(.secondary).frame(width: 90, alignment: .trailing)
            Text(value).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

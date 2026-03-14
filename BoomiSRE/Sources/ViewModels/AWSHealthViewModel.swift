import Foundation
import SwiftUI

@MainActor
final class AWSHealthViewModel: ObservableObject {

    // MARK: - Selection
    @Published var selectedProfile: String = ""
    @Published var selectedRegion: String? = nil
    @Published var availableRegions: [String] = []

    // MARK: - Section Data
    @Published var ec2Instances: [EC2Instance] = []
    @Published var asgList: [ASGInfo] = []
    @Published var albList: [ALBInfo] = []
    @Published var targetHealthByGroup: [String: [TargetHealthInfo]] = [:]
    @Published var targetGroupsByALB: [String: [TargetGroupInfo]] = [:]
    @Published var rdsInstances: [RDSInstance] = []
    @Published var auroraClusters: [AuroraCluster] = []
    @Published var alarms: [CloudWatchAlarm] = []
    @Published var lambdaFunctions: [LambdaFunction] = []
    @Published var lambdaErrorCounts: [String: Int] = [:]
    @Published var cloudTrailEvents: [CloudTrailEvent] = []

    // MARK: - Loading States
    @Published var isLoadingEC2 = false
    @Published var isLoadingASG = false
    @Published var isLoadingALB = false
    @Published var isLoadingRDS = false
    @Published var isLoadingAlarms = false
    @Published var isLoadingLambda = false
    @Published var isLoadingActivity = false

    // MARK: - Error States
    @Published var ec2Error: String?
    @Published var asgError: String?
    @Published var albError: String?
    @Published var rdsError: String?
    @Published var alarmsError: String?
    @Published var lambdaError: String?
    @Published var activityError: String?

    // MARK: - AI Analysis
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?
    @Published var showAIPanel = false
    @Published var naturalLanguageQuery: String = ""
    @Published var nlqResult: String?
    @Published var isQueryingNLQ = false

    // MARK: - Session
    @Published var sessionExpired = false

    // MARK: - Cross-Account Mode
    @Published var crossAccountMode = false
    @Published var crossAccountResults: [String: AccountHealthSummary] = [:]
    @Published var crossAccountProgress: String = ""
    @Published var isLoadingCrossAccount = false

    // MARK: - Section Expand/Collapse
    @Published var expandedSections: Set<String> = ["alarms"]

    // MARK: - Selected Resource (for detail panel)
    @Published var selectedEC2: EC2Instance?
    @Published var selectedALB: ALBInfo?
    @Published var selectedRDS: RDSInstance?
    @Published var selectedCluster: AuroraCluster?
    @Published var selectedAlarm: CloudWatchAlarm?
    @Published var selectedLambda: LambdaFunction?

    private let claudeService = ClaudeService()

    // MARK: - Computed Health Properties

    var ec2HealthStatus: HealthStatus {
        if ec2Instances.isEmpty && !isLoadingEC2 { return .unknown }
        let impaired = ec2Instances.filter {
            $0.state != "running" && $0.state != "stopped" && $0.state != "terminated"
        }.count
        let stopped = ec2Instances.filter { $0.state == "stopped" }.count
        if impaired > 0 { return .critical }
        if stopped > 0 { return .warning }
        return .healthy
    }

    var asgHealthStatus: HealthStatus {
        if asgList.isEmpty && !isLoadingASG { return .unknown }
        if asgList.contains(where: { !$0.isHealthy }) { return .critical }
        return .healthy
    }

    var albHealthStatus: HealthStatus {
        if albList.isEmpty && !isLoadingALB { return .unknown }
        let allTargets = targetHealthByGroup.values.flatMap { $0 }
        let unhealthy = allTargets.filter { !$0.isHealthy }.count
        if unhealthy > 0 { return .critical }
        if albList.contains(where: { $0.state != "active" }) { return .warning }
        return .healthy
    }

    var rdsHealthStatus: HealthStatus {
        let allStatuses = rdsInstances.map(\.status) + auroraClusters.map(\.status)
        if allStatuses.isEmpty && !isLoadingRDS { return .unknown }
        if allStatuses.contains(where: { $0 != "available" && $0 != "backing-up" }) { return .critical }
        if allStatuses.contains(where: { $0 == "backing-up" || $0 == "maintenance" || $0 == "modifying" }) { return .warning }
        return .healthy
    }

    var alarmsHealthStatus: HealthStatus {
        if isLoadingAlarms { return .unknown }
        let firing = alarms.filter { $0.stateValue == "ALARM" }.count
        let insufficient = alarms.filter { $0.stateValue == "INSUFFICIENT_DATA" }.count
        if firing > 0 { return .critical }
        if insufficient > 0 { return .warning }
        return .healthy
    }

    var lambdaHealthStatus: HealthStatus {
        if isLoadingLambda { return .unknown }
        let total = lambdaErrorCounts.values.reduce(0, +)
        if total >= 10 { return .critical }
        if total > 0 { return .warning }
        return .healthy
    }

    var firingAlarmsCount: Int { alarms.filter { $0.stateValue == "ALARM" }.count }
    var totalLambdaErrors: Int { lambdaErrorCounts.values.reduce(0, +) }
    var unhealthyTargetsCount: Int { targetHealthByGroup.values.flatMap { $0 }.filter { !$0.isHealthy }.count }

    // MARK: - Region-filtered views

    var filteredEC2: [EC2Instance] {
        guard let r = selectedRegion else { return ec2Instances }
        return ec2Instances.filter { $0.region == r }
    }

    var filteredASG: [ASGInfo] {
        guard let r = selectedRegion else { return asgList }
        return asgList.filter { $0.availabilityZones.contains(where: { $0.hasPrefix(r) }) }
    }

    var filteredALB: [ALBInfo] {
        guard let r = selectedRegion else { return albList }
        return albList.filter { $0.availabilityZones.contains(where: { $0.hasPrefix(r) }) }
    }

    // MARK: - Refresh

    func refreshAll(profile: String, region: String?) async {
        selectedProfile = profile
        selectedRegion = region

        ec2Error = nil; asgError = nil; albError = nil; rdsError = nil
        alarmsError = nil; lambdaError = nil; activityError = nil

        await withTaskGroup(of: Void.self) { group in
            let p = profile
            let r = region
            group.addTask { @MainActor in await self.fetchEC2(profile: p, region: r) }
            group.addTask { @MainActor in await self.fetchASG(profile: p, region: r) }
            group.addTask { @MainActor in await self.fetchALB(profile: p, region: r) }
            group.addTask { @MainActor in await self.fetchRDS(profile: p, region: r) }
            group.addTask { @MainActor in await self.fetchAlarms(profile: p, region: r) }
            group.addTask { @MainActor in await self.fetchLambda(profile: p, region: r) }
            group.addTask { @MainActor in await self.fetchActivity(profile: p, region: r) }
        }

        updateAvailableRegions()
        autoExpandUnhealthy()
    }

    func loadTargetHealth(albArn: String, profile: String, region: String?) async {
        let service = AWSInfraService()
        let tgs = (try? await service.describeTargetGroups(profile: profile, loadBalancerArn: albArn, region: region)) ?? []
        targetGroupsByALB[albArn] = tgs
        for tg in tgs {
            let health = (try? await service.describeTargetHealth(profile: profile, targetGroupArn: tg.arn, region: region)) ?? []
            targetHealthByGroup[tg.arn] = health
        }
    }

    // MARK: - Cross-Account

    func fetchCrossAccount(profiles: [String], region: String?) async {
        isLoadingCrossAccount = true
        crossAccountResults = [:]
        crossAccountProgress = ""

        let batches = stride(from: 0, to: profiles.count, by: 3).map {
            Array(profiles[$0..<min($0 + 3, profiles.count)])
        }

        for (batchIdx, batch) in batches.enumerated() {
            await withTaskGroup(of: (String, AccountHealthSummary).self) { group in
                for profile in batch {
                    let p = profile
                    let r = region
                    let batchNum = batchIdx
                    let total = profiles.count
                    group.addTask { @MainActor in
                        self.crossAccountProgress = "Checking \(p) (\(batchNum * 3 + 1) of \(total))..."
                        let summary = await self.fetchAccountSummary(profile: p, region: r)
                        return (p, summary)
                    }
                }
                for await (profile, summary) in group {
                    crossAccountResults[profile] = summary
                }
            }
        }

        isLoadingCrossAccount = false
        crossAccountProgress = ""
    }

    private func fetchAccountSummary(profile: String, region: String?) async -> AccountHealthSummary {
        let service = AWSInfraService()
        async let ec2 = (try? await service.describeInstances(profile: profile, region: region)) ?? []
        async let asg = (try? await service.describeAutoScalingGroups(profile: profile, region: region)) ?? []
        async let alb = (try? await service.describeLoadBalancers(profile: profile, region: region)) ?? []
        async let alarms = (try? await service.describeAlarms(profile: profile, region: region, stateValue: "ALARM")) ?? []
        let (ec2r, asgr, albr, alarmsr) = await (ec2, asg, alb, alarms)

        return AccountHealthSummary(
            profile: profile,
            ec2Count: ec2r.filter { $0.isRunning }.count,
            ec2Status: ec2r.contains(where: { !$0.isRunning && $0.state != "stopped" && $0.state != "terminated" })
                ? .critical : (ec2r.contains(where: { $0.state == "stopped" }) ? .warning : .healthy),
            asgCount: asgr.count,
            asgStatus: asgr.contains(where: { !$0.isHealthy }) ? .critical : .healthy,
            albCount: albr.count,
            albStatus: albr.contains(where: { $0.state != "active" }) ? .critical : .healthy,
            firingAlarms: alarmsr.count
        )
    }

    // MARK: - AI Analysis

    func analyzeInfrastructure() async {
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."
            return
        }
        isAnalyzing = true
        aiError = nil
        aiAnalysis = nil
        showAIPanel = true

        let context = buildInfraContext()
        do {
            aiAnalysis = try await claudeService.chat(
                messages: [("user", "Analyze this AWS infrastructure health data for Boomi's SRE team:\n\n\(context)")],
                systemPrompt: """
                You are an expert AWS SRE. Analyze the infrastructure data and provide:
                1. **Health Assessment** (Healthy/Warning/Critical) with a one-sentence reason
                2. **Issues Found** — specific problems needing attention (bullet list)
                3. **Recommendations** — 3–5 actionable optimization suggestions
                4. **Risk Assessment** — potential issues not yet problems (single-AZ resources, missing alarms, etc.)

                Be specific and concise. Use markdown formatting.
                """,
                maxTokens: 1024
            )
        } catch {
            aiError = error.localizedDescription
        }
        isAnalyzing = false
    }

    func explainSection(_ section: String) async -> String {
        guard claudeService.discoverAPIKey() != nil else {
            return "No Anthropic API key configured."
        }
        let prompt = """
        Explain \(section) in AWS to a junior SRE. Cover:
        - What these resources are
        - Why they matter for reliability
        - What to look for when something is unhealthy
        - Common gotchas

        Be encouraging and educational. Keep it under 200 words.
        """
        do {
            return try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are a senior SRE teaching a junior engineer. Be clear, encouraging, and practical.",
                maxTokens: 512
            )
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func analyzeAlarms() async -> String {
        let firingAlarms = alarms.filter { $0.stateValue == "ALARM" }
        guard !firingAlarms.isEmpty else { return "No active alarms to analyze." }
        guard claudeService.discoverAPIKey() != nil else { return "No Anthropic API key configured." }
        let alarmList = firingAlarms.map { "- \($0.alarmName): \($0.stateReason)" }.joined(separator: "\n")
        let prompt = """
        Active CloudWatch Alarms:
        \(alarmList)

        Provide:
        1. Which alarms are most urgent?
        2. Are any likely related (same root cause)?
        3. Estimated blast radius?
        4. Suggested investigation steps for each alarm.
        """
        do {
            return try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an AWS operations expert helping triage active alarms.",
                maxTokens: 1024
            )
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func submitNLQuery() async {
        let trimmed = naturalLanguageQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, claudeService.discoverAPIKey() != nil else { return }
        isQueryingNLQ = true
        nlqResult = nil
        let query = naturalLanguageQuery
        let context = buildInfraContext()
        do {
            nlqResult = try await claudeService.chat(
                messages: [("user", "Infrastructure data:\n\(context)\n\nQuestion: \(query)")],
                systemPrompt: "You are an AWS SRE assistant. Answer questions about the infrastructure data concisely using bullet points. If data is missing, say so.",
                maxTokens: 512
            )
        } catch {
            nlqResult = "Error: \(error.localizedDescription)"
        }
        isQueryingNLQ = false
    }

    // MARK: - Private fetch helpers

    private func fetchEC2(profile: String, region: String?) async {
        isLoadingEC2 = true
        do {
            ec2Instances = try await AWSInfraService().describeInstances(profile: profile, region: region)
        } catch {
            ec2Error = error.localizedDescription
        }
        isLoadingEC2 = false
    }

    private func fetchASG(profile: String, region: String?) async {
        isLoadingASG = true
        do {
            asgList = try await AWSInfraService().describeAutoScalingGroups(profile: profile, region: region)
        } catch {
            asgError = error.localizedDescription
        }
        isLoadingASG = false
    }

    private func fetchALB(profile: String, region: String?) async {
        isLoadingALB = true
        do {
            albList = try await AWSInfraService().describeLoadBalancers(profile: profile, region: region)
        } catch {
            albError = error.localizedDescription
        }
        isLoadingALB = false
    }

    private func fetchRDS(profile: String, region: String?) async {
        isLoadingRDS = true
        do {
            async let instances = AWSInfraService().describeDBInstances(profile: profile, region: region)
            async let clusters = AWSInfraService().describeDBClusters(profile: profile, region: region)
            rdsInstances = (try? await instances) ?? []
            auroraClusters = (try? await clusters) ?? []
        } catch {
            rdsError = error.localizedDescription
        }
        isLoadingRDS = false
    }

    private func fetchAlarms(profile: String, region: String?) async {
        isLoadingAlarms = true
        do {
            alarms = try await AWSInfraService().describeAlarms(profile: profile, region: region)
        } catch {
            alarmsError = error.localizedDescription
        }
        isLoadingAlarms = false
    }

    private func fetchLambda(profile: String, region: String?) async {
        isLoadingLambda = true
        do {
            let functions = try await AWSInfraService().listFunctions(profile: profile, region: region)
            lambdaFunctions = functions
            for fn in functions.prefix(10) {
                let errors = (try? await AWSInfraService().getLambdaErrors(
                    profile: profile,
                    functionName: fn.functionName,
                    region: region
                )) ?? []
                let total = Int(errors.reduce(0.0) { $0 + $1.sum })
                if total > 0 { lambdaErrorCounts[fn.functionName] = total }
            }
        } catch {
            lambdaError = error.localizedDescription
        }
        isLoadingLambda = false
    }

    private func fetchActivity(profile: String, region: String?) async {
        isLoadingActivity = true
        do {
            cloudTrailEvents = try await AWSInfraService().lookupEvents(profile: profile, region: region)
        } catch {
            activityError = error.localizedDescription
        }
        isLoadingActivity = false
    }

    private func updateAvailableRegions() {
        var regions = Set<String>()
        ec2Instances.forEach { regions.insert($0.region) }
        asgList.forEach { asg in
            asg.availabilityZones.forEach { az in
                guard az.count > 1 else { return }
                regions.insert(String(az.dropLast()))
            }
        }
        albList.forEach { alb in
            alb.availabilityZones.forEach { az in
                guard az.count > 1 else { return }
                regions.insert(String(az.dropLast()))
            }
        }
        availableRegions = regions.sorted()
    }

    private func autoExpandUnhealthy() {
        if firingAlarmsCount > 0 { expandedSections.insert("alarms") }
        if asgHealthStatus == .critical { expandedSections.insert("asg") }
        if albHealthStatus == .critical { expandedSections.insert("alb") }
        if rdsHealthStatus == .critical { expandedSections.insert("rds") }
        if ec2HealthStatus == .critical { expandedSections.insert("ec2") }
    }

    private func buildInfraContext() -> String {
        let stoppedCount = ec2Instances.filter { $0.state == "stopped" }.count
        var parts: [String] = []
        parts.append("EC2: \(ec2Instances.filter { $0.isRunning }.count) running, \(stoppedCount) stopped")
        parts.append("ASGs: \(asgList.count) total, \(asgList.filter { !$0.isHealthy }.count) unhealthy")
        parts.append("ALBs: \(albList.count) total, \(unhealthyTargetsCount) unhealthy targets")
        parts.append("RDS: \(rdsInstances.count) instances, \(auroraClusters.count) Aurora clusters")
        let firing = alarms.filter { $0.stateValue == "ALARM" }
        if !firing.isEmpty {
            parts.append("FIRING ALARMS: \(firing.map(\.alarmName).joined(separator: ", "))")
        }
        parts.append("Lambda: \(lambdaFunctions.count) functions, \(totalLambdaErrors) errors (24h)")
        return parts.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

enum HealthStatus: String {
    case healthy = "Healthy"
    case warning = "Warning"
    case critical = "Critical"
    case unknown = "Unknown"

    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct AccountHealthSummary: Sendable {
    let profile: String
    let ec2Count: Int
    let ec2Status: HealthStatus
    let asgCount: Int
    let asgStatus: HealthStatus
    let albCount: Int
    let albStatus: HealthStatus
    let firingAlarms: Int

    var overallStatus: HealthStatus {
        if [ec2Status, asgStatus, albStatus].contains(.critical) || firingAlarms > 0 { return .critical }
        if [ec2Status, asgStatus, albStatus].contains(.warning) { return .warning }
        return .healthy
    }
}

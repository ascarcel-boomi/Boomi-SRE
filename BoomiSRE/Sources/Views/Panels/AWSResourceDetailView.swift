import SwiftUI
import Charts

// MARK: - Resource Detail View

/// Slide-over panel showing detailed metrics and config for a specific AWS resource.
struct AWSResourceDetailView: View {
    enum Resource {
        case ec2(EC2Instance)
        case alb(ALBInfo)
        case rdsCluster(AuroraCluster)
        case rdsInstance(RDSInstance)
        case lambda(LambdaFunction)
        case alarm(CloudWatchAlarm)
    }

    let resource: Resource
    let profile: String
    let region: String?
    let onDismiss: () -> Void

    @StateObject private var vm = AWSResourceDetailViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: resourceIcon)
                    .foregroundColor(Color.accentColor)
                Text(resourceTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if vm.isAnalyzing {
                    ProgressView().controlSize(.mini)
                }
                Button("Analyze with AI") { Task { await vm.analyzeResource(resource: resource, profile: profile, region: region) } }
                    .font(.caption)
                    .disabled(vm.isAnalyzing)
                Button { onDismiss() } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis = vm.aiAnalysis {
                        aiPanel(analysis)
                    }
                    resourceContent
                }
                .padding(12)
            }
        }
        .onAppear {
            Task { await vm.loadDetail(resource: resource, profile: profile, region: region) }
        }
    }

    // MARK: - Resource-specific content

    @ViewBuilder
    private var resourceContent: some View {
        switch resource {
        case .ec2(let instance):
            EC2DetailPanel(instance: instance, status: vm.ec2Status, metrics: vm.metrics)
        case .alb(let alb):
            ALBDetailPanel(alb: alb, targetGroups: vm.targetGroups, targetHealth: vm.targetHealth, metrics: vm.metrics)
        case .rdsCluster(let cluster):
            RDSClusterDetailPanel(cluster: cluster, metrics: vm.metrics)
        case .rdsInstance(let instance):
            RDSInstanceDetailPanel(instance: instance, metrics: vm.metrics)
        case .lambda(let fn):
            LambdaDetailPanel(function: fn, metrics: vm.metrics)
        case .alarm(let alarm):
            AlarmDetailPanel(alarm: alarm, history: vm.alarmHistory)
        }
    }

    private var resourceTitle: String {
        switch resource {
        case .ec2(let i): return i.name
        case .alb(let a): return a.name
        case .rdsCluster(let c): return c.identifier
        case .rdsInstance(let i): return i.identifier
        case .lambda(let f): return f.functionName
        case .alarm(let a): return a.alarmName
        }
    }

    private var resourceIcon: String {
        switch resource {
        case .ec2: return "server.rack"
        case .alb: return "network"
        case .rdsCluster, .rdsInstance: return "cylinder.split.1x2"
        case .lambda: return "function"
        case .alarm: return "bell.badge"
        }
    }

    private func aiPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AI Analysis", systemImage: "sparkles").font(.caption.bold())
            Text(text).font(.caption).textSelection(.enabled)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.purple.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.purple.opacity(0.3), lineWidth: 1)))
    }
}

// MARK: - ViewModel

@MainActor
final class AWSResourceDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var ec2Status: EC2InstanceStatus?
    @Published var targetGroups: [TargetGroupInfo] = []
    @Published var targetHealth: [String: [TargetHealthInfo]] = [:]
    @Published var alarmHistory: [AlarmHistoryItem] = []
    @Published var metrics: [String: [MetricDataPoint]] = [:]
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false

    private let claudeService = ClaudeService()

    func loadDetail(resource: AWSResourceDetailView.Resource, profile: String, region: String?) async {
        isLoading = true
        switch resource {
        case .ec2(let i):      await loadEC2Detail(instance: i, profile: profile, region: region)
        case .alb(let a):     await loadALBDetail(alb: a, profile: profile, region: region)
        case .rdsCluster(let c): await loadRDSClusterDetail(cluster: c, profile: profile, region: region)
        case .rdsInstance(let i): await loadRDSInstanceDetail(instance: i, profile: profile, region: region)
        case .lambda(let f):  await loadLambdaDetail(function: f, profile: profile, region: region)
        case .alarm(let a):   await loadAlarmDetail(alarm: a, profile: profile, region: region)
        }
        isLoading = false
    }

    // MARK: EC2

    private func loadEC2Detail(instance: EC2Instance, profile: String, region: String?) async {
        let svc = AWSInfraService()
        ec2Status = try? await svc.describeInstanceStatus(profile: profile, instanceId: instance.instanceId, region: region)
        let now = Date(); let start = now.addingTimeInterval(-6 * 3600)
        await withTaskGroup(of: (String, [MetricDataPoint]).self) { group in
            for metric in ["CPUUtilization", "NetworkIn", "NetworkOut", "StatusCheckFailed"] {
                group.addTask {
                    let msvc = AWSInfraService()
                    let pts = (try? await msvc.getMetricStatistics(
                        profile: profile,
                        namespace: "AWS/EC2", metricName: metric,
                        dimensionName: "InstanceId", dimensionValue: instance.instanceId,
                        startTime: start, endTime: now,
                        period: 300,
                        statistics: metric == "CPUUtilization" ? ["Average"] : ["Sum"],
                        region: region
                    )) ?? []
                    return (metric, pts)
                }
            }
            for await (name, pts) in group { metrics[name] = pts }
        }
    }

    // MARK: ALB

    private func loadALBDetail(alb: ALBInfo, profile: String, region: String?) async {
        let svc = AWSInfraService()
        let tgs = (try? await svc.describeTargetGroups(profile: profile, loadBalancerArn: alb.arn, region: region)) ?? []
        targetGroups = tgs
        for tg in tgs {
            let health = (try? await svc.describeTargetHealth(profile: profile, targetGroupArn: tg.arn, region: region)) ?? []
            targetHealth[tg.arn] = health
        }
        // CloudWatch metrics for ALB
        // Use load balancer name-based dimension
        let albDim = alb.arn.components(separatedBy: ":loadbalancer/").last ?? alb.name
        let now = Date(); let start = now.addingTimeInterval(-6 * 3600)
        await withTaskGroup(of: (String, [MetricDataPoint]).self) { group in
            for metric in ["RequestCount", "HTTPCode_Target_5XX_Count", "TargetResponseTime"] {
                group.addTask {
                    let msvc = AWSInfraService()
                    let pts = (try? await msvc.getMetricStatistics(
                        profile: profile,
                        namespace: "AWS/ApplicationELB", metricName: metric,
                        dimensionName: "LoadBalancer", dimensionValue: albDim,
                        startTime: start, endTime: now, period: 300,
                        statistics: metric == "TargetResponseTime" ? ["Average"] : ["Sum"],
                        region: region
                    )) ?? []
                    return (metric, pts)
                }
            }
            for await (name, pts) in group { metrics[name] = pts }
        }
    }

    // MARK: RDS Cluster

    private func loadRDSClusterDetail(cluster: AuroraCluster, profile: String, region: String?) async {
        let now = Date(); let start = now.addingTimeInterval(-6 * 3600)
        await withTaskGroup(of: (String, [MetricDataPoint]).self) { group in
            for metric in ["CPUUtilization", "FreeableMemory", "ReadIOPS", "WriteIOPS", "DatabaseConnections"] {
                group.addTask {
                    let svc = AWSInfraService()
                    let pts = (try? await svc.getMetricStatistics(
                        profile: profile,
                        namespace: "AWS/RDS", metricName: metric,
                        dimensionName: "DBClusterIdentifier", dimensionValue: cluster.identifier,
                        startTime: start, endTime: now, period: 300,
                        statistics: metric == "CPUUtilization" || metric == "FreeableMemory" || metric == "DatabaseConnections" ? ["Average"] : ["Sum"],
                        region: region
                    )) ?? []
                    return (metric, pts)
                }
            }
            for await (name, pts) in group { metrics[name] = pts }
        }
    }

    // MARK: RDS Instance

    private func loadRDSInstanceDetail(instance: RDSInstance, profile: String, region: String?) async {
        let now = Date(); let start = now.addingTimeInterval(-6 * 3600)
        await withTaskGroup(of: (String, [MetricDataPoint]).self) { group in
            for metric in ["CPUUtilization", "FreeableMemory", "ReadIOPS", "WriteIOPS", "DatabaseConnections"] {
                group.addTask {
                    let svc = AWSInfraService()
                    let pts = (try? await svc.getMetricStatistics(
                        profile: profile,
                        namespace: "AWS/RDS", metricName: metric,
                        dimensionName: "DBInstanceIdentifier", dimensionValue: instance.identifier,
                        startTime: start, endTime: now, period: 300,
                        statistics: ["Average"],
                        region: region
                    )) ?? []
                    return (metric, pts)
                }
            }
            for await (name, pts) in group { metrics[name] = pts }
        }
    }

    // MARK: Lambda

    private func loadLambdaDetail(function fn: LambdaFunction, profile: String, region: String?) async {
        let now = Date(); let start = now.addingTimeInterval(-24 * 3600)
        await withTaskGroup(of: (String, [MetricDataPoint]).self) { group in
            for metric in ["Invocations", "Errors", "Duration", "Throttles"] {
                group.addTask {
                    let svc = AWSInfraService()
                    let pts = (try? await svc.getMetricStatistics(
                        profile: profile,
                        namespace: "AWS/Lambda", metricName: metric,
                        dimensionName: "FunctionName", dimensionValue: fn.functionName,
                        startTime: start, endTime: now, period: 3600,
                        statistics: metric == "Duration" ? ["Average"] : ["Sum"],
                        region: region
                    )) ?? []
                    return (metric, pts)
                }
            }
            for await (name, pts) in group { metrics[name] = pts }
        }
    }

    // MARK: Alarm

    private func loadAlarmDetail(alarm: CloudWatchAlarm, profile: String, region: String?) async {
        let svc = AWSInfraService()
        alarmHistory = (try? await svc.describeAlarmHistory(profile: profile, alarmName: alarm.alarmName, region: region)) ?? []
    }

    // MARK: AI Analysis

    func analyzeResource(resource: AWSResourceDetailView.Resource, profile: String, region: String?) async {
        guard claudeService.isAIAvailable else { return }
        isAnalyzing = true
        aiAnalysis = nil

        let context = buildResourceContext(resource: resource)
        let prompt = """
        Analyze this AWS resource for Boomi's SRE team:

        \(context)

        Provide:
        1. **Health Assessment**: Is this resource healthy? Why or why not?
        2. **Right-Sizing**: Is it over/under-provisioned based on the metrics?
        3. **Risks**: Single AZ? No backups? Stale config? Missing alarms?
        4. **Next Steps**: What should an SRE check next?

        Be specific and concise (under 300 words).
        """
        do {
            aiAnalysis = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an AWS infrastructure reliability expert. Be specific and actionable.",
                maxTokens: 1024
            )
        } catch {
            aiAnalysis = "Error: \(error.localizedDescription)"
        }
        isAnalyzing = false
    }

    private func buildResourceContext(resource: AWSResourceDetailView.Resource) -> String {
        switch resource {
        case .ec2(let i):
            var lines = ["EC2 Instance: \(i.name) (\(i.instanceId))", "Type: \(i.instanceType)", "State: \(i.state)", "AZ: \(i.availabilityZone)", "Platform: \(i.platform)"]
            if let s = ec2Status { lines += ["System Status: \(s.systemStatus)", "Instance Status: \(s.instanceStatus)"] }
            if let cpu = metrics["CPUUtilization"]?.last { lines.append("CPU (latest): \(String(format: "%.1f", cpu.sum))%") }
            return lines.joined(separator: "\n")
        case .alb(let a):
            var lines = ["ALB: \(a.name)", "Scheme: \(a.scheme)", "State: \(a.state)", "AZs: \(a.availabilityZones.joined(separator: ", "))"]
            let allTargets = targetHealth.values.flatMap { $0 }
            let unhealthy = allTargets.filter { !$0.isHealthy }.count
            lines.append("Targets: \(allTargets.count - unhealthy)/\(allTargets.count) healthy")
            if let errors = metrics["HTTPCode_Target_5XX_Count"]?.reduce(0, { $0 + $1.sum }) {
                lines.append("5xx errors (6h): \(Int(errors))")
            }
            return lines.joined(separator: "\n")
        case .rdsCluster(let c):
            return ["Aurora Cluster: \(c.identifier)", "Engine: \(c.engine) \(c.engineVersion)", "Status: \(c.status)", "Members: \(c.writerCount)w / \(c.readerCount)r", "Encrypted: \(c.storageEncrypted)", "AZs: \(c.availabilityZones.joined(separator: ", "))"].joined(separator: "\n")
        case .rdsInstance(let i):
            return ["RDS Instance: \(i.identifier)", "Engine: \(i.engine) \(i.engineVersion)", "Class: \(i.instanceClass)", "Status: \(i.status)", "Multi-AZ: \(i.multiAZ)", "Storage: \(i.allocatedStorage)GB \(i.storageType)"].joined(separator: "\n")
        case .lambda(let f):
            let totalErrors = metrics["Errors"]?.reduce(0, { $0 + $1.sum }) ?? 0
            let totalInvocations = metrics["Invocations"]?.reduce(0, { $0 + $1.sum }) ?? 0
            return ["Lambda: \(f.functionName)", "Runtime: \(f.runtime)", "Memory: \(f.memorySize)MB", "Timeout: \(f.timeout)s", "Invocations (24h): \(Int(totalInvocations))", "Errors (24h): \(Int(totalErrors))"].joined(separator: "\n")
        case .alarm(let a):
            return ["Alarm: \(a.alarmName)", "State: \(a.stateValue)", "Metric: \(a.namespace)/\(a.metricName)", "Threshold: \(a.comparisonOperator) \(a.threshold)", "Reason: \(a.stateReason.prefix(200))"].joined(separator: "\n")
        }
    }
}

// MARK: - EC2 Detail Panel

struct EC2DetailPanel: View {
    let instance: EC2Instance
    let status: EC2InstanceStatus?
    let metrics: [String: [MetricDataPoint]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection("Instance Details") {
                DetailRow2("Instance ID", instance.instanceId, copyable: true)
                DetailRow2("Type", instance.instanceType)
                DetailRow2("State", instance.state)
                DetailRow2("AZ", instance.availabilityZone)
                DetailRow2("Platform", instance.platform)
                DetailRow2("Private IP", instance.privateIpAddress, copyable: true)
                if !instance.publicIpAddress.isEmpty {
                    DetailRow2("Public IP", instance.publicIpAddress, copyable: true)
                }
                DetailRow2("VPC", instance.vpcId)
                DetailRow2("Subnet", instance.subnetId)
            }
            if let s = status {
                DetailSection("Status Checks") {
                    StatusCheckRow("System Status", s.systemStatus)
                    StatusCheckRow("Instance Status", s.instanceStatus)
                }
            }
            if !metrics.isEmpty {
                DetailSection("CloudWatch Metrics (6h)") {
                    ForEach(["CPUUtilization", "NetworkIn", "NetworkOut", "StatusCheckFailed"], id: \.self) { metricName in
                        if let pts = metrics[metricName], !pts.isEmpty {
                            SparklineChart(title: metricName, points: pts, color: metricColor(metricName))
                        }
                    }
                }
            }
            consoleButton("ec2", region: instance.region, resourceId: instance.instanceId)
        }
    }
}

// MARK: - ALB Detail Panel

struct ALBDetailPanel: View {
    let alb: ALBInfo
    let targetGroups: [TargetGroupInfo]
    let targetHealth: [String: [TargetHealthInfo]]
    let metrics: [String: [MetricDataPoint]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection("Load Balancer Details") {
                DetailRow2("Name", alb.name)
                DetailRow2("DNS", alb.dnsName, copyable: true)
                DetailRow2("Scheme", alb.scheme)
                DetailRow2("State", alb.state)
                DetailRow2("Type", alb.type)
                DetailRow2("VPC", alb.vpcId)
                DetailRow2("AZs", alb.availabilityZones.joined(separator: ", "))
            }
            if !targetGroups.isEmpty {
                DetailSection("Target Groups") {
                    ForEach(targetGroups) { tg in
                        let health = targetHealth[tg.arn] ?? []
                        let unhealthy = health.filter { !$0.isHealthy }
                        VStack(alignment: .leading, spacing: 4) {
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
                                    Text("\(t.targetId) — \(t.description)").font(.caption2).foregroundColor(.red)
                                }
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(unhealthy.isEmpty ? Color.green.opacity(0.06) : Color.red.opacity(0.06)))
                    }
                }
            }
            if !metrics.isEmpty {
                DetailSection("CloudWatch Metrics (6h)") {
                    ForEach(["RequestCount", "HTTPCode_Target_5XX_Count", "TargetResponseTime"], id: \.self) { name in
                        if let pts = metrics[name], !pts.isEmpty {
                            SparklineChart(title: name, points: pts, color: name.contains("5XX") ? .red : .blue)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - RDS Cluster Detail Panel

struct RDSClusterDetailPanel: View {
    let cluster: AuroraCluster
    let metrics: [String: [MetricDataPoint]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection("Cluster Details") {
                DetailRow2("Identifier", cluster.identifier)
                DetailRow2("Engine", "\(cluster.engine) \(cluster.engineVersion)")
                DetailRow2("Status", cluster.status)
                DetailRow2("Members", "\(cluster.writerCount)w / \(cluster.readerCount)r")
                DetailRow2("Endpoint", cluster.endpoint, copyable: true)
                if !cluster.readerEndpoint.isEmpty {
                    DetailRow2("Reader Endpoint", cluster.readerEndpoint, copyable: true)
                }
                DetailRow2("Backup Retention", "\(cluster.backupRetentionPeriod) days")
                DetailRow2("Encrypted", cluster.storageEncrypted ? "Yes" : "No")
                DetailRow2("AZs", cluster.availabilityZones.joined(separator: ", "))
                if let t = cluster.latestRestorableTime {
                    DetailRow2("Latest Restore", relativeTimestamp(t))
                }
            }
            if !metrics.isEmpty {
                DetailSection("CloudWatch Metrics (6h)") {
                    ForEach(["CPUUtilization", "FreeableMemory", "ReadIOPS", "WriteIOPS", "DatabaseConnections"], id: \.self) { name in
                        if let pts = metrics[name], !pts.isEmpty {
                            SparklineChart(title: name, points: pts, color: metricColor(name))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - RDS Instance Detail Panel

struct RDSInstanceDetailPanel: View {
    let instance: RDSInstance
    let metrics: [String: [MetricDataPoint]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection("Instance Details") {
                DetailRow2("Identifier", instance.identifier)
                DetailRow2("Engine", "\(instance.engine) \(instance.engineVersion)")
                DetailRow2("Class", instance.instanceClass)
                DetailRow2("Status", instance.status)
                DetailRow2("Multi-AZ", instance.multiAZ ? "Yes" : "No")
                DetailRow2("Storage", "\(instance.allocatedStorage)GB \(instance.storageType)")
                DetailRow2("Endpoint", instance.endpoint, copyable: true)
                DetailRow2("AZ", instance.availabilityZone)
            }
            if !metrics.isEmpty {
                DetailSection("CloudWatch Metrics (6h)") {
                    ForEach(["CPUUtilization", "FreeableMemory", "ReadIOPS", "WriteIOPS", "DatabaseConnections"], id: \.self) { name in
                        if let pts = metrics[name], !pts.isEmpty {
                            SparklineChart(title: name, points: pts, color: metricColor(name))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Lambda Detail Panel

struct LambdaDetailPanel: View {
    let function: LambdaFunction
    let metrics: [String: [MetricDataPoint]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection("Function Details") {
                DetailRow2("Name", function.functionName)
                DetailRow2("Runtime", function.runtime)
                DetailRow2("Handler", function.handler)
                DetailRow2("Memory", "\(function.memorySize) MB")
                DetailRow2("Timeout", "\(function.timeout)s")
                DetailRow2("Code Size", "\(function.codeSize / 1024) KB")
                DetailRow2("State", function.state)
                DetailRow2("Last Modified", function.lastModified)
                if !function.description.isEmpty {
                    DetailRow2("Description", function.description)
                }
            }
            if !metrics.isEmpty {
                DetailSection("CloudWatch Metrics (24h)") {
                    ForEach(["Invocations", "Errors", "Duration", "Throttles"], id: \.self) { name in
                        if let pts = metrics[name], !pts.isEmpty {
                            SparklineChart(title: name, points: pts, color: name == "Errors" ? .red : name == "Throttles" ? .yellow : .blue)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Alarm Detail Panel

struct AlarmDetailPanel: View {
    let alarm: CloudWatchAlarm
    let history: [AlarmHistoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection("Alarm Configuration") {
                DetailRow2("Name", alarm.alarmName)
                DetailRow2("State", alarm.stateValue)
                DetailRow2("Metric", "\(alarm.namespace)/\(alarm.metricName)")
                DetailRow2("Threshold", "\(alarm.comparisonOperator) \(alarm.threshold)")
                DetailRow2("Evaluation", "\(alarm.evaluationPeriods) × \(alarm.period)s (\(alarm.statistic))")
                DetailRow2("Actions Enabled", alarm.actionsEnabled ? "Yes" : "No")
                if !alarm.alarmActions.isEmpty {
                    DetailRow2("Actions", "\(alarm.alarmActions.count) configured")
                }
                if !alarm.dimensions.isEmpty {
                    DetailRow2("Dimensions", alarm.dimensions.map { "\($0.name)=\($0.value)" }.joined(separator: ", "))
                }
            }
            DetailSection("State Reason") {
                Text(alarm.stateReason)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !history.isEmpty {
                DetailSection("History") {
                    ForEach(history) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: item.historyType == "StateUpdate" ? "arrow.triangle.2.circlepath" : "info.circle")
                                .font(.caption2).foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.historySummary).font(.caption).lineLimit(2)
                                if let t = item.timestamp {
                                    Text(relativeTimestamp(t)).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sparkline Chart

struct SparklineChart: View {
    let title: String
    let points: [MetricDataPoint]
    let color: Color

    private var maxVal: Double { points.map(\.sum).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption2.bold()).foregroundColor(.secondary)
                Spacer()
                if let last = points.last {
                    Text(String(format: "%.1f", last.sum)).font(.caption2.monospaced())
                }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.sum)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.sum)
                    )
                    .foregroundStyle(color.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .frame(height: 36)
        }
    }
}

// MARK: - Shared helpers

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            content
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color(NSColor.controlBackgroundColor)))
    }
}

private struct DetailRow2: View {
    let label: String
    let value: String
    var copyable: Bool = false

    init(_ label: String, _ value: String, copyable: Bool = false) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":").font(.caption2).foregroundColor(.secondary).frame(width: 110, alignment: .trailing)
            Text(value).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if copyable && !value.isEmpty {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) } label: {
                    Image(systemName: "doc.on.doc").font(.caption2)
                }
                .buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
    }
}

private struct StatusCheckRow: View {
    let label: String
    let status: String

    init(_ label: String, _ status: String) {
        self.label = label
        self.status = status
    }

    var color: Color { status == "ok" ? .green : status == "not-applicable" ? .secondary : .red }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status == "ok" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(color).font(.caption)
            Text(label).font(.caption)
            Spacer()
            Text(status).font(.caption2).foregroundColor(color)
        }
    }
}

private func metricColor(_ name: String) -> Color {
    switch name {
    case "CPUUtilization": return .orange
    case "FreeableMemory": return .blue
    case "Errors", "StatusCheckFailed", "HTTPCode_Target_5XX_Count": return .red
    case "DatabaseConnections": return .purple
    case "ReadIOPS", "WriteIOPS": return .teal
    default: return .blue
    }
}

private func consoleButton(_ service: String, region: String, resourceId: String) -> some View {
    let url: String
    switch service {
    case "ec2":
        url = "https://\(region).console.aws.amazon.com/ec2/home?region=\(region)#InstanceDetails:instanceId=\(resourceId)"
    default:
        url = "https://console.aws.amazon.com/\(service)"
    }
    return Button("Open in AWS Console") {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
    .font(.caption)
}

private func relativeTimestamp(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    if diff < 3600 { return "\(Int(diff / 60))m ago" }
    if diff < 86400 { return "\(Int(diff / 3600))h ago" }
    return "\(Int(diff / 86400))d ago"
}

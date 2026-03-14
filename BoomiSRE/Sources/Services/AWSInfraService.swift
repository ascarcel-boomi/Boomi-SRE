import Foundation

/// Native Swift client for AWS infrastructure CLI commands (ec2, elbv2, rds, cloudwatch, lambda, cloudtrail, s3).
actor AWSInfraService {

    // MARK: - EC2

    func describeInstances(profile: String, region: String? = nil) async throws -> [EC2Instance] {
        var args = [
            "ec2", "describe-instances",
            "--profile", profile,
            "--output", "json",
            "--query", "Reservations[].Instances[]",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return json.compactMap { EC2Instance($0) }
    }

    // MARK: - ASG

    func describeAutoScalingGroups(profile: String, region: String? = nil) async throws -> [ASGInfo] {
        var args = [
            "autoscaling", "describe-auto-scaling-groups",
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = json["AutoScalingGroups"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return groups.compactMap { ASGInfo($0) }
    }

    // MARK: - ALB

    func describeLoadBalancers(profile: String, region: String? = nil) async throws -> [ALBInfo] {
        var args = [
            "elbv2", "describe-load-balancers",
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lbs = json["LoadBalancers"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return lbs.compactMap { ALBInfo($0) }
    }

    func describeTargetHealth(profile: String, targetGroupArn: String, region: String? = nil) async throws -> [TargetHealthInfo] {
        var args = [
            "elbv2", "describe-target-health",
            "--profile", profile,
            "--target-group-arn", targetGroupArn,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let descriptions = json["TargetHealthDescriptions"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return descriptions.compactMap { TargetHealthInfo($0) }
    }

    func describeTargetGroups(profile: String, loadBalancerArn: String, region: String? = nil) async throws -> [TargetGroupInfo] {
        var args = [
            "elbv2", "describe-target-groups",
            "--profile", profile,
            "--load-balancer-arn", loadBalancerArn,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tgs = json["TargetGroups"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return tgs.compactMap { TargetGroupInfo($0) }
    }

    // MARK: - RDS

    func describeDBInstances(profile: String, region: String? = nil) async throws -> [RDSInstance] {
        var args = [
            "rds", "describe-db-instances",
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instances = json["DBInstances"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return instances.compactMap { RDSInstance($0) }
    }

    func describeDBClusters(profile: String, region: String? = nil) async throws -> [AuroraCluster] {
        var args = [
            "rds", "describe-db-clusters",
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clusters = json["DBClusters"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return clusters.compactMap { AuroraCluster($0) }
    }

    // MARK: - CloudWatch Alarms

    func describeAlarms(profile: String, region: String? = nil, stateValue: String? = nil) async throws -> [CloudWatchAlarm] {
        var args = [
            "cloudwatch", "describe-alarms",
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        if let sv = stateValue { args += ["--state-value", sv] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alarms = json["MetricAlarms"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return alarms.compactMap { CloudWatchAlarm($0) }
    }

    func describeAlarmHistory(profile: String, alarmName: String, region: String? = nil, maxRecords: Int = 10) async throws -> [AlarmHistoryItem] {
        var args = [
            "cloudwatch", "describe-alarm-history",
            "--profile", profile,
            "--alarm-name", alarmName,
            "--max-records", "\(maxRecords)",
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["AlarmHistoryItems"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return items.compactMap { AlarmHistoryItem($0) }
    }

    // MARK: - CloudWatch Metrics

    func getMetricStatistics(
        profile: String,
        namespace: String,
        metricName: String,
        dimensionName: String,
        dimensionValue: String,
        startTime: Date,
        endTime: Date,
        period: Int,
        statistics: [String],
        region: String? = nil
    ) async throws -> [MetricDataPoint] {
        let iso = ISO8601DateFormatter()
        var args = [
            "cloudwatch", "get-metric-statistics",
            "--profile", profile,
            "--namespace", namespace,
            "--metric-name", metricName,
            "--dimensions", "Name=\(dimensionName),Value=\(dimensionValue)",
            "--start-time", iso.string(from: startTime),
            "--end-time", iso.string(from: endTime),
            "--period", "\(period)",
            "--statistics",
        ] + statistics + ["--output", "json"]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let datapoints = json["Datapoints"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return datapoints.compactMap { MetricDataPoint($0) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Lambda

    func listFunctions(profile: String, region: String? = nil) async throws -> [LambdaFunction] {
        var args = [
            "lambda", "list-functions",
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let functions = json["Functions"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return functions.compactMap { LambdaFunction($0) }
    }

    func getLambdaErrors(profile: String, functionName: String, region: String? = nil) async throws -> [MetricDataPoint] {
        let now = Date()
        let startTime = now.addingTimeInterval(-86400)
        let iso = ISO8601DateFormatter()
        var args = [
            "cloudwatch", "get-metric-statistics",
            "--profile", profile,
            "--namespace", "AWS/Lambda",
            "--metric-name", "Errors",
            "--dimensions", "Name=FunctionName,Value=\(functionName)",
            "--start-time", iso.string(from: startTime),
            "--end-time", iso.string(from: now),
            "--period", "3600",
            "--statistics", "Sum",
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let datapoints = json["Datapoints"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return datapoints.compactMap { MetricDataPoint($0) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - CloudTrail

    func lookupEvents(profile: String, region: String? = nil, maxResults: Int = 25) async throws -> [CloudTrailEvent] {
        var args = [
            "cloudtrail", "lookup-events",
            "--profile", profile,
            "--max-results", "\(maxResults)",
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["Events"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return events.compactMap { CloudTrailEvent($0) }
    }

    // MARK: - S3

    func listBuckets(profile: String) async throws -> [S3Bucket] {
        let args = [
            "s3api", "list-buckets",
            "--profile", profile,
            "--output", "json",
        ]
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["Buckets"] as? [[String: Any]] else {
            throw AWSInfraError.parseError
        }
        return buckets.compactMap { S3Bucket($0) }
    }

    // MARK: - EC2 Instance Status

    func describeInstanceStatus(profile: String, instanceId: String, region: String? = nil) async throws -> EC2InstanceStatus? {
        var args = [
            "ec2", "describe-instance-status",
            "--instance-ids", instanceId,
            "--profile", profile,
            "--output", "json",
        ]
        if let r = region { args += ["--region", r] }
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else { throw AWSInfraError.from(output) }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statuses = json["InstanceStatuses"] as? [[String: Any]],
              let first = statuses.first else {
            return nil
        }
        return EC2InstanceStatus(first)
    }

    // Delegates to shared AWSCLIRunner.run() — see Extensions/AWSCLIRunner.swift
    private func runAWS(_ args: [String]) async throws -> (String, Int32) {
        let result = try await AWSCLIRunner.run(arguments: args)
        return (result.output, result.exitCode)
    }
}

// MARK: - Models

struct EC2Instance: Identifiable, Sendable {
    var id: String { instanceId }
    let instanceId: String
    let instanceType: String
    let state: String
    let name: String
    let launchTime: Date?
    let privateIpAddress: String
    let publicIpAddress: String
    let availabilityZone: String
    let platform: String
    let vpcId: String
    let subnetId: String

    var isRunning: Bool { state == "running" }
    var region: String {
        guard availabilityZone.count > 1 else { return availabilityZone }
        return String(availabilityZone.dropLast())
    }

    init?(_ dict: [String: Any]) {
        guard let instanceId = dict["InstanceId"] as? String else { return nil }
        self.instanceId = instanceId
        self.instanceType = dict["InstanceType"] as? String ?? ""
        let stateDict = dict["State"] as? [String: Any]
        self.state = stateDict?["Name"] as? String ?? "unknown"
        self.privateIpAddress = dict["PrivateIpAddress"] as? String ?? ""
        self.publicIpAddress = dict["PublicIpAddress"] as? String ?? ""
        let placement = dict["Placement"] as? [String: Any]
        self.availabilityZone = placement?["AvailabilityZone"] as? String ?? ""
        // Windows platform field is only present for Windows; Linux instances omit it
        self.platform = dict["Platform"] as? String ?? "Linux"
        self.vpcId = dict["VpcId"] as? String ?? ""
        self.subnetId = dict["SubnetId"] as? String ?? ""
        // Parse Name tag
        var nameTag = instanceId
        if let tags = dict["Tags"] as? [[String: Any]] {
            for tag in tags {
                if let key = tag["Key"] as? String, key == "Name",
                   let value = tag["Value"] as? String, !value.isEmpty {
                    nameTag = value
                    break
                }
            }
        }
        self.name = nameTag
        // Parse launch time (ISO8601)
        if let launchStr = dict["LaunchTime"] as? String {
            let iso = ISO8601DateFormatter()
            self.launchTime = iso.date(from: launchStr)
        } else {
            self.launchTime = nil
        }
    }
}

struct ASGInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let minSize: Int
    let maxSize: Int
    let desiredCapacity: Int
    let runningCount: Int
    let unhealthyCount: Int
    let launchTemplateName: String
    let availabilityZones: [String]
    let targetGroupARNs: [String]
    let status: String

    var isHealthy: Bool { runningCount >= desiredCapacity && unhealthyCount == 0 }

    init?(_ dict: [String: Any]) {
        guard let name = dict["AutoScalingGroupName"] as? String else { return nil }
        self.name = name
        self.minSize = dict["MinSize"] as? Int ?? 0
        self.maxSize = dict["MaxSize"] as? Int ?? 0
        self.desiredCapacity = dict["DesiredCapacity"] as? Int ?? 0
        self.availabilityZones = dict["AvailabilityZones"] as? [String] ?? []
        self.targetGroupARNs = dict["TargetGroupARNs"] as? [String] ?? []
        self.status = dict["Status"] as? String ?? ""
        // Count healthy InService instances
        let instances = dict["Instances"] as? [[String: Any]] ?? []
        self.runningCount = instances.filter {
            ($0["HealthStatus"] as? String) == "Healthy" &&
            ($0["LifecycleState"] as? String) == "InService"
        }.count
        self.unhealthyCount = instances.filter {
            ($0["HealthStatus"] as? String) == "Unhealthy"
        }.count
        // Prefer launch template name; fall back to launch configuration
        if let lt = dict["LaunchTemplate"] as? [String: Any],
           let ltName = lt["LaunchTemplateName"] as? String {
            self.launchTemplateName = ltName
        } else {
            self.launchTemplateName = dict["LaunchConfigurationName"] as? String ?? ""
        }
    }
}

struct ALBInfo: Identifiable, Sendable {
    var id: String { arn }
    let arn: String
    let name: String
    let dnsName: String
    let state: String
    let type: String
    let scheme: String
    let availabilityZones: [String]
    let vpcId: String
    let createdTime: Date?

    init?(_ dict: [String: Any]) {
        guard let arn = dict["LoadBalancerArn"] as? String else { return nil }
        self.arn = arn
        self.name = dict["LoadBalancerName"] as? String ?? ""
        self.dnsName = dict["DNSName"] as? String ?? ""
        let stateDict = dict["State"] as? [String: Any]
        self.state = stateDict?["Code"] as? String ?? "unknown"
        self.type = dict["Type"] as? String ?? ""
        self.scheme = dict["Scheme"] as? String ?? ""
        self.vpcId = dict["VpcId"] as? String ?? ""
        let azDicts = dict["AvailabilityZones"] as? [[String: Any]] ?? []
        self.availabilityZones = azDicts.compactMap { $0["ZoneName"] as? String }
        if let createdStr = dict["CreatedTime"] as? String {
            let iso = ISO8601DateFormatter()
            self.createdTime = iso.date(from: createdStr)
        } else {
            self.createdTime = nil
        }
    }
}

struct TargetGroupInfo: Identifiable, Sendable {
    var id: String { arn }
    let arn: String
    let name: String
    let `protocol`: String
    let port: Int
    let targetType: String

    init?(_ dict: [String: Any]) {
        guard let arn = dict["TargetGroupArn"] as? String else { return nil }
        self.arn = arn
        self.name = dict["TargetGroupName"] as? String ?? ""
        self.protocol = dict["Protocol"] as? String ?? ""
        self.port = dict["Port"] as? Int ?? 0
        self.targetType = dict["TargetType"] as? String ?? ""
    }
}

struct TargetHealthInfo: Identifiable, Sendable {
    let id: UUID
    let targetId: String
    let port: Int
    let healthState: String
    let reason: String
    let description: String

    var isHealthy: Bool { healthState == "healthy" }

    init?(_ dict: [String: Any]) {
        guard let target = dict["Target"] as? [String: Any],
              let targetId = target["Id"] as? String else { return nil }
        self.id = UUID()
        self.targetId = targetId
        self.port = target["Port"] as? Int ?? 0
        let health = dict["TargetHealth"] as? [String: Any]
        self.healthState = health?["State"] as? String ?? "unknown"
        self.reason = health?["Reason"] as? String ?? ""
        self.description = health?["Description"] as? String ?? ""
    }
}

struct RDSInstance: Identifiable, Sendable {
    var id: String { identifier }
    let identifier: String
    let engine: String
    let engineVersion: String
    let instanceClass: String
    let status: String
    let multiAZ: Bool
    let storageType: String
    let allocatedStorage: Int
    let endpoint: String
    let availabilityZone: String
    let clusterIdentifier: String

    var isAvailable: Bool { status == "available" }

    init?(_ dict: [String: Any]) {
        guard let identifier = dict["DBInstanceIdentifier"] as? String else { return nil }
        self.identifier = identifier
        self.engine = dict["Engine"] as? String ?? ""
        self.engineVersion = dict["EngineVersion"] as? String ?? ""
        self.instanceClass = dict["DBInstanceClass"] as? String ?? ""
        self.status = dict["DBInstanceStatus"] as? String ?? ""
        self.multiAZ = dict["MultiAZ"] as? Bool ?? false
        self.storageType = dict["StorageType"] as? String ?? ""
        self.allocatedStorage = dict["AllocatedStorage"] as? Int ?? 0
        let ep = dict["Endpoint"] as? [String: Any]
        self.endpoint = ep?["Address"] as? String ?? ""
        self.availabilityZone = dict["AvailabilityZone"] as? String ?? ""
        self.clusterIdentifier = dict["DBClusterIdentifier"] as? String ?? ""
    }
}

struct AuroraCluster: Identifiable, Sendable {
    var id: String { identifier }
    let identifier: String
    let engine: String
    let engineVersion: String
    let status: String
    let writerCount: Int
    let readerCount: Int
    let endpoint: String
    let readerEndpoint: String
    let storageEncrypted: Bool
    let backupRetentionPeriod: Int
    let latestRestorableTime: Date?
    let availabilityZones: [String]

    var isAvailable: Bool { status == "available" }
    var memberCount: Int { writerCount + readerCount }

    init?(_ dict: [String: Any]) {
        guard let identifier = dict["DBClusterIdentifier"] as? String else { return nil }
        self.identifier = identifier
        self.engine = dict["Engine"] as? String ?? ""
        self.engineVersion = dict["EngineVersion"] as? String ?? ""
        self.status = dict["Status"] as? String ?? ""
        self.endpoint = dict["Endpoint"] as? String ?? ""
        self.readerEndpoint = dict["ReaderEndpoint"] as? String ?? ""
        self.storageEncrypted = dict["StorageEncrypted"] as? Bool ?? false
        self.backupRetentionPeriod = dict["BackupRetentionPeriod"] as? Int ?? 0
        self.availabilityZones = dict["AvailabilityZones"] as? [String] ?? []
        // Count writers vs readers from cluster members
        let members = dict["DBClusterMembers"] as? [[String: Any]] ?? []
        self.writerCount = members.filter { $0["IsClusterWriter"] as? Bool == true }.count
        self.readerCount = members.filter { $0["IsClusterWriter"] as? Bool != true }.count
        if let restorableStr = dict["LatestRestorableTime"] as? String {
            let iso = ISO8601DateFormatter()
            self.latestRestorableTime = iso.date(from: restorableStr)
        } else {
            self.latestRestorableTime = nil
        }
    }
}

struct AlarmDimension: Sendable {
    let name: String
    let value: String
}

struct CloudWatchAlarm: Identifiable, Sendable {
    var id: String { alarmName }
    let alarmName: String
    let namespace: String
    let metricName: String
    let stateValue: String
    let stateReason: String
    let stateUpdatedTimestamp: Date?
    let dimensions: [AlarmDimension]
    let threshold: Double
    let comparisonOperator: String
    let evaluationPeriods: Int
    let period: Int
    let statistic: String
    let actionsEnabled: Bool
    let alarmActions: [String]

    init?(_ dict: [String: Any]) {
        guard let alarmName = dict["AlarmName"] as? String else { return nil }
        self.alarmName = alarmName
        self.namespace = dict["Namespace"] as? String ?? ""
        self.metricName = dict["MetricName"] as? String ?? ""
        self.stateValue = dict["StateValue"] as? String ?? ""
        self.stateReason = dict["StateReason"] as? String ?? ""
        self.threshold = dict["Threshold"] as? Double ?? 0
        self.comparisonOperator = dict["ComparisonOperator"] as? String ?? ""
        self.evaluationPeriods = dict["EvaluationPeriods"] as? Int ?? 0
        self.period = dict["Period"] as? Int ?? 0
        self.statistic = dict["Statistic"] as? String ?? ""
        self.actionsEnabled = dict["ActionsEnabled"] as? Bool ?? false
        self.alarmActions = dict["AlarmActions"] as? [String] ?? []
        let dimDicts = dict["Dimensions"] as? [[String: Any]] ?? []
        self.dimensions = dimDicts.compactMap { d -> AlarmDimension? in
            guard let n = d["Name"] as? String, let v = d["Value"] as? String else { return nil }
            return AlarmDimension(name: n, value: v)
        }
        if let tsStr = dict["StateUpdatedTimestamp"] as? String {
            let iso = ISO8601DateFormatter()
            self.stateUpdatedTimestamp = iso.date(from: tsStr)
        } else {
            self.stateUpdatedTimestamp = nil
        }
    }
}

struct LambdaFunction: Identifiable, Sendable {
    var id: String { functionName }
    let functionName: String
    let runtime: String
    let handler: String
    let codeSize: Int64
    let memorySize: Int
    let timeout: Int
    let lastModified: String
    let state: String
    let description: String

    init?(_ dict: [String: Any]) {
        guard let functionName = dict["FunctionName"] as? String else { return nil }
        self.functionName = functionName
        self.runtime = dict["Runtime"] as? String ?? ""
        self.handler = dict["Handler"] as? String ?? ""
        self.codeSize = (dict["CodeSize"] as? Int).map { Int64($0) } ?? 0
        self.memorySize = dict["MemorySize"] as? Int ?? 128
        self.timeout = dict["Timeout"] as? Int ?? 3
        self.lastModified = dict["LastModified"] as? String ?? ""
        self.description = dict["Description"] as? String ?? ""
        // State lives inside nested FunctionConfiguration.State in list-functions
        // but can also be at root when described individually
        if let stateDict = dict["State"] as? String {
            self.state = stateDict
        } else {
            self.state = "Active"
        }
    }
}

struct MetricDataPoint: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let sum: Double
    let unit: String

    init?(_ dict: [String: Any]) {
        guard let tsStr = dict["Timestamp"] as? String else { return nil }
        let iso = ISO8601DateFormatter()
        guard let ts = iso.date(from: tsStr) else { return nil }
        self.id = UUID()
        self.timestamp = ts
        self.sum = dict["Sum"] as? Double ?? 0
        self.unit = dict["Unit"] as? String ?? ""
    }
}

struct TrailResource: Sendable {
    let type: String
    let name: String
}

struct CloudTrailEvent: Identifiable, Sendable {
    var id: String { eventId }
    let eventId: String
    let eventName: String
    let eventSource: String
    let eventTime: Date?
    let username: String
    let sourceIPAddress: String
    let resources: [TrailResource]

    var isDestructive: Bool {
        eventName.hasPrefix("Delete") || eventName.hasPrefix("Terminate") || eventName.hasPrefix("Remove")
    }
    var isModification: Bool {
        eventName.hasPrefix("Update") || eventName.hasPrefix("Modify") ||
        eventName.hasPrefix("Put") || eventName.hasPrefix("Create") ||
        eventName.hasPrefix("Start") || eventName.hasPrefix("Stop")
    }

    init?(_ dict: [String: Any]) {
        guard let eventId = dict["EventId"] as? String else { return nil }
        self.eventId = eventId
        self.eventName = dict["EventName"] as? String ?? ""
        self.eventSource = dict["EventSource"] as? String ?? ""
        self.username = dict["Username"] as? String ?? ""
        // CloudTrail events may embed the full CloudTrailEvent JSON in "CloudTrailEvent"
        // Extract source IP from there if possible
        var sourceIP = ""
        if let rawJson = dict["CloudTrailEvent"] as? String,
           let jsonData = rawJson.data(using: .utf8),
           let inner = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            sourceIP = inner["sourceIPAddress"] as? String ?? ""
        }
        self.sourceIPAddress = sourceIP
        let resourceDicts = dict["Resources"] as? [[String: Any]] ?? []
        self.resources = resourceDicts.compactMap { r -> TrailResource? in
            guard let name = r["ResourceName"] as? String else { return nil }
            return TrailResource(type: r["ResourceType"] as? String ?? "", name: name)
        }
        if let tsDouble = dict["EventTime"] as? Double {
            self.eventTime = Date(timeIntervalSince1970: tsDouble)
        } else if let tsStr = dict["EventTime"] as? String {
            let iso = ISO8601DateFormatter()
            self.eventTime = iso.date(from: tsStr)
        } else {
            self.eventTime = nil
        }
    }
}

struct S3Bucket: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let creationDate: Date?

    init?(_ dict: [String: Any]) {
        guard let name = dict["Name"] as? String else { return nil }
        self.name = name
        if let dateStr = dict["CreationDate"] as? String {
            let iso = ISO8601DateFormatter()
            self.creationDate = iso.date(from: dateStr)
        } else {
            self.creationDate = nil
        }
    }
}

struct EC2InstanceStatus: Sendable {
    let instanceId: String
    let systemStatus: String
    let instanceStatus: String

    init?(_ dict: [String: Any]) {
        guard let instanceId = dict["InstanceId"] as? String else { return nil }
        self.instanceId = instanceId
        let sysStatus = dict["SystemStatus"] as? [String: Any]
        self.systemStatus = sysStatus?["Status"] as? String ?? "not-applicable"
        let instStatus = dict["InstanceStatus"] as? [String: Any]
        self.instanceStatus = instStatus?["Status"] as? String ?? "not-applicable"
    }
}

struct AlarmHistoryItem: Identifiable, Sendable {
    let id: UUID
    let alarmName: String
    let historyType: String
    let historyData: String
    let historySummary: String
    let timestamp: Date?

    init?(_ dict: [String: Any]) {
        guard let alarmName = dict["AlarmName"] as? String else { return nil }
        self.id = UUID()
        self.alarmName = alarmName
        self.historyType = dict["HistoryItemType"] as? String ?? ""
        self.historyData = dict["HistoryData"] as? String ?? ""
        self.historySummary = dict["HistorySummary"] as? String ?? ""
        if let tsStr = dict["Timestamp"] as? String {
            let iso = ISO8601DateFormatter()
            self.timestamp = iso.date(from: tsStr)
        } else {
            self.timestamp = nil
        }
    }
}

// MARK: - Errors

enum AWSInfraError: LocalizedError {
    case cliFailed(String)
    case parseError
    case sessionExpired
    case accessDenied(String)

    static func from(_ output: String) -> AWSInfraError {
        if output.contains("ExpiredTokenException") || output.contains("expired") { return .sessionExpired }
        if output.contains("AccessDeniedException") || output.contains("not authorized") { return .accessDenied(output) }
        return .cliFailed(output)
    }

    var errorDescription: String? {
        switch self {
        case .cliFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "AWS CLI error:\n\(String(trimmed.prefix(500)))"
        case .parseError:
            return "Failed to parse AWS CLI response."
        case .sessionExpired:
            return "AWS session expired. Re-authenticate in Settings or sidebar."
        case .accessDenied(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Access denied: \(String(trimmed.prefix(300)))"
        }
    }
}

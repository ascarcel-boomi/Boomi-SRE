import Foundation

// MARK: - FY27 BPOP Metrics

extension BPOPMetric {
    /// All 15 FY27 BPOP metrics.
    static let allMetrics: [BPOPMetric] = [

        // MARK: Reliability (4)
        BPOPMetric(
            id: "reliability-availability",
            pillar: .reliability,
            name: "Platform Availability",
            description: "Percentage of time the Boomi APIM platform is fully operational",
            unit: .percent,
            target: 99.9,
            direction: .higherIsBetter,
            dataSource: .grafana,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "reliability-mttr",
            pillar: .reliability,
            name: "Mean Time to Restore (MTTR)",
            description: "Average time in minutes to restore service after an incident",
            unit: .minutes,
            target: 30,
            direction: .lowerIsBetter,
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "reliability-p1-count",
            pillar: .reliability,
            name: "P1 Incidents (YTD)",
            description: "Total number of Severity 1 incidents year-to-date",
            unit: .count,
            target: 5,
            direction: .lowerIsBetter,
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "reliability-error-rate",
            pillar: .reliability,
            name: "API Error Rate",
            description: "Percentage of API calls returning 5xx errors",
            unit: .percent,
            target: 0.1,
            direction: .lowerIsBetter,
            dataSource: .grafana,
            currentValue: nil, lastUpdated: nil
        ),

        // MARK: Velocity (3)
        BPOPMetric(
            id: "velocity-sprint-completion",
            pillar: .velocity,
            name: "Sprint Story Point Completion",
            description: "Percentage of committed story points completed each sprint",
            unit: .percent,
            target: 80,
            direction: .higherIsBetter,
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "velocity-cycle-time",
            pillar: .velocity,
            name: "Cycle Time",
            description: "Average days from ticket start to Done",
            unit: .days,
            target: 5,
            direction: .lowerIsBetter,
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "velocity-lead-time",
            pillar: .velocity,
            name: "Lead Time for Changes",
            description: "Average time from commit to production deployment",
            unit: .hours,
            target: 24,
            direction: .lowerIsBetter,
            dataSource: .jenkins,
            currentValue: nil, lastUpdated: nil
        ),

        // MARK: Security (3)
        BPOPMetric(
            id: "security-patch-compliance",
            pillar: .security,
            name: "Patch Compliance",
            description: "Percentage of systems within patch compliance window",
            unit: .percent,
            target: 95,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "security-vuln-open",
            pillar: .security,
            name: "Open Critical Vulnerabilities",
            description: "Number of open critical/high CVEs across managed infrastructure",
            unit: .count,
            target: 0,
            direction: .lowerIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "security-cert-expiry",
            pillar: .security,
            name: "Certificates Expiring Soon",
            description: "Certificates expiring within 30 days",
            unit: .count,
            target: 0,
            direction: .lowerIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),

        // MARK: Cost (2)
        BPOPMetric(
            id: "cost-monthly-aws",
            pillar: .cost,
            name: "Monthly AWS Spend",
            description: "Total AWS infrastructure spend this month vs. budget",
            unit: .currency,
            target: 50000,
            direction: .lowerIsBetter,
            dataSource: .aws,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "cost-savings-ytd",
            pillar: .cost,
            name: "Cost Savings (YTD)",
            description: "Cumulative cost savings from SRE optimization efforts",
            unit: .currency,
            target: 100000,
            direction: .higherIsBetter,
            dataSource: .aws,
            currentValue: nil, lastUpdated: nil
        ),

        // MARK: Customer Impact (3)
        BPOPMetric(
            id: "customer-p1-customer-hours",
            pillar: .customerImpact,
            name: "Customer-Impacting Downtime (hrs)",
            description: "Cumulative hours of customer-facing service degradation",
            unit: .hours,
            target: 1,
            direction: .lowerIsBetter,
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "customer-csat",
            pillar: .customerImpact,
            name: "Customer Satisfaction (CSAT)",
            description: "CSAT score from post-incident surveys",
            unit: .percent,
            target: 90,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "customer-api-latency-p99",
            pillar: .customerImpact,
            name: "API Latency P99",
            description: "99th percentile API response time in milliseconds",
            unit: .minutes,
            target: 500,
            direction: .lowerIsBetter,
            dataSource: .grafana,
            currentValue: nil, lastUpdated: nil
        ),
    ]
}

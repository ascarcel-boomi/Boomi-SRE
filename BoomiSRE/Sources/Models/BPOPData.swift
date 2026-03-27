import Foundation

// MARK: - FY27 BPOP Metrics (Culture / Platform / Growth / Trust / Focus)
// Source of truth: Combined_SRE_BPOP_FY27_v2.csv

extension BPOPMetric {
    static let allMetrics: [BPOPMetric] = [

        // ── CULTURE (3) ─────────────────────────────────────
        BPOPMetric(
            id: "culture-enps",
            pillar: .culture,
            name: "eNPS & Retention",
            description: "5pt improvement in eNPS YoY with 90%+ high-performer retention",
            unit: .number,
            target: 5,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "culture-ai-adoption",
            pillar: .culture,
            name: "AI Adoption",
            description: "90% of SRE workflows using approved AI tools with measured productivity gains by end of FY27",
            unit: .percent,
            target: 90,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "culture-training",
            pillar: .culture,
            name: "BPOP & Training",
            description: "100% BPOP participation; 10hr IC coursework / 8hr manager coursework completed",
            unit: .percent,
            target: 100,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),

        // ── PLATFORM (3) ────────────────────────────────────
        BPOPMetric(
            id: "platform-sla",
            pillar: .platform,
            name: "SLA & Security",
            description: "99.99% Platform and Runtime SLA with A+ security scorecard — including acquisitions",
            unit: .percent,
            target: 99.99,
            direction: .higherIsBetter,
            dataSource: .grafana,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "platform-resilience",
            pillar: .platform,
            name: "Resilience & Testing",
            description: "One DR game day per quarter; 90% test coverage for new modules; 30% regression suite expansion",
            unit: .count,
            target: 4,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "platform-recurring",
            pillar: .platform,
            name: "Recurring Issues Remediated",
            description: "5 recurring operational issues identified and remediated per quarter (20/year)",
            unit: .count,
            target: 20,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),

        // ── GROWTH (3) ──────────────────────────────────────
        BPOPMetric(
            id: "growth-transition",
            pillar: .growth,
            name: "Service Transition",
            description: "Transition deployment and infra ops for 20 services from 5 Element teams to SRE across PC3, PC4, and Production",
            unit: .count,
            target: 20,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "growth-golden-metrics",
            pillar: .growth,
            name: "Golden Metrics & Lead Time",
            description: "Improve service management golden metrics by 50% vs FY26; reduce change lead time by 20%",
            unit: .percent,
            target: 50,
            direction: .higherIsBetter,
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "growth-compliance-ai",
            pillar: .growth,
            name: "Compliance & AI Agents",
            description: "All FEDRAMP/compliance attestations retained; at least one AI Agent or Workflow implemented per SRE element",
            unit: .percent,
            target: 100,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),

        // ── TRUST (3) ───────────────────────────────────────
        BPOPMetric(
            id: "trust-rca-capa",
            pillar: .trust,
            name: "RCA & CAPA",
            description: "Sev-1 RCAs delivered within 5 business days for 95% of incidents; CAPA addressed within 3 weeks for High/Critical",
            unit: .percent,
            target: 95,
            direction: .higherIsBetter,
            // NOTE: Auto-population from Jira deferred — requires JQL query for resolved Sev-1
            // incidents and resolution time calculation against 5-business-day SLA.
            // Tracked in BPOPViewModel.refreshFromJira() when implemented.
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "trust-mttd-mttr",
            pillar: .trust,
            name: "MTTD/MTTR Improvement",
            description: "MTTD and MTTR improved 25% YoY via AI anomaly detection — at least one deployment per element",
            unit: .percent,
            target: 25,
            direction: .higherIsBetter,
            // NOTE: Auto-population deferred — requires Jira incident query comparing
            // current MTTD/MTTR against FY26 baseline values (not yet stored).
            // Tracked in BPOPViewModel.refreshFromJira() when implemented.
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "trust-defects",
            pillar: .trust,
            name: "Defect Reduction",
            description: "Customer bug backlog reduced 45%; release-related Sev-1/2 reduced 15% vs FY25; zero DNS/cert disruptions",
            unit: .percent,
            target: 45,
            direction: .higherIsBetter,
            // NOTE: Auto-population deferred — requires Jira bug backlog query
            // comparing current count against FY26 baseline (not yet stored).
            // Tracked in BPOPViewModel.refreshFromJira() when implemented.
            dataSource: .jira,
            currentValue: nil, lastUpdated: nil
        ),

        // ── FOCUS (3) ───────────────────────────────────────
        BPOPMetric(
            id: "focus-health-metrics",
            pillar: .focus,
            name: "Engineering Health",
            description: "5 engineering health metrics tracked monthly — at least 4 improving by FY27 end",
            unit: .count,
            target: 4,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "focus-ai-generation",
            pillar: .focus,
            name: "AI Code Generation",
            description: "70% of code, docs, and test cases generated with AI tools while maintaining quality gates",
            unit: .percent,
            target: 70,
            direction: .higherIsBetter,
            dataSource: .manual,
            currentValue: nil, lastUpdated: nil
        ),
        BPOPMetric(
            id: "focus-change-safety",
            pillar: .focus,
            name: "Change Safety",
            description: "100% production changes validated in lower environments; SRE engaged early on all infrastructure changes",
            unit: .percent,
            target: 100,
            direction: .higherIsBetter,
            dataSource: .jenkins,
            currentValue: nil, lastUpdated: nil
        ),
    ]
}

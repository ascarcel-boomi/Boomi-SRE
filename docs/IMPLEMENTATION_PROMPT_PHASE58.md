# Boomi SRE App — Phase 58: Fix BPOP Dashboard — Replace Wrong Metrics with Actual FY27 BPOP

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `~/Downloads/Combined_SRE_BPOP_FY27_v2.csv` — the ACTUAL FY27 BPOP with 5 pillars (Culture, Platform, Growth, Trust, Focus) × 3 metrics = 15 metrics. THIS IS THE SOURCE OF TRUTH.
- `BoomiSRE/Sources/Models/BPOPModels.swift` — current pillar enum (WRONG: Reliability, Velocity, Security, Cost, Customer Impact)
- `BoomiSRE/Sources/Models/BPOPData.swift` — current 15 metrics (ALL WRONG: Platform Availability, MTTR, API Error Rate, etc.)
- `BoomiSRE/Sources/Views/Panels/BPOPDashboardView.swift` — the BPOP dashboard view

---

## Problem

The BPOP Dashboard was implemented with completely wrong data. The pillars and all 15 metrics were made up instead of using the actual BPOP that was defined in the CSV file.

**What's wrong:**
- Pillars: Reliability, Velocity, Security, Cost, Customer Impact ← ALL WRONG
- Metrics: Platform Availability, MTTR, P1 Incidents, API Error Rate, etc. ← ALL WRONG

**What it should be:**
- Pillars: Culture, Platform, Growth, Trust, Focus
- Metrics: eNPS & Retention, AI Adoption, BPOP & Training, SLA & Security, etc. (15 total from the CSV)

---

## Implementation

### Phase 58A: Replace the BPOPPillar Enum

In `BPOPModels.swift`, replace the entire `BPOPPillar` enum:

```swift
enum BPOPPillar: String, CaseIterable, Codable {
    case culture  = "Culture"
    case platform = "Platform"
    case growth   = "Growth"
    case trust    = "Trust"
    case focus    = "Focus"

    var icon: String {
        switch self {
        case .culture:  return "person.3.fill"
        case .platform: return "server.rack"
        case .growth:   return "chart.line.uptrend.xyaxis"
        case .trust:    return "shield.checkmark"
        case .focus:    return "target"
        }
    }

    var color: Color {
        switch self {
        case .culture:  return .purple
        case .platform: return .blue
        case .growth:   return .green
        case .trust:    return .orange
        case .focus:    return .red
        }
    }
}
```

### Phase 58B: Replace All 15 Metrics

In `BPOPData.swift`, replace the entire `allMetrics` array with the actual BPOP:

```swift
extension BPOPMetric {
    static let allMetrics: [BPOPMetric] = [

        // ── CULTURE (3) ─────────────────────────────────────
        BPOPMetric(id: "culture-enps", pillar: .culture,
                   name: "eNPS & Retention",
                   description: "5pt improvement in eNPS YoY with 90%+ high-performer retention",
                   unit: .number, target: 5, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "culture-ai-adoption", pillar: .culture,
                   name: "AI Adoption",
                   description: "90% of SRE workflows using approved AI tools with measured productivity gains",
                   unit: .percent, target: 90, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "culture-training", pillar: .culture,
                   name: "BPOP & Training",
                   description: "100% BPOP participation; 10hr IC / 8hr manager coursework completed",
                   unit: .percent, target: 100, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),

        // ── PLATFORM (3) ────────────────────────────────────
        BPOPMetric(id: "platform-sla", pillar: .platform,
                   name: "SLA & Security",
                   description: "99.99% Platform and Runtime SLA with A+ security scorecard — including acquisitions",
                   unit: .percent, target: 99.99, direction: .higherIsBetter,
                   dataSource: .grafana, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "platform-resilience", pillar: .platform,
                   name: "Resilience & Testing",
                   description: "Quarterly DR game days; 90% test coverage for new modules; 30% regression expansion",
                   unit: .count, target: 4, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "platform-recurring", pillar: .platform,
                   name: "Recurring Issues Remediated",
                   description: "5 recurring operational issues identified and remediated per quarter (20/year)",
                   unit: .count, target: 20, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),

        // ── GROWTH (3) ──────────────────────────────────────
        BPOPMetric(id: "growth-transition", pillar: .growth,
                   name: "Service Transition",
                   description: "Transition deployment + infra ops for 20 services from Element teams to SRE",
                   unit: .count, target: 20, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "growth-golden-metrics", pillar: .growth,
                   name: "Golden Metrics & Lead Time",
                   description: "Improve service management golden metrics by 50% vs FY26; reduce change lead time by 20%",
                   unit: .percent, target: 50, direction: .higherIsBetter,
                   dataSource: .jira, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "growth-compliance-ai", pillar: .growth,
                   name: "Compliance & AI Agents",
                   description: "All compliance attestations retained; at least one AI Agent per SRE element",
                   unit: .percent, target: 100, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),

        // ── TRUST (3) ───────────────────────────────────────
        BPOPMetric(id: "trust-rca-capa", pillar: .trust,
                   name: "RCA & CAPA",
                   description: "Sev-1 RCAs within 5 business days (95%); CAPA within 3 weeks for High/Critical",
                   unit: .percent, target: 95, direction: .higherIsBetter,
                   dataSource: .jira, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "trust-mttd-mttr", pillar: .trust,
                   name: "MTTD/MTTR Improvement",
                   description: "25% improvement in MTTD and MTTR via AI anomaly detection — one per element",
                   unit: .percent, target: 25, direction: .higherIsBetter,
                   dataSource: .jira, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "trust-defects", pillar: .trust,
                   name: "Defect Reduction",
                   description: "Bug backlog reduced 45%; release Sev-1/2 reduced 15%; zero DNS/cert disruptions",
                   unit: .percent, target: 45, direction: .higherIsBetter,
                   dataSource: .jira, currentValue: nil, lastUpdated: nil),

        // ── FOCUS (3) ───────────────────────────────────────
        BPOPMetric(id: "focus-health-metrics", pillar: .focus,
                   name: "Engineering Health",
                   description: "5 health metrics tracked monthly — at least 4 improving by FY27 end",
                   unit: .count, target: 4, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "focus-ai-generation", pillar: .focus,
                   name: "AI Code Generation",
                   description: "70% of code, docs, and test cases generated with AI tools with quality gates",
                   unit: .percent, target: 70, direction: .higherIsBetter,
                   dataSource: .manual, currentValue: nil, lastUpdated: nil),
        BPOPMetric(id: "focus-change-safety", pillar: .focus,
                   name: "Change Safety",
                   description: "100% production changes validated in lower environments; SRE engaged early",
                   unit: .percent, target: 100, direction: .higherIsBetter,
                   dataSource: .jenkins, currentValue: nil, lastUpdated: nil),
    ]
}
```

### Phase 58C: Fix Any Compile Errors from the Enum Change

The `BPOPDashboardView` and any other file that references the old pillar cases (`.reliability`, `.velocity`, `.security`, `.cost`, `.customerImpact`) will break. Search the entire `Sources/` directory for these old enum cases and replace them:

- `.reliability` → remove/replace (no direct equivalent — it's now `.platform` for SLA-related or `.trust` for incident-related)
- `.velocity` → remove/replace
- `.security` → remove/replace
- `.cost` → remove/replace
- `.customerImpact` → remove/replace

Since the `BPOPDashboardView` iterates `BPOPPillar.allCases` dynamically, most of the view code should just work with the new enum values. But check for any hardcoded references to old case names.

Also check:
- `BPOPDashboardView.swift` — filter chips, pillar cards, any hardcoded pillar references
- `DashboardViewModel.swift` — if it references specific BPOP metrics by ID or pillar

### Phase 58D: Auto-Populate Metrics That Can Be Fetched

For metrics with `dataSource: .jira`, try to auto-populate current values from Jira data:

1. **`trust-rca-capa`** (RCA within 5 business days):
   - Query: `project = "Boomi Incident Management" AND priority = Highest AND resolved >= -90d`
   - For each resolved incident, check if `resolutiondate - created <= 5 business days`
   - Calculate percentage
   - This is complex — for now, leave as manual but add a placeholder comment in the code noting how to automate it later

2. **`trust-defects`** (Bug backlog reduction):
   - Query current open bugs: `issuetype = Bug AND statusCategory NOT IN (Done) AND project IN ({projects})`
   - This gives the current count. To calculate "45% reduction" you'd need the FY26 baseline — leave as manual for now

3. **`growth-golden-metrics`** (Golden metrics improvement):
   - This requires baseline data from FY26 — leave as manual

4. **For the `platform-sla` metric**, if we have Grafana uptime data, we could pull it. But for now, leave as manual since we don't know which Grafana dashboard has SLA data.

**Bottom line for this phase:** Most metrics start as manual entry. The "Edit Values" button should allow managers to enter current values for each metric. Automatic population can be added incrementally later.

### Phase 58E: Verify the Edit Values Feature Works

The screenshot shows an "Edit Values" button in the top right of the BPOP Dashboard. Verify that:
1. Clicking it opens an editor where each metric's current value can be entered
2. Values are saved to `~/.boomi_sre_bpop.json`
3. After saving, the progress bars and status icons update immediately
4. The per-team view works — managers can enter values per team

If the edit feature is broken or missing, implement it:
```swift
// A sheet or inline editor that shows each metric with a text field for current value
ForEach(metrics) { metric in
    HStack {
        Text(metric.name).font(.callout)
        Spacer()
        TextField("Current", value: Binding(
            get: { metric.currentValue ?? 0 },
            set: { newValue in updateMetricValue(metric.id, value: newValue) }
        ), format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 80)
        Text("/ \(metric.formattedTarget)")
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Fix BPOP — replace wrong metrics with actual FY27 BPOP (Culture/Platform/Growth/Trust/Focus)"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

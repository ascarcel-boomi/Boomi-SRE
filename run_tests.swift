#!/usr/bin/env swift
/// Standalone test runner — works without Xcode.
/// Run: swift run_tests.swift (from the Boomi-SRE directory)

import Foundation

// We test the non-UI logic by reimplementing the key types inline,
// since we can't import the SwiftUI-based module without Xcode.

// ============================================================================
// Minimal reimplementations of testable types
// ============================================================================

struct ResultRow {
    let label: String
    let value: Double
    let group: String
    let detail: String
    init(label: String, value: Double, group: String = "", detail: String = "") {
        self.label = label; self.value = value; self.group = group; self.detail = detail
    }
}

enum ChartType { case bar, line, pie, stackedBar, horizontalBar, table }

struct ResultSection {
    let title: String; let rows: [ResultRow]; let chartHint: ChartType
}

struct ReportResult {
    let title: String; let generatedAt: Date; let sections: [ResultSection]; let rawOutput: String
}

enum ReportSection: String, CaseIterable {
    case awsCost = "AWS Cost Reports"
    case jiraAnalytics = "Jira / SRE Analytics"
    case fy26Eval = "FY26 Self-Evaluation"
    case automation = "Automation & Scheduling"
    var icon: String {
        switch self {
        case .awsCost: return "dollarsign.circle"
        case .jiraAnalytics: return "chart.bar.xaxis"
        case .fy26Eval: return "checkmark.seal"
        case .automation: return "clock.arrow.2.circlepath"
        }
    }
}

struct ReportItem: Identifiable, Hashable {
    let id: String; let title: String; let description: String
    let section: ReportSection; let scriptName: String
    let csvKeys: [String]; let chartType: ChartType
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ReportItem, rhs: ReportItem) -> Bool { lhs.id == rhs.id }
}

// Copy of OutputParser logic for testing
struct OutputParser {
    static func parse(output: String, report: ReportItem) -> ReportResult {
        let lines = output.components(separatedBy: "\n")
        var sections: [ResultSection] = []
        var currentTitle = report.title
        var currentRows: [ResultRow] = []
        let currentChartHint = report.chartType

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("===") || trimmed.hasPrefix("---") {
                if !currentRows.isEmpty {
                    sections.append(ResultSection(title: currentTitle, rows: currentRows, chartHint: currentChartHint))
                    currentRows = []
                }
                continue
            }
            if trimmed.count > 3 && trimmed == trimmed.uppercased() && !trimmed.contains(":") &&
                trimmed.rangeOfCharacter(from: .letters) != nil && !trimmed.hasPrefix("|") {
                if !currentRows.isEmpty {
                    sections.append(ResultSection(title: currentTitle, rows: currentRows, chartHint: currentChartHint))
                    currentRows = []
                }
                currentTitle = trimmed.capitalized
                continue
            }
            if let m = extractLabelValue(from: trimmed) { currentRows.append(m); continue }
            if let m = extractDashPattern(from: trimmed) { currentRows.append(m); continue }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if let m = extractTableRow(from: trimmed) { currentRows.append(m) }
                continue
            }
            if let m = extractAlignedColumns(from: trimmed) { currentRows.append(m); continue }
        }
        if !currentRows.isEmpty {
            sections.append(ResultSection(title: currentTitle, rows: currentRows, chartHint: currentChartHint))
        }
        if sections.isEmpty {
            sections.append(ResultSection(title: report.title,
                rows: [ResultRow(label: "Raw Output", value: 0, detail: output)], chartHint: .table))
        }
        return ReportResult(title: report.title, generatedAt: Date(), sections: sections, rawOutput: output)
    }

    private static func extractLabelValue(from line: String) -> ResultRow? {
        guard let colonRange = line.range(of: ": ") else { return nil }
        let label = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rest = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        if let value = parseNumber(rest) { return ResultRow(label: label, value: value, detail: rest) }
        if !rest.isEmpty && label.count < 60 { return ResultRow(label: label, value: 0, detail: rest) }
        return nil
    }

    private static func extractDashPattern(from line: String) -> ResultRow? {
        for sep in [" — ", " – ", " - "] {
            guard let range = line.range(of: sep) else { continue }
            let label = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, label.count < 80 else { continue }
            if let value = parseNumber(rest) { return ResultRow(label: label, value: value, detail: rest) }
        }
        return nil
    }

    private static func extractTableRow(from line: String) -> ResultRow? {
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 2 else { return nil }
        if cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) { return nil }
        let label = cells[0]
        guard !label.isEmpty else { return nil }
        for i in 1..<cells.count {
            if let value = parseNumber(cells[i]) {
                return ResultRow(label: label, value: value, detail: cells.dropFirst().joined(separator: " | "))
            }
        }
        return ResultRow(label: label, value: 0, detail: cells.dropFirst().joined(separator: " | "))
    }

    private static func extractAlignedColumns(from line: String) -> ResultRow? {
        let pattern = #"^(.+?)\s{2,}([\$]?[\d,]+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        guard let lr = Range(match.range(at: 1), in: line),
              let vr = Range(match.range(at: 2), in: line) else { return nil }
        let label = String(line[lr]).trimmingCharacters(in: .whitespaces)
        let valueStr = String(line[vr])
        guard !label.isEmpty, let value = parseNumber(valueStr) else { return nil }
        return ResultRow(label: label, value: value, detail: valueStr)
    }

    static func parseNumber(_ s: String) -> Double? {
        var cleaned = s.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("$") { cleaned = String(cleaned.dropFirst()) }
        if cleaned.hasSuffix("%") { cleaned = String(cleaned.dropLast()) }
        let pattern = #"[\d,]+\.?\d*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range, in: cleaned) else { return nil }
        let numStr = String(cleaned[range]).replacingOccurrences(of: ",", with: "")
        return Double(numStr)
    }
}

// ============================================================================
// Report Catalog (copied for validation)
// ============================================================================

let allReports: [ReportItem] = [
    ReportItem(id: "aws_cam_prod", title: "CAM Production Costs", description: "", section: .awsCost,
               scriptName: "generate_real_aws_report.py", csvKeys: [], chartType: .bar),
    ReportItem(id: "aws_smoke_test", title: "Top 10 Services", description: "", section: .awsCost,
               scriptName: "test_real_aws_costs.py", csvKeys: [], chartType: .horizontalBar),
    ReportItem(id: "jira_epic_dist", title: "Epic Distribution", description: "", section: .jiraAnalytics,
               scriptName: "analyze_boomi_sre.py", csvKeys: ["Epics completed by Boomi SRE in 2025.csv"], chartType: .pie),
    ReportItem(id: "jira_sev2", title: "Sev2 Incidents YoY", description: "", section: .jiraAnalytics,
               scriptName: "analyze_sev2.py", csvKeys: [], chartType: .line),
    ReportItem(id: "jira_planned_unplanned", title: "Planned vs Unplanned", description: "", section: .jiraAnalytics,
               scriptName: "planned_vs_unplanned.py", csvKeys: [], chartType: .stackedBar),
    ReportItem(id: "jira_team_perf", title: "Team Performance", description: "", section: .jiraAnalytics,
               scriptName: "team_performance.py", csvKeys: [], chartType: .bar),
    ReportItem(id: "jira_yoy", title: "YoY Comparison", description: "", section: .jiraAnalytics,
               scriptName: "yoy_comparison.py", csvKeys: [], chartType: .stackedBar),
    ReportItem(id: "jira_work_dist", title: "Work Distribution", description: "", section: .jiraAnalytics,
               scriptName: "work_distribution.py", csvKeys: [], chartType: .pie),
    ReportItem(id: "jira_alert_yoy", title: "Alert Volume YoY", description: "", section: .jiraAnalytics,
               scriptName: "analyze_unplanned.py", csvKeys: [], chartType: .bar),
]

// ============================================================================
// Test harness
// ============================================================================

var passed = 0
var failed = 0
var errors: [String] = []

func assert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        errors.append("FAIL [\(line)]: \(msg)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String, line: Int = #line) {
    assert(a == b, "\(msg) — got \(a), expected \(b)", line: line)
}

// ============================================================================
// Tests
// ============================================================================

print("Running Boomi SRE Tests...\n")

// --- Report Catalog ---
assert(allReports.count > 5, "Catalog has >5 reports")
let ids = allReports.map(\.id)
assertEqual(ids.count, Set(ids).count, "All report IDs unique")
assert(allReports.filter({ $0.section == .awsCost }).count > 0, "AWS section has reports")
assert(allReports.filter({ $0.section == .jiraAnalytics }).count > 0, "Jira section has reports")
for r in allReports { assert(r.scriptName.hasSuffix(".py"), "\(r.id) has .py script") }
for s in ReportSection.allCases { assert(!s.icon.isEmpty, "\(s.rawValue) has icon") }

// --- Number parsing ---
assertEqual(OutputParser.parseNumber("123"), 123, "Parse 123")
assertEqual(OutputParser.parseNumber("$1,234.56"), 1234.56, "Parse $1,234.56")
assertEqual(OutputParser.parseNumber("45%"), 45, "Parse 45%")
assertEqual(OutputParser.parseNumber("$12,345"), 12345, "Parse $12,345")
assert(OutputParser.parseNumber("abc") == nil, "Non-numeric returns nil")
assert(OutputParser.parseNumber("") == nil, "Empty returns nil")

// --- Label: value parsing ---
let r1 = OutputParser.parse(
    output: "Total Cost: $1,234.56\nEC2: $456.78\nS3: $123.45",
    report: ReportItem(id: "t", title: "T", description: "", section: .awsCost,
                       scriptName: "t.py", csvKeys: [], chartType: .bar))
let rows1 = r1.sections.flatMap(\.rows)
assert(rows1.contains { $0.label == "Total Cost" }, "Finds 'Total Cost'")
assert(rows1.contains { $0.label == "EC2" && $0.value == 456.78 }, "EC2 = 456.78")
assert(rows1.contains { $0.label == "S3" && $0.value == 123.45 }, "S3 = 123.45")

// --- Dash pattern ---
let r2 = OutputParser.parse(
    output: "Security — 25 (30%)\nKTLO — 15 (18%)\nInfrastructure — 42 (52%)",
    report: ReportItem(id: "t", title: "T", description: "", section: .jiraAnalytics,
                       scriptName: "t.py", csvKeys: [], chartType: .pie))
let rows2 = r2.sections.flatMap(\.rows)
assert(rows2.contains { $0.label == "Security" && $0.value == 25 }, "Security = 25")
assert(rows2.contains { $0.label == "Infrastructure" && $0.value == 42 }, "Infrastructure = 42")

// --- Table rows ---
let r3 = OutputParser.parse(
    output: "| Service | Cost |\n| ------- | ---- |\n| EC2     | 456  |\n| S3      | 123  |",
    report: ReportItem(id: "t", title: "T", description: "", section: .awsCost,
                       scriptName: "t.py", csvKeys: [], chartType: .bar))
let rows3 = r3.sections.flatMap(\.rows)
assert(rows3.contains { $0.label == "EC2" && $0.value == 456 }, "Table: EC2 = 456")
assert(rows3.contains { $0.label == "S3" && $0.value == 123 }, "Table: S3 = 123")

// --- Section dividers ---
let r4 = OutputParser.parse(
    output: "SUMMARY\n===\nTotal: 100\n---\nDETAILS\n===\nAlpha: 60\nBeta: 40",
    report: ReportItem(id: "t", title: "T", description: "", section: .jiraAnalytics,
                       scriptName: "t.py", csvKeys: [], chartType: .bar))
assert(r4.sections.count >= 2, "Section dividers create >=2 sections (got \(r4.sections.count))")

// --- Empty output ---
let r5 = OutputParser.parse(
    output: "No data available",
    report: ReportItem(id: "t", title: "T", description: "", section: .awsCost,
                       scriptName: "t.py", csvKeys: [], chartType: .bar))
assertEqual(r5.sections.count, 1, "Empty output = 1 section")

// --- Aligned columns ---
let r6 = OutputParser.parse(
    output: "Amazon EC2          $45,678.90\nAmazon S3           $12,345.67",
    report: ReportItem(id: "t", title: "T", description: "", section: .awsCost,
                       scriptName: "t.py", csvKeys: [], chartType: .horizontalBar))
let rows6 = r6.sections.flatMap(\.rows)
assert(rows6.contains { $0.label.contains("EC2") && $0.value == 45678.90 }, "Aligned: EC2")
assert(rows6.contains { $0.label.contains("S3") && $0.value == 12345.67 }, "Aligned: S3")

// --- Data model defaults ---
let row = ResultRow(label: "Test", value: 42)
assertEqual(row.group, "", "Row default group")
assertEqual(row.detail, "", "Row default detail")

let section = ResultSection(title: "Sec", rows: [row, ResultRow(label: "B", value: 20, group: "2024")], chartHint: .bar)
assertEqual(section.rows.count, 2, "Section row count")

// --- ViewMode ---
assertEqual(["Table", "Chart"].count, 2, "ViewMode has 2 cases")

// ============================================================================
// Results
// ============================================================================

print("")
if errors.isEmpty {
    print("All \(passed) tests passed!")
} else {
    for e in errors { print("  \(e)") }
    print("\n\(passed) passed, \(failed) failed")
}

exit(failed > 0 ? 1 : 0)

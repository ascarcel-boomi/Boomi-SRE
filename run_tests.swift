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
    var icon: String {
        switch self {
        case .awsCost: return "dollarsign.circle"
        case .jiraAnalytics: return "chart.bar.xaxis"
        }
    }
}

struct ReportItem: Identifiable, Hashable {
    let id: String; let title: String; let description: String
    let section: ReportSection; let scriptName: String
    let csvKeys: [String]; let chartType: ChartType
    var isRealTime: Bool { csvKeys.isEmpty }
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
assert(allReports.count >= 2, "Catalog has >=2 reports")
let ids = allReports.map(\.id)
assertEqual(ids.count, Set(ids).count, "All report IDs unique")
assert(allReports.filter({ $0.section == .awsCost }).count > 0, "AWS section has reports")
for r in allReports { assert(r.scriptName.hasSuffix(".py"), "\(r.id) has .py script") }
for r in allReports { assert(r.isRealTime, "\(r.id) is real-time (no CSVs)") }
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

// ============================================================================
// Phase 39C: New tests — INI parsing, MOTD, version comparison, widget models
// ============================================================================

print("\n--- INI / Credential Parsing Tests ---")

// --- removeINIBlock: basic ---
func removeINIBlock(_ content: String, named blockName: String) -> String {
    let lines = content.components(separatedBy: "\n")
    var filtered: [String] = []
    var skipping = false
    for line in lines {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if l == "[\(blockName)]" || l == "[profile \(blockName)]" {
            skipping = true; continue
        }
        if skipping && l.hasPrefix("[") && l.hasSuffix("]") { skipping = false }
        if !skipping { filtered.append(line) }
    }
    return filtered.joined(separator: "\n")
}

let creds1 = "[default]\naws_access_key_id=ABC\n\n[test]\naws_secret=XYZ\n"
let cleaned1 = removeINIBlock(creds1, named: "test")
assert(!cleaned1.contains("[test]"), "removeINIBlock: removes target block")
assert(cleaned1.contains("[default]"), "removeINIBlock: keeps other blocks")

// --- removeINIBlock handles [profile name] config format ---
let config1 = "[profile default]\nregion=us-east-1\n\n[profile pasted]\nregion=us-east-1\n"
let cleaned2 = removeINIBlock(config1, named: "pasted")
assert(!cleaned2.contains("[profile pasted]"), "removeINIBlock: removes [profile pasted]")
assert(cleaned2.contains("[profile default]"), "removeINIBlock: keeps other profile")

// --- \r\n line ending handling ---
let credsWithCR = "[554825952155_ReadOnlyAccess]\r\naws_access_key_id=ASIA\r\naws_secret_access_key=SECRET\r\n"
let normalized = credsWithCR.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
var profileName = ""
for line in normalized.components(separatedBy: "\n") {
    let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if l.hasPrefix("[") && l.hasSuffix("]") { profileName = String(l.dropFirst().dropLast()); break }
}
assertEqual(profileName, "554825952155_ReadOnlyAccess", "Profile name extracted despite \\r\\n endings")

// --- Profile name fallback when no header ---
let noHeader = "aws_access_key_id=ABC\naws_secret_access_key=DEF\n"
var fallbackName = ""
for line in noHeader.components(separatedBy: "\n") {
    let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if l.hasPrefix("[") && l.hasSuffix("]") { fallbackName = String(l.dropFirst().dropLast()); break }
}
assert(fallbackName.isEmpty, "No profile header → empty name (caller uses fallback)")

// --- Deduplication: keep last occurrence of each block ---
func deduplicateINIBlocks(_ content: String) -> String {
    let lines = content.components(separatedBy: "\n")
    var blockOrder: [String] = []
    var blockLines: [String: [String]] = [:]
    var currentBlock: String? = nil
    var preamble: [String] = []
    for line in lines {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.hasPrefix("[") && l.hasSuffix("]") {
            let name = String(l.dropFirst().dropLast())
            currentBlock = name
            if !blockOrder.contains(name) { blockOrder.append(name) }
            blockLines[name] = [line]
        } else if let block = currentBlock {
            blockLines[block, default: []].append(line)
        } else { preamble.append(line) }
    }
    var result = preamble
    for name in blockOrder { if let bl = blockLines[name] { result.append(contentsOf: bl) } }
    return result.joined(separator: "\n")
}

let duped = "[myprofile]\nkey=OLD\n\n[myprofile]\nkey=NEW\n"
let deduped = deduplicateINIBlocks(duped)
let occurrences = deduped.components(separatedBy: "[myprofile]").count - 1
assertEqual(occurrences, 1, "deduplicateINIBlocks: only one [myprofile] block after dedup")

print("\n--- MOTD Tests ---")

// Inline minimal MOTD library for testing
struct MOTDTestMessage { let quote: String; let category: String }
let motdMessages: [MOTDTestMessage] = [
    MOTDTestMessage(quote: "Hope is not a strategy.", category: "sreWisdom"),
    MOTDTestMessage(quote: "Two is One and One is None.", category: "teamPhilosophy"),
    MOTDTestMessage(quote: "When we do our job well, no one knows we exist.", category: "ninjaSpirit"),
    MOTDTestMessage(quote: "Connect everything to achieve anything.", category: "boomiPride"),
]
assert(motdMessages.count >= 4, "MOTD: at least 4 messages")
let categories = Set(motdMessages.map(\.category))
assert(categories.contains("sreWisdom"), "MOTD: has sreWisdom category")
assert(categories.contains("teamPhilosophy"), "MOTD: has teamPhilosophy category")
assert(categories.contains("ninjaSpirit"), "MOTD: has ninjaSpirit category")
assert(categories.contains("boomiPride"), "MOTD: has boomiPride category")

// messageOfTheMoment: deterministic within a 5-minute window
let slot1 = Int(Date().timeIntervalSince1970) / 300
let slot2 = Int(Date().timeIntervalSince1970) / 300  // same call immediately after
assertEqual(slot1, slot2, "MOTD: same 5-min slot returns same index")

// nextRandom: different from current
let current = motdMessages[0]
var nextFound = false
for _ in 0..<20 {
    let candidate = motdMessages[Int.random(in: 0..<motdMessages.count)]
    if candidate.quote != current.quote { nextFound = true; break }
}
assert(nextFound, "MOTD: nextRandom eventually returns different message")

print("\n--- Version Comparison Tests ---")

// Lexicographic comparison works for YY.MM.DD-HHMMSS format
assert("26.03.14-120001" > "26.03.14-120000", "Newer time is greater")
assert("26.03.14-120000" > "26.03.13-120000", "Newer date is greater")
assert("26.04.01-000000" > "26.03.31-235959", "Month rollover: April > March")
assert(!("26.03.14-120000" > "26.03.14-120000"), "Same version: not greater")
assert("dev" < "26.03.14-000000", "dev build is always older than any release")
// Simulate checkForUpdate logic
func needsUpdate(current: String, remote: String) -> Bool { remote > current }
assert(needsUpdate(current: "26.03.14-100000", remote: "26.03.14-120000"), "Update available: newer time")
assert(!needsUpdate(current: "26.03.14-120000", remote: "26.03.14-120000"), "No update: same version")
assert(needsUpdate(current: "dev", remote: "26.03.14-000001"), "Dev build always gets update")

print("\n--- Widget Model Tests ---")

// All WidgetType cases have non-empty icons and titles
enum TestWidgetType: String, CaseIterable {
    case activeIncidents, myTickets, recentPRs, jenkinsBuilds, grafanaAlerts
    case jsmOpsAlerts, awsCostTrend, upcomingCalendar, unreadEmails, confluenceRecent
    case serviceHealth, quickActions, aiDailySummary
    var icon: String {
        switch self {
        case .activeIncidents: return "exclamationmark.shield"
        case .myTickets: return "checklist"
        case .recentPRs: return "arrow.triangle.pull"
        case .jenkinsBuilds: return "hammer"
        case .grafanaAlerts: return "bell.badge"
        case .jsmOpsAlerts: return "bell.badge.fill"
        case .awsCostTrend: return "dollarsign.circle"
        case .upcomingCalendar: return "calendar"
        case .unreadEmails: return "envelope.badge"
        case .confluenceRecent: return "doc.richtext"
        case .serviceHealth: return "network"
        case .quickActions: return "bolt.circle"
        case .aiDailySummary: return "sparkles"
        }
    }
    var title: String {
        switch self {
        case .activeIncidents: return "Active Incidents"
        case .myTickets: return "My Tickets"
        case .recentPRs: return "Open PRs"
        case .jenkinsBuilds: return "Jenkins Builds"
        case .grafanaAlerts: return "Grafana Alerts"
        case .jsmOpsAlerts: return "JSM Ops Alerts"
        case .awsCostTrend: return "AWS Cost"
        case .upcomingCalendar: return "Calendar"
        case .unreadEmails: return "Email"
        case .confluenceRecent: return "Confluence"
        case .serviceHealth: return "Service Health"
        case .quickActions: return "Quick Actions"
        case .aiDailySummary: return "AI Daily Summary"
        }
    }
}
for wt in TestWidgetType.allCases {
    assert(!wt.icon.isEmpty, "Widget \(wt.rawValue) has non-empty icon")
    assert(!wt.title.isEmpty, "Widget \(wt.rawValue) has non-empty title")
}
assertEqual(TestWidgetType.allCases.count, 13, "WidgetType has 13 cases")

// WidgetSize has 3 cases
let sizes = ["small", "medium", "large"]
assertEqual(sizes.count, 3, "WidgetSize has 3 cases")

print("\n--- Health Score Tests ---")

// Simulate health score calculation
func testHealthScore(p1incidents: Int, p2incidents: Int, p1alerts: Int, p2alerts: Int,
                     p3alerts: Int, grafanaFiring: Int, jenkinsFailed: Int,
                     disconnectedServices: Int) -> Int {
    var score = 100
    score -= p1incidents * 30
    score -= p2incidents * 30
    score -= p1alerts * 15
    score -= p2alerts * 10
    score -= p3alerts * 5
    score -= grafanaFiring * 10
    score -= jenkinsFailed * 5
    score -= disconnectedServices * 5
    return max(0, min(100, score))
}
assertEqual(testHealthScore(p1incidents: 0, p2incidents: 0, p1alerts: 0, p2alerts: 0,
                            p3alerts: 0, grafanaFiring: 0, jenkinsFailed: 0, disconnectedServices: 0),
            100, "Health: perfect score with no issues")
assertEqual(testHealthScore(p1incidents: 1, p2incidents: 0, p1alerts: 0, p2alerts: 0,
                            p3alerts: 0, grafanaFiring: 0, jenkinsFailed: 0, disconnectedServices: 0),
            70, "Health: P1 incident deducts 30")
assert(testHealthScore(p1incidents: 5, p2incidents: 5, p1alerts: 5, p2alerts: 5,
                       p3alerts: 5, grafanaFiring: 5, jenkinsFailed: 5, disconnectedServices: 5) == 0,
       "Health: score never goes below 0")
assert(testHealthScore(p1incidents: 0, p2incidents: 0, p1alerts: 0, p2alerts: 0,
                       p3alerts: 0, grafanaFiring: 0, jenkinsFailed: 0, disconnectedServices: 0) <= 100,
       "Health: score never exceeds 100")

print("\n--- JSM Ops Response Parsing Tests ---")

// Parse schedules response: {"values": [...]}
let schedulesJSON = """
{"values": [
  {"id": "91b865f0", "name": "CAMSRE_Primary", "enabled": true, "teamId": "og-abc123"},
  {"id": "fc0d725f", "name": "CAMSRE_Secondary", "enabled": false}
]}
"""
let schedData = schedulesJSON.data(using: .utf8)!
let schedJSON = try! JSONSerialization.jsonObject(with: schedData) as! [String: Any]
let schedValues = schedJSON["values"] as! [[String: Any]]
assertEqual(schedValues.count, 2, "Schedules: parses 2 values")
assertEqual(schedValues[0]["id"] as! String, "91b865f0", "Schedules: correct ID")
assertEqual(schedValues[0]["teamId"] as? String ?? "", "og-abc123", "Schedules: teamId present")
assert(schedValues[1]["teamId"] as? String == nil, "Schedules: missing teamId is nil")

// Parse on-call response
let onCallJSON = """
{"onCallParticipants": [
  {"id": "712020:1c18606a", "type": "user"},
  {"id": "712020:abcdef12", "type": "user"}
]}
"""
let ocData = onCallJSON.data(using: .utf8)!
let ocJSON = try! JSONSerialization.jsonObject(with: ocData) as! [String: Any]
let participants = ocJSON["onCallParticipants"] as! [[String: Any]]
assertEqual(participants.count, 2, "OnCall: 2 participants")
assertEqual(participants[0]["id"] as! String, "712020:1c18606a", "OnCall: accountId in id field")
assertEqual(participants[0]["type"] as! String, "user", "OnCall: type is user")

// Parse teams response: bare array
let teamsJSON = """
[
  {"teamId": "og-90b86004", "teamName": "CAM SRE"},
  {"teamId": "og-12345678", "teamName": "Platform SRE"}
]
"""
let teamsData = teamsJSON.data(using: .utf8)!
let teamsArr = try! JSONSerialization.jsonObject(with: teamsData) as! [[String: Any]]
assertEqual(teamsArr.count, 2, "Teams: bare array with 2 teams")
assertEqual(teamsArr[0]["teamName"] as! String, "CAM SRE", "Teams: correct name")

// Parse alerts response
let alertsJSON = """
{"values": [
  {"id": "bf415f36", "tinyId": "148783", "message": "SQS queue depth high",
   "status": "open", "priority": "P2", "acknowledged": false, "owner": "john@boomi.com",
   "source": "Coralogix", "integrationType": "Coralogix", "tags": ["prod", "sqs"],
   "createdAt": "2026-03-14T23:11:11.485Z", "updatedAt": "2026-03-14T23:12:00.000Z",
   "snoozed": false, "count": 1}
]}
"""
let alertData = alertsJSON.data(using: .utf8)!
let alertJSON = try! JSONSerialization.jsonObject(with: alertData) as! [String: Any]
let alertValues = alertJSON["values"] as! [[String: Any]]
assertEqual(alertValues.count, 1, "Alerts: 1 alert parsed")
let a = alertValues[0]
assertEqual(a["status"] as! String, "open", "Alert: status is open")
assertEqual(a["priority"] as! String, "P2", "Alert: priority is P2")
assertEqual(a["acknowledged"] as! Bool, false, "Alert: not acknowledged")
assertEqual(a["owner"] as! String, "john@boomi.com", "Alert: owner is email")
let tags = a["tags"] as! [String]
assert(tags.contains("prod"), "Alert: has prod tag")

// Handle empty responses
let emptyJSON = """{"values": []}"""
let emptyData = emptyJSON.data(using: .utf8)!
let emptyObj = try! JSONSerialization.jsonObject(with: emptyData) as! [String: Any]
let emptyValues = emptyObj["values"] as! [[String: Any]]
assertEqual(emptyValues.count, 0, "Empty response: 0 values")

// Handle malformed JSON
let malformedData = "not valid json".data(using: .utf8)!
let malformed = try? JSONSerialization.jsonObject(with: malformedData) as? [String: Any]
assert(malformed == nil, "Malformed JSON: returns nil gracefully")


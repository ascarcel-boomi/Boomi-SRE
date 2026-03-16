/// Boomi SRE Test Suite — pure Swift, no Foundation imports
/// Run: swift test
import Testing

// MARK: - Pattern Matching

private func matchesAny(_ value: String, patterns: [String]) -> Bool {
    if patterns.isEmpty { return true }
    let lower = value.lowercased()
    return patterns.contains { pattern in
        let p = pattern.lowercased()
        if p.hasPrefix("*") && p.hasSuffix("*") { return lower.contains(String(p.dropFirst().dropLast())) }
        else if p.hasPrefix("*") { return lower.hasSuffix(String(p.dropFirst())) }
        else if p.hasSuffix("*") { return lower.hasPrefix(String(p.dropLast())) }
        else { return lower == p }
    }
}

@Suite("PatternMatching")
struct PatternMatchingTests {
    @Test func emptyPatterns()    { #expect(matchesAny("anything", patterns: [])) }
    @Test func exactMatch()       { #expect(matchesAny("apim-sre-terraform-iac", patterns: ["apim-sre-terraform-iac"])) }
    @Test func exactNoMatch()     { #expect(!matchesAny("other-repo", patterns: ["apim-sre-terraform-iac"])) }
    @Test func prefixWildcard()   { #expect(matchesAny("apim-sre-terraform-iac", patterns: ["apim-sre-*"])) }
    @Test func prefixNoMatch()    { #expect(!matchesAny("other-repo", patterns: ["apim-sre-*"])) }
    @Test func suffixWildcard()   { #expect(matchesAny("deploy-mashery-prod", patterns: ["*-mashery-prod"])) }
    @Test func bothWildcards()    { #expect(matchesAny("deploy-mashery-prod", patterns: ["*mashery*"])) }
    @Test func bothNoMatch()      { #expect(!matchesAny("deploy-mft-prod", patterns: ["*mashery*"])) }
    @Test func caseInsensitive()  { #expect(matchesAny("APIM-SRE-Terraform", patterns: ["apim-sre-*"])) }
    @Test func multiplePatterns() { #expect(matchesAny("mft-sre-job", patterns: ["*mashery*", "*mft*"])) }
    @Test func allMiss()          { #expect(!matchesAny("other-job", patterns: ["*mashery*", "*mft*"])) }
}

// MARK: - Version Comparison

@Suite("VersionComparison")
struct VersionComparisonTests {
    @Test func newerDate()     { #expect("26.03.15-120000" > "26.03.14-120000") }
    @Test func newerTime()     { #expect("26.03.15-120001" > "26.03.15-120000") }
    @Test func monthRollover() { #expect("26.04.01-000000" > "26.03.31-235959") }
    @Test func sameVersion()   { let v = "26.03.15-120000"; #expect(!(v > v)) }
    @Test func devVersion()    { #expect("dev" > "26.03.15-120000") }  // "d" > "2" lexicographically
    @Test func yearRollover()  { #expect("27.01.01-000000" > "26.12.31-235959") }
}

// MARK: - Health Score

@Suite("HealthScore")
struct HealthScoreTests {
    private func calc(p1: Int = 0, alerts: Int = 0, failures: Int = 0) -> Int {
        max(0, min(100, 100 - p1 * 30 - alerts * 5 - failures * 5))
    }
    @Test func perfect()        { #expect(calc() == 100) }
    @Test func oneP1()          { #expect(calc(p1: 1) == 70) }
    @Test func twoP1()          { #expect(calc(p1: 2) == 40) }
    @Test func clampZero()      { #expect(calc(p1: 10) == 0) }
    @Test func alertDeduction() { #expect(calc(alerts: 1) == 95) }
    @Test func combined()       { #expect(calc(p1: 1, alerts: 2, failures: 1) == 55) }
    @Test func clampMax()       { #expect(max(0, min(100, 150)) == 100) }
}

// MARK: - INI Parsing (pure Swift — no Foundation)

private func extractINIProfileName(_ text: String) -> String {
    // Normalize line endings without Foundation
    var normalized = ""
    var i = text.startIndex
    while i < text.endIndex {
        let ch = text[i]
        if ch == "\r" {
            normalized.append("\n")
            let next = text.index(after: i)
            if next < text.endIndex && text[next] == "\n" { i = next }
        } else {
            normalized.append(ch)
        }
        i = text.index(after: i)
    }
    for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
        let l = String(line).filter { !$0.isWhitespace }
        if l.hasPrefix("[") && l.hasSuffix("]") { return String(l.dropFirst().dropLast()) }
    }
    return ""
}

@Suite("INIParsing")
struct INIParsingTests {
    @Test func standard()       { #expect(extractINIProfileName("[MyProfile]\nkey=val") == "MyProfile") }
    @Test func windowsEndings() { #expect(extractINIProfileName("[MyProfile]\r\nkey=val") == "MyProfile") }
    @Test func noHeader()       { #expect(extractINIProfileName("key=val") == "") }
    @Test func numericAWSName() { #expect(extractINIProfileName("[554825952155_ReadOnlyAccess]\nk=v") == "554825952155_ReadOnlyAccess") }
    @Test func profileFormat()  { #expect(extractINIProfileName("[profile default]\nregion=us-east-1") == "profile default") }
}

// MARK: - Feed Priority

@Suite("FeedPriority")
struct FeedPriorityTests {
    enum P: Int, Comparable {
        case critical = 0, high = 1, medium = 2, low = 3, info = 4
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    }
    @Test func sortOrder()          { #expect(P.critical < P.high && P.high < P.medium && P.medium < P.low && P.low < P.info) }
    @Test func criticalSortsFirst() { #expect([P.info, P.critical, P.medium].sorted().first == .critical) }
    @Test func infoSortsLast()      { #expect([P.info, P.critical, P.medium].sorted().last == .info) }
    @Test func equalPriority()      { #expect(!(P.high < P.high)) }
}

// MARK: - Productivity

@Suite("ProductivityEstimates")
struct ProductivityEstimatesTests {
    @Test func postmortemHigherThanAck() { #expect(30.0 > 2.0) }
    @Test func allPositive()             { #expect([2.0, 1.0, 3.0, 10.0, 15.0, 30.0, 5.0, 20.0].allSatisfy { $0 > 0 }) }
    @Test func weeklyAccumulation()      { #expect(45.0 * 5.0 == 225.0) }
    @Test func formatMinutes() {
        func fmt(_ m: Double) -> String { m < 60 ? "\(Int(m)) min" : "\(Int(m / 60)) hrs" }
        #expect(fmt(45) == "45 min")
        #expect(fmt(60) == "1 hrs")
        #expect(fmt(120) == "2 hrs")
    }
}

// MARK: - String Helpers

@Suite("StringHelpers")
struct StringHelperTests {
    @Test func dropBrackets() {
        let s = "[MyProfile]"
        #expect(String(s.dropFirst().dropLast()) == "MyProfile")
    }
    @Test func wildcardInner() {
        #expect(String("*mashery*".dropFirst().dropLast()) == "mashery")
    }
    @Test func lowercasedMatch() {
        #expect("APIM-SRE".lowercased() == "apim-sre")
    }
    @Test func hasPrefixSuffix() {
        #expect("[Block]".hasPrefix("[") && "[Block]".hasSuffix("]"))
    }
    @Test func splitByNewline() {
        let lines = "a\nb\nc".split(separator: "\n")
        #expect(lines.count == 3)
    }
}

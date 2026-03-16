# Boomi SRE App — Phase 55: Comprehensive Test Suite (No Xcode Required)

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. Tests run via `swift test` (SPM, no Xcode needed).

**Read these files first:**
- `Package.swift` — current test target configuration (BoomiSRETests in Tests/)
- `Tests/BoomiSRETests.swift` — currently empty placeholder
- `run_tests.swift` — existing CLI test runner (tests OutputParser only)
- All files in `BoomiSRE/Sources/Models/` — the 20 model files that contain testable logic
- `BoomiSRE/Sources/Services/AWSAuthService.swift` — INI parsing logic (removeINIBlock, addPortalCredentials)
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — file-based secrets store
- `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift` — buildFeed(), urgency scoring
- `BoomiSRE/Sources/Models/ProductContext.swift` — product filter matching
- `BoomiSRE/Sources/Models/ProductivityModels.swift` — time savings calculations

**Key constraint:** Tests must work with `swift test` — NO Xcode required. Use the `Testing` framework (Swift 5.9+) or `XCTest`. Since the app is an executable target (not a library), the test target imports `BoomiSRE` — verify this works. If importing the executable module causes issues (common with SwiftUI `@main`), the tests may need to use `@testable import` or test models/logic that are in separate files.

**Important note:** If `import BoomiSRE` fails in tests because the module is an executable with `@main`, the workaround is to either:
1. Extract testable logic into a separate library target
2. Or test using the standalone `run_tests.swift` pattern (no imports — redefine the types inline)

Try option 1 first. If it fails, fall back to expanding `run_tests.swift`.

---

## Implementation

### Phase 55A: Set Up the Test Infrastructure

1. **Try adding tests with `@testable import BoomiSRE`:**

```swift
// Tests/BoomiSRETests.swift
import Testing
@testable import BoomiSRE

@Suite("Boomi SRE Tests")
struct BoomiSRETests {
    @Test func placeholder() {
        #expect(true)
    }
}
```

Run `swift test`. If it compiles and the test passes, proceed with this approach.

2. **If the import fails** (common with executable targets), create a library target for testable code:

Update `Package.swift`:
```swift
let package = Package(
    name: "BoomiSRE",
    platforms: [.macOS("15.0")],
    targets: [
        // Library with all the business logic (models, services, view models)
        .target(
            name: "BoomiSRECore",
            path: "BoomiSRE/Sources",
            exclude: ["BoomiSREApp.swift"]  // exclude the @main entry point
        ),
        // Executable that just has the @main entry point
        .executableTarget(
            name: "BoomiSRE",
            dependencies: ["BoomiSRECore"],
            path: "BoomiSRE/App"  // create a minimal App/ dir with just the entry point
        ),
        // Tests import the library
        .testTarget(
            name: "BoomiSRETests",
            dependencies: ["BoomiSRECore"],
            path: "Tests"
        ),
    ]
)
```

This may require moving `BoomiSREApp.swift` to `BoomiSRE/App/` and having it `import BoomiSRECore`. This is a bigger refactor.

3. **If that's too complex, fall back to the standalone pattern:** Expand `run_tests.swift` with comprehensive tests that redefine types inline (like the existing `run_tests.swift` does). This is less elegant but guaranteed to work.

**Pick whichever approach compiles.** The tests themselves are the same regardless of approach.

### Phase 55B: Model Tests

```swift
// ── Product Context Tests ──────────────────────────────

@Suite("ProductContext")
struct ProductContextTests {
    @Test func defaultsHaveSixProducts() {
        #expect(ProductContext.defaults.count == 6)
    }

    @Test func allProductsHasEmptyFilters() {
        let all = ProductContext.defaults.first { $0.id == "all" }
        #expect(all != nil)
        #expect(all!.jsmTeamIds.isEmpty)
        #expect(all!.jiraProjectKeys.isEmpty)
    }

    @Test func camSREHasCorrectTeamId() {
        let cam = ProductContext.defaults.first { $0.id == "cam-sre" }
        #expect(cam != nil)
        #expect(cam!.jsmTeamIds.contains("og-90b86004-f391-4213-9742-3c0f47d8731b"))
        #expect(cam!.jiraProjectKeys.contains("CAMSRE"))
    }

    @Test func allProductsHaveRequiredFields() {
        for product in ProductContext.defaults {
            #expect(!product.id.isEmpty)
            #expect(!product.name.isEmpty)
            #expect(!product.shortName.isEmpty)
            #expect(!product.icon.isEmpty)
        }
    }
}

// ── Widget Model Tests ──────────────────────────────────

@Suite("WidgetModels")
struct WidgetModelTests {
    @Test func allWidgetTypesHaveTitlesAndIcons() {
        for type in WidgetType.allCases {
            #expect(!type.title.isEmpty, "WidgetType.\(type) has no title")
            #expect(!type.icon.isEmpty, "WidgetType.\(type) has no icon")
        }
    }

    @Test func defaultWidgetsCoverAllTypes() {
        let defaultTypes = Set(DashboardWidget.defaults.map(\.type))
        let allTypes = Set(WidgetType.allCases)
        let missing = allTypes.subtracting(defaultTypes)
        #expect(missing.isEmpty, "Missing widget types in defaults: \(missing)")
    }

    @Test func defaultWidgetsHaveUniquePositions() {
        let positions = DashboardWidget.defaults.map(\.position)
        #expect(positions.count == Set(positions).count, "Duplicate positions in widget defaults")
    }
}

// ── Incident Model Tests ────────────────────────────────

@Suite("IncidentModels")
struct IncidentModelTests {
    @Test func severityOrdering() {
        #expect(IncidentSeverity.p1.isActive)
        #expect(IncidentSeverity.p2.isActive)
        #expect(!IncidentSeverity.p3.isActive)
        #expect(!IncidentSeverity.p4.isActive)
    }

    @Test func statusResolved() {
        #expect(IncidentStatus.resolved.isResolved)
        #expect(!IncidentStatus.investigating.isResolved)
        #expect(!IncidentStatus.identified.isResolved)
        #expect(!IncidentStatus.monitoring.isResolved)
    }

    @Test func incidentElapsedString() {
        let incident = Incident(title: "Test", severity: .p2,
                               createdAt: Date().addingTimeInterval(-3700))
        #expect(incident.elapsedString.contains("h"))
    }
}

// ── MOTD Tests ──────────────────────────────────────────

@Suite("MOTD")
struct MOTDTests {
    @Test func libraryHasEnoughMessages() {
        #expect(MOTDLibrary.messages.count >= 40)
    }

    @Test func messageOfTheMomentReturnsValidMessage() {
        let msg = MOTDLibrary.messageOfTheMoment()
        #expect(!msg.quote.isEmpty)
        #expect(!msg.attribution.isEmpty)
        #expect(!msg.emoji.isEmpty)
    }

    @Test func allCategoriesHaveMessages() {
        for category in MOTDCategory.allCases {
            let count = MOTDLibrary.messages.filter { $0.category == category }.count
            #expect(count > 0, "Category \(category) has no messages")
        }
    }

    @Test func nextRandomExcludesCurrent() {
        let current = MOTDLibrary.messages[0]
        let next = MOTDLibrary.nextRandom(excluding: current)
        #expect(next.id != current.id)
    }
}

// ── Report Catalog Tests ────────────────────────────────

@Suite("ReportCatalog")
struct ReportCatalogTests {
    @Test func allReportsHaveUniqueIds() {
        let ids = ReportCatalog.all.map(\.id)
        #expect(ids.count == Set(ids).count, "Duplicate report IDs")
    }

    @Test func allReportsHaveIconsAndTitles() {
        for report in ReportCatalog.all {
            #expect(!report.title.isEmpty, "\(report.id) has no title")
            #expect(!report.icon.isEmpty, "\(report.id) has no icon")
        }
    }

    @Test func allSectionsHaveReports() {
        for section in ReportSection.allCases {
            let reports = ReportCatalog.reports(for: section)
            #expect(!reports.isEmpty, "Section \(section) has no reports")
        }
    }
}

// ── User Profile Tests ──────────────────────────────────

@Suite("UserProfile")
struct UserProfileTests {
    @Test func greetingChangesWithTime() {
        let profile = UserProfile()
        let greeting = profile.greeting
        // Should contain a time-based greeting
        let validPrefixes = ["Good morning", "Good afternoon", "Good evening"]
        #expect(validPrefixes.contains(where: { greeting.hasPrefix($0) }) || greeting.hasPrefix("Hello"))
    }

    @Test func experienceLevelHints() {
        #expect(!ExperienceLevel.junior.analysisDepthHint.isEmpty)
        #expect(!ExperienceLevel.senior.analysisDepthHint.isEmpty)
        #expect(ExperienceLevel.junior.analysisDepthHint != ExperienceLevel.senior.analysisDepthHint)
    }
}

// ── Productivity Model Tests ────────────────────────────

@Suite("ProductivityModels")
struct ProductivityModelTests {
    @Test func allActionsHavePositiveMinutes() {
        for action in ProductivityAction.allCases {
            #expect(action.estimatedMinutes > 0, "\(action) has 0 minutes")
        }
    }

    @Test func allActionsHaveCategories() {
        for action in ProductivityAction.allCases {
            #expect(!action.category.isEmpty, "\(action) has no category")
        }
    }

    @Test func highValueActionsAreCorrectlyEstimated() {
        #expect(ProductivityAction.aiPostmortemDraft.estimatedMinutes >= 20)
        #expect(ProductivityAction.aiPCRGeneration.estimatedMinutes >= 20)
        #expect(ProductivityAction.alertAcknowledged.estimatedMinutes <= 5)
    }
}
```

### Phase 55C: Service Logic Tests

```swift
// ── Feed Building Tests ─────────────────────────────────

@Suite("FeedBuilding")
struct FeedBuildingTests {
    @Test func feedPrioritySorting() {
        // Verify critical items sort before low items
        #expect(FeedPriority.critical < FeedPriority.high)
        #expect(FeedPriority.high < FeedPriority.medium)
        #expect(FeedPriority.medium < FeedPriority.low)
        #expect(FeedPriority.low < FeedPriority.info)
    }

    @Test func feedSourcesHaveIconsAndColors() {
        let sources: [FeedSource] = [.jsmAlert, .grafanaAlert, .incident, .jiraTicket,
                                      .githubPR, .jenkinsBuild, .onCall, .notification, .aiSummary]
        for source in sources {
            #expect(!source.icon.isEmpty, "\(source) has no icon")
            #expect(!source.rawValue.isEmpty, "\(source) has no display name")
        }
    }
}

// ── Notification Type Tests ─────────────────────────────

@Suite("NotificationTypes")
struct NotificationTypeTests {
    @Test func highPriorityTypes() {
        #expect(NotificationType.jiraAssigned.isHighPriority)
        #expect(NotificationType.jenkinsBuildFailed.isHighPriority)
        #expect(NotificationType.grafanaAlertFiring.isHighPriority)
        #expect(!NotificationType.jiraStatusChange.isHighPriority)
        #expect(!NotificationType.briefingGenerated.isHighPriority)
    }
}

// ── Version Comparison Tests (Update Service) ───────────

@Suite("VersionComparison")
struct VersionComparisonTests {
    @Test func newerVersionDetected() {
        #expect("26.03.15-120000" > "26.03.14-120000")
        #expect("26.03.15-120001" > "26.03.15-120000")
        #expect("26.04.01-000000" > "26.03.31-235959")
    }

    @Test func sameVersionNotDetected() {
        let v = "26.03.15-120000"
        #expect(!(v > v))
    }

    @Test func devVersionAlwaysGetsUpdates() {
        #expect("26.03.15-120000" > "dev")
    }
}

// ── INI Parsing Tests (AWS) ─────────────────────────────

@Suite("INIParsing")
struct INIParsingTests {
    @Test func profileNameExtraction() {
        let text = "[554825952155_ReadOnlyAccess]\naws_access_key_id=AKIA...\naws_secret_access_key=xxx"
        // Test that the profile name "554825952155_ReadOnlyAccess" is correctly extracted
        let lines = text.components(separatedBy: "\n")
        var profileName = "pasted"
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") && l.hasSuffix("]") {
                profileName = String(l.dropFirst().dropLast())
                break
            }
        }
        #expect(profileName == "554825952155_ReadOnlyAccess")
    }

    @Test func profileNameWithWindowsLineEndings() {
        let text = "[554825952155_ReadOnlyAccess]\r\naws_access_key_id=AKIA..."
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = cleaned.components(separatedBy: "\n")
        var profileName = "pasted"
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") && l.hasSuffix("]") {
                profileName = String(l.dropFirst().dropLast())
                break
            }
        }
        #expect(profileName == "554825952155_ReadOnlyAccess")
    }
}

// ── Pattern Matching Tests (Product Filtering) ──────────

@Suite("PatternMatching")
struct PatternMatchingTests {
    // Reimplement the matchesAny function for testing
    func matchesAny(_ value: String, patterns: [String]) -> Bool {
        if patterns.isEmpty { return true }
        let lower = value.lowercased()
        return patterns.contains { pattern in
            let p = pattern.lowercased()
            if p.hasPrefix("*") && p.hasSuffix("*") {
                return lower.contains(String(p.dropFirst().dropLast()))
            } else if p.hasPrefix("*") {
                return lower.hasSuffix(String(p.dropFirst()))
            } else if p.hasSuffix("*") {
                return lower.hasPrefix(String(p.dropLast()))
            } else {
                return lower == p
            }
        }
    }

    @Test func emptyPatternsMatchEverything() {
        #expect(matchesAny("anything", patterns: []))
    }

    @Test func exactMatch() {
        #expect(matchesAny("apim-sre-terraform-iac", patterns: ["apim-sre-terraform-iac"]))
        #expect(!matchesAny("other-repo", patterns: ["apim-sre-terraform-iac"]))
    }

    @Test func wildcardPrefix() {
        #expect(matchesAny("apim-sre-terraform-iac", patterns: ["apim-sre-*"]))
        #expect(!matchesAny("other-repo", patterns: ["apim-sre-*"]))
    }

    @Test func wildcardSuffix() {
        #expect(matchesAny("deploy-mashery-prod", patterns: ["*-mashery-prod"]))
        #expect(!matchesAny("deploy-mft-prod", patterns: ["*-mashery-prod"]))
    }

    @Test func wildcardBoth() {
        #expect(matchesAny("deploy-mashery-prod", patterns: ["*mashery*"]))
        #expect(matchesAny("mashery-deploy", patterns: ["*mashery*"]))
        #expect(!matchesAny("deploy-mft-prod", patterns: ["*mashery*"]))
    }

    @Test func caseInsensitive() {
        #expect(matchesAny("APIM-SRE-Terraform", patterns: ["apim-sre-*"]))
    }
}
```

### Phase 55D: Health Score Tests

```swift
@Suite("HealthScore")
struct HealthScoreTests {
    @Test func perfectScoreWhenNoIssues() {
        // With no incidents, no alerts, no failures → score should be 100
        var score = 100
        let incidents = 0
        let alerts = 0
        let failures = 0
        score -= incidents * 30
        score -= alerts * 5
        score -= failures * 5
        #expect(score == 100)
    }

    @Test func scoreDeductionsForP1() {
        var score = 100
        score -= 1 * 30  // 1 P1 incident
        #expect(score == 70)
    }

    @Test func scoreNeverBelowZero() {
        var score = 100
        score -= 5 * 30  // 5 P1 incidents = -150
        score = max(0, min(100, score))
        #expect(score == 0)
    }

    @Test func scoreNeverAbove100() {
        var score = 150  // somehow overflowed
        score = max(0, min(100, score))
        #expect(score == 100)
    }
}
```

### Phase 55E: Run Tests and Verify

1. Run `swift test` and verify all tests pass.
2. If any test fails, investigate and fix either the test or the code.
3. Add a note to `README.md` about running tests: `swift test` from the project root.
4. Update `run_tests.swift` if it's still used — or replace it entirely with the new test suite.

---

## Build & Release

After making all changes:
1. Run `swift test` to verify all tests pass.
2. Run `swift build -c release` to verify the release build compiles.
3. Commit with message: "Add comprehensive test suite — models, services, feed, health score, patterns"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.

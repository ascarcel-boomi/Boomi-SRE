import Foundation

// MARK: - Quadrant

/// The four quadrants of the Eisenhower Matrix.
enum Quadrant: String, CaseIterable, Sendable {
    case doFirst   = "Do First"
    case schedule  = "Schedule"
    case delegate  = "Delegate"
    case eliminate = "Eliminate"
}

// MARK: - EisenhowerItem

/// A classified Jira ticket ready for display in the Eisenhower Matrix.
struct EisenhowerItem: Identifiable, Sendable {
    let key: String
    let name: String
    let type: String
    let status: String
    let statusCategory: String
    let staleDays: Int?
    let sp: Double?
    let quarter: String
    let project: String
    let isDelegated: Bool
    let quadrant: Quadrant

    var id: String { key }
}

// MARK: - EisenhowerResult

/// The full output of a classification pass.
struct EisenhowerResult: Sendable {
    /// Top 3 items that need immediate attention (Q1 first, then Q3, then Q2).
    let focusNow: [EisenhowerItem]

    let doFirst: [EisenhowerItem]
    let schedule: [EisenhowerItem]
    let delegate: [EisenhowerItem]
    let eliminate: [EisenhowerItem]

    /// Jira keys of all nodes that belong to the current user's watchlist
    /// but are assigned to someone else (delegated items).
    let userNodeKeys: Set<String>

    var totalCount: Int {
        doFirst.count + schedule.count + delegate.count + eliminate.count
    }

    var isEmpty: Bool { totalCount == 0 }
}

// MARK: - EisenhowerClassifier

/// Pure, stateless classifier. Input → output, no side effects.
struct EisenhowerClassifier {

    // MARK: Constants

    static let plannedTypes: Set<String> = [
        "epic",
        "story",
        "deploy_req",
        "deployment request"
    ]

    static let unplannedTypes: Set<String> = [
        "task",
        "ops_req",
        "operational request",
        "troubleshoot",
        "troubleshooting",
        "access_req",
        "access request"
    ]

    static let staleDaysThreshold: Int = 14

    // MARK: Public API

    /// Walk the work-map node tree and classify every ticket for the given user.
    ///
    /// - Parameters:
    ///   - nodes: Top-level project nodes from the Work Map (project > epic > children).
    ///   - userDisplayName: The assignee display name to match against `WorkMapNode.assignee`.
    ///   - watchedKeys: Jira keys the user is watching (but may not own).
    ///   - currentQuarter: The active quarter label, e.g. `"Q2CY26"`.
    /// - Returns: A fully classified `EisenhowerResult`.
    static func classify(
        nodes: [WorkMapNode],
        userDisplayName: String,
        watchedKeys: Set<String>,
        currentQuarter: String
    ) -> EisenhowerResult {

        var doFirst:   [EisenhowerItem] = []
        var schedule:  [EisenhowerItem] = []
        var delegate:  [EisenhowerItem] = []
        var eliminate: [EisenhowerItem] = []
        var userNodeKeys: Set<String>   = []

        // Walk: project node → epic node → leaf children (and epics themselves)
        for projectNode in nodes {
            let project = projectNode.key  // e.g. "CAMSRE"

            for epicNode in projectNode.children {
                // Classify the epic itself
                classifyNode(
                    epicNode,
                    project: project,
                    userDisplayName: userDisplayName,
                    watchedKeys: watchedKeys,
                    currentQuarter: currentQuarter,
                    doFirst: &doFirst,
                    schedule: &schedule,
                    delegate: &delegate,
                    eliminate: &eliminate,
                    userNodeKeys: &userNodeKeys
                )

                // Classify each child under the epic
                for child in epicNode.children {
                    classifyNode(
                        child,
                        project: project,
                        userDisplayName: userDisplayName,
                        watchedKeys: watchedKeys,
                        currentQuarter: currentQuarter,
                        doFirst: &doFirst,
                        schedule: &schedule,
                        delegate: &delegate,
                        eliminate: &eliminate,
                        userNodeKeys: &userNodeKeys
                    )
                }
            }
        }

        // Sort each quadrant
        let sortedDoFirst   = doFirst.sorted   { staleDaysDesc($0, $1) }
        let sortedSchedule  = schedule.sorted  { spDesc($0, $1) }
        let sortedDelegate  = delegate.sorted  { staleDaysDesc($0, $1) }
        let sortedEliminate = eliminate  // no sort requirement specified

        // Focus Now: top 3 from Q1 first, then Q3, then Q2. Never Q4.
        let focusPool = sortedDoFirst + sortedDelegate + sortedSchedule
        let focusNow  = Array(focusPool.prefix(3))

        return EisenhowerResult(
            focusNow: focusNow,
            doFirst: sortedDoFirst,
            schedule: sortedSchedule,
            delegate: sortedDelegate,
            eliminate: sortedEliminate,
            userNodeKeys: userNodeKeys
        )
    }

    // MARK: Private helpers

    private static func classifyNode(
        _ node: WorkMapNode,
        project: String,
        userDisplayName: String,
        watchedKeys: Set<String>,
        currentQuarter: String,
        doFirst:   inout [EisenhowerItem],
        schedule:  inout [EisenhowerItem],
        delegate:  inout [EisenhowerItem],
        eliminate: inout [EisenhowerItem],
        userNodeKeys: inout Set<String>
    ) {
        // Skip completed tickets
        guard node.statusCategory.lowercased() != "done" else { return }

        let typeLower    = node.type.lowercased()
        let isPlanned    = plannedTypes.contains(typeLower)
        let isUnplanned  = unplannedTypes.contains(typeLower)
        let isAssigned   = node.assignee == userDisplayName
        let isWatched    = watchedKeys.contains(node.key)
        let stale        = computeStaleDays(updated: node.updated)

        // Track keys the user has any stake in
        if isAssigned || isWatched {
            userNodeKeys.insert(node.key)
        }

        // Rule: watched but NOT assigned → Q3 Delegate (isDelegated = true)
        if isWatched && !isAssigned {
            let item = EisenhowerItem(
                key: node.key, name: node.name, type: node.type,
                status: node.status, statusCategory: node.statusCategory,
                staleDays: stale, sp: node.sp, quarter: node.quarter,
                project: project, isDelegated: true, quadrant: .delegate
            )
            delegate.append(item)
            return
        }

        // Only classify items assigned to the user from here on
        guard isAssigned else { return }

        // Q1 — Do First
        // Assigned + planned type + in-progress (indeterminate) + (stale > 14 days OR quarter matches)
        if isPlanned &&
            node.statusCategory.lowercased() == "indeterminate" &&
            ((stale ?? 0) >= staleDaysThreshold || node.quarter.contains(currentQuarter)) {

            let item = makeItem(node, project: project, quadrant: .doFirst)
            doFirst.append(item)
            return
        }

        // Q2 — Schedule
        // Assigned + planned type + current quarter + not started (new) + has SP > 0
        if isPlanned &&
            node.quarter.contains(currentQuarter) &&
            node.statusCategory.lowercased() == "new" &&
            (node.sp ?? 0) > 0 {

            let item = makeItem(node, project: project, quadrant: .schedule)
            schedule.append(item)
            return
        }

        // Q3 — Delegate
        // Assigned + unplanned type
        if isUnplanned {
            let item = makeItem(node, project: project, quadrant: .delegate, isDelegated: false)
            delegate.append(item)
            return
        }

        // Q4 — Eliminate (everything else assigned to the user)
        let item = makeItem(node, project: project, quadrant: .eliminate)
        eliminate.append(item)
    }

    private static func makeItem(
        _ node: WorkMapNode,
        project: String,
        quadrant: Quadrant,
        isDelegated: Bool = false
    ) -> EisenhowerItem {
        EisenhowerItem(
            key: node.key,
            name: node.name,
            type: node.type,
            status: node.status,
            statusCategory: node.statusCategory,
            staleDays: computeStaleDays(updated: node.updated),
            sp: node.sp,
            quarter: node.quarter,
            project: project,
            isDelegated: isDelegated,
            quadrant: quadrant
        )
    }

    // MARK: Stale-days calculation

    /// Parses a Jira `updated` timestamp (e.g. `"2025-03-01T12:34:56.000+0000"`)
    /// and returns the number of calendar days elapsed since that date.
    /// Returns `nil` if the date prefix cannot be parsed.
    private static func computeStaleDays(updated: String) -> Int? {
        // Take only the "YYYY-MM-DD" prefix
        guard updated.count >= 10 else { return nil }
        let prefix = String(updated.prefix(10))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar   = calendar
        formatter.timeZone   = calendar.timeZone

        guard let date = formatter.date(from: prefix) else { return nil }

        let components = calendar.dateComponents([.day], from: date, to: Date())
        guard let days = components.day else { return nil }
        return max(0, days)
    }

    // MARK: Sort helpers

    private static func staleDaysDesc(_ a: EisenhowerItem, _ b: EisenhowerItem) -> Bool {
        let aDays = a.staleDays ?? 0
        let bDays = b.staleDays ?? 0
        return aDays > bDays
    }

    private static func spDesc(_ a: EisenhowerItem, _ b: EisenhowerItem) -> Bool {
        let aSP = a.sp ?? 0
        let bSP = b.sp ?? 0
        return aSP > bSP
    }
}

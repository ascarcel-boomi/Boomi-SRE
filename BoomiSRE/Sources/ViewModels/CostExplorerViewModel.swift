import Foundation
import SwiftUI

/// ViewModel for the AWS Cost Explorer view.
@MainActor
final class CostExplorerViewModel: ObservableObject {
    @Published var timeRange: CostTimeRange = .lastMonth
    @Published var groupBy: CostGroupBy = .service
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var costResult: CostResult?
    @Published var monthlyTotals: [CostPeriodTotal] = []
    @Published var forecast: Double = 0
    @Published var lastProfile: String = ""

    // Drill-down state (detail pane)
    @Published var drillDownResult: CostResult?
    @Published var drillDownName: String?
    @Published var isLoadingDrillDown = false
    @Published var drillDownError: String?

    private let costService  = AWSCostService()
    private let claudeService = ClaudeService()

    // MARK: - AI Analysis

    @Published var aiAnalysis: String?
    @Published var isAnalyzingCosts = false
    @Published var aiError: String?
    @Published var naturalLanguageQuery: String = ""

    /// Analyze the current cost data with Claude — trend, anomalies, and recommendations.
    func analyzeCosts() async {
        guard let result = costResult else { return }
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured. Add one in Settings."
            return
        }
        isAnalyzingCosts = true
        aiError = nil
        aiAnalysis = nil

        let costText = buildCostContext(result: result)
        let prompt = """
        You are an AWS cost analyst for Boomi's APIM SRE team. Analyze the following cost data and provide:

        1. **Cost Trend** — is spend going up, down, or stable across months? What's the trajectory?
        2. **Top Cost Drivers** — why are the top 3–5 services expensive? What's expected vs. surprising?
        3. **Anomalies** — flag any service with >20% month-over-month increase; explain the likely cause.
        4. **Optimization Recommendations** — 3–5 specific, actionable items (right-sizing, reserved instances, unused resources, savings plans). Include estimated savings where possible.

        Be specific: use actual service names and dollar amounts. Keep it under 400 words.

        \(costText)
        """
        do {
            aiAnalysis = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are a cloud cost optimization expert. Reference exact dollar amounts and service names. Be actionable.",
                maxTokens: 2048
            )
        } catch {
            aiError = error.localizedDescription
        }
        isAnalyzingCosts = false
    }

    /// Answer a free-form question about the current cost data.
    func askCostQuestion() async {
        let query = naturalLanguageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let result = costResult else { return }
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."
            return
        }
        naturalLanguageQuery = ""
        isAnalyzingCosts = true
        aiError = nil

        let costText = buildCostContext(result: result)
        let prompt = "\(costText)\n\nQuestion: \(query)"
        do {
            let answer = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an AWS cost analyst. Answer the question using the provided cost data. Be specific with dollar amounts.",
                maxTokens: 1024
            )
            if let existing = aiAnalysis {
                aiAnalysis = existing + "\n\n---\n\n**Q: \(query)**\n\n" + answer
            } else {
                aiAnalysis = "**Q: \(query)**\n\n" + answer
            }
        } catch {
            aiError = error.localizedDescription
        }
        isAnalyzingCosts = false
    }

    /// Format cost data for Claude context.
    func buildCostContext(result: CostResult) -> String {
        var lines = ["AWS Cost Data | Period: \(timeRange.rawValue) | Total: \(formatCurrency(result.totalCost))"]
        lines.append("\nTOP SERVICES:")
        for (i, item) in result.aggregated.prefix(15).enumerated() {
            let pct = result.totalCost > 0 ? (item.amount / result.totalCost) * 100 : 0
            lines.append("  \(i + 1). \(shortenServiceName(item.name)): \(formatCurrency(item.amount)) (\(String(format: "%.1f", pct))%)")
        }
        if monthlyTotals.count > 1 {
            lines.append("\nMONTHLY TREND:")
            for p in monthlyTotals { lines.append("  \(p.displayMonth): \(formatCurrency(p.amount))") }
        }
        if result.periods.count >= 2 {
            let prev = result.periods[result.periods.count - 2]
            let curr = result.periods[result.periods.count - 1]
            lines.append("\nMONTH-OVER-MONTH CHANGES:")
            for item in result.aggregated.prefix(10) {
                let prevAmt = prev.items.first(where: { $0.name == item.name })?.amount ?? 0
                let currAmt = curr.items.first(where: { $0.name == item.name })?.amount ?? 0
                guard prevAmt > 1 else { continue }
                let pct = ((currAmt - prevAmt) / prevAmt) * 100
                let sign = pct >= 0 ? "+" : ""
                lines.append("  \(shortenServiceName(item.name)): \(sign)\(String(format: "%.1f", pct))% (\(formatCurrency(prevAmt)) → \(formatCurrency(currAmt)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Fetch cost data for the given profile and current settings.
    func fetch(profile: String) {
        guard !profile.isEmpty else {
            errorMessage = "No AWS profile selected. Choose one in Settings."
            return
        }
        isLoading = true
        errorMessage = nil
        lastProfile = profile

        let range = timeRange.dateRange
        let groupBy = self.groupBy
        let timeRange = self.timeRange

        Task {
            do {
                // Fetch grouped cost data + monthly trend in parallel
                async let grouped = costService.getCostAndUsage(
                    profile: profile,
                    startDate: range.start,
                    endDate: range.end,
                    granularity: .monthly,
                    groupBy: groupBy
                )

                // For trend, always fetch monthly totals for the selected range
                async let totals = costService.getTotalCost(
                    profile: profile,
                    startDate: range.start,
                    endDate: range.end,
                    granularity: .monthly
                )

                // Forecast: only for multi-month ranges
                async let fc = fetchForecast(profile: profile, timeRange: timeRange)

                let (groupedResult, totalsResult, forecastResult) = try await (grouped, totals, fc)

                self.costResult = groupedResult
                self.monthlyTotals = totalsResult
                self.forecast = forecastResult
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func fetchForecast(profile: String, timeRange: CostTimeRange) async -> Double {
        // Only show forecast for ranges that include recent data
        guard timeRange != .lastMonth else { return 0 }
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let startOfNextMonth = cal.date(byAdding: .month, value: 1, to: startOfThisMonth)!
        let start = fmt.string(from: startOfThisMonth)
        let end = fmt.string(from: startOfNextMonth)
        return (try? await costService.getCostForecast(
            profile: profile, startDate: start, endDate: end
        )) ?? 0
    }

    // MARK: - Drill-down

    /// Fetch a secondary breakdown for the selected row.
    /// - Service view → drill down by Region
    /// - Region view → drill down by Service
    /// - Linked Account view → drill down by Service
    func fetchDrillDown(name: String) {
        guard !lastProfile.isEmpty else { return }

        // If same item already loaded, skip
        if drillDownName == name && drillDownResult != nil { return }

        drillDownName = name
        drillDownResult = nil
        drillDownError = nil
        isLoadingDrillDown = true

        let range = timeRange.dateRange
        let filterDim = groupBy
        let secondaryGroup: CostGroupBy
        switch groupBy {
        case .service: secondaryGroup = .region
        case .region: secondaryGroup = .service
        case .linkedAccount: secondaryGroup = .service
        }

        Task {
            do {
                let result = try await costService.getCostAndUsageFiltered(
                    profile: lastProfile,
                    startDate: range.start,
                    endDate: range.end,
                    granularity: .monthly,
                    filterDimension: filterDim,
                    filterValue: name,
                    groupBy: secondaryGroup
                )
                self.drillDownResult = result
                self.isLoadingDrillDown = false
            } catch {
                self.drillDownError = error.localizedDescription
                self.isLoadingDrillDown = false
            }
        }
    }

    /// Clear drill-down when selection changes.
    func clearDrillDown() {
        drillDownName = nil
        drillDownResult = nil
        drillDownError = nil
        isLoadingDrillDown = false
    }

    /// Label for the secondary dimension in drill-down.
    var drillDownGroupLabel: String {
        switch groupBy {
        case .service: return "Region"
        case .region: return "Service"
        case .linkedAccount: return "Service"
        }
    }

    // MARK: - Table display rows

    /// Build sortable display rows from the aggregated cost data.
    func displayRows() -> [CostDisplayRow] {
        guard let result = costResult else { return [] }
        let total = result.totalCost
        return result.aggregated.map { item in
            let pct = total > 0 ? (item.amount / total) * 100 : 0
            // Per-month breakdown for this item
            var monthly: [CostDisplayRow.MonthAmount] = []
            for period in result.periods {
                if let match = period.items.first(where: { $0.name == item.name }) {
                    monthly.append(.init(month: period.displayMonth, amount: match.amount))
                } else {
                    monthly.append(.init(month: period.displayMonth, amount: 0))
                }
            }
            return CostDisplayRow(
                name: item.name,
                amount: item.amount,
                percentOfTotal: pct,
                monthlyBreakdown: monthly
            )
        }
    }

    // MARK: - Convert to ResultSection for chart reuse

    /// Top N services/regions as a horizontal bar chart section.
    func topItemsSection(limit: Int = 15) -> ResultSection? {
        guard let result = costResult else { return nil }
        let items = Array(result.aggregated.prefix(limit))
        guard !items.isEmpty else { return nil }
        let rows = items.map { item in
            ResultRow(label: shortenServiceName(item.name),
                      value: item.amount,
                      detail: formatCurrency(item.amount))
        }
        return ResultSection(title: "Top \(rows.count) by \(groupBy.label)",
                             rows: rows, chartHint: .horizontalBar)
    }

    /// Monthly trend as a line/bar chart section.
    func trendSection() -> ResultSection? {
        guard !monthlyTotals.isEmpty, monthlyTotals.count > 1 else { return nil }
        let rows = monthlyTotals.map { period in
            ResultRow(label: period.displayMonth,
                      value: period.amount,
                      detail: formatCurrency(period.amount))
        }
        return ResultSection(title: "Monthly Trend", rows: rows, chartHint: .bar)
    }

    /// Per-period breakdown with group labels (for stacked view).
    func periodBreakdownSections(topN: Int = 10) -> [ResultSection] {
        guard let result = costResult, result.periods.count > 1 else { return [] }
        return result.periods.map { period in
            let rows = Array(period.items.prefix(topN)).map { item in
                ResultRow(label: shortenServiceName(item.name),
                          value: item.amount,
                          group: period.displayMonth,
                          detail: formatCurrency(item.amount))
            }
            return ResultSection(title: period.displayMonth,
                                 rows: rows, chartHint: .horizontalBar)
        }
    }

    // MARK: - Formatting

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    func formatCurrency(_ v: Double) -> String {
        if v >= 1_000_000 {
            return String(format: "$%.2fM", v / 1_000_000)
        }
        return Self.currencyFormatter.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    /// Shorten verbose AWS service names for chart labels.
    func shortenServiceName(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "Amazon ", with: "")
        s = s.replacingOccurrences(of: "AWS ", with: "")
        s = s.replacingOccurrences(of: "Elastic Compute Cloud - Compute", with: "EC2")
        s = s.replacingOccurrences(of: "Elastic Load Balancing", with: "ELB")
        s = s.replacingOccurrences(of: "Relational Database Service", with: "RDS")
        s = s.replacingOccurrences(of: "Simple Storage Service", with: "S3")
        s = s.replacingOccurrences(of: "Simple Notification Service", with: "SNS")
        s = s.replacingOccurrences(of: "Simple Queue Service", with: "SQS")
        s = s.replacingOccurrences(of: "CloudWatch", with: "CW")
        return s
    }
}

// MARK: - Table display model

/// A row for the sortable cost table. Uses `name` as stable identity.
struct CostDisplayRow: Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
    let percentOfTotal: Double
    let monthlyBreakdown: [MonthAmount]

    struct MonthAmount: Identifiable {
        var id: String { month }
        let month: String
        let amount: Double
    }
}

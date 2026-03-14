import Foundation

/// Native Swift client for AWS Cost Explorer — shells out to `aws ce` CLI commands.
actor AWSCostService {

    // MARK: - Cost and Usage

    /// Fetch cost and usage data grouped by a dimension.
    func getCostAndUsage(
        profile: String,
        startDate: String,
        endDate: String,
        granularity: CostGranularity = .monthly,
        groupBy: CostGroupBy = .service
    ) async throws -> CostResult {
        let args = [
            "ce", "get-cost-and-usage",
            "--profile", profile,
            "--time-period", "Start=\(startDate),End=\(endDate)",
            "--granularity", granularity.rawValue,
            "--metrics", "BlendedCost",
            "--group-by", "Type=DIMENSION,Key=\(groupBy.rawValue)",
            "--output", "json",
        ]
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else {
            throw AWSCostError.cliFailed(output)
        }
        return try parseCostAndUsage(output, groupBy: groupBy)
    }

    /// Fetch cost data with a dimension filter, grouped by a secondary dimension.
    /// e.g. filter SERVICE="EC2", group by REGION.
    func getCostAndUsageFiltered(
        profile: String,
        startDate: String,
        endDate: String,
        granularity: CostGranularity = .monthly,
        filterDimension: CostGroupBy,
        filterValue: String,
        groupBy: CostGroupBy
    ) async throws -> CostResult {
        // Build the --filter JSON
        let filterJSON = """
        {"Dimensions":{"Key":"\(filterDimension.rawValue)","Values":["\(filterValue)"]}}
        """
        let args = [
            "ce", "get-cost-and-usage",
            "--profile", profile,
            "--time-period", "Start=\(startDate),End=\(endDate)",
            "--granularity", granularity.rawValue,
            "--metrics", "BlendedCost",
            "--filter", filterJSON,
            "--group-by", "Type=DIMENSION,Key=\(groupBy.rawValue)",
            "--output", "json",
        ]
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else {
            throw AWSCostError.cliFailed(output)
        }
        return try parseCostAndUsage(output, groupBy: groupBy)
    }

    /// Fetch total cost (ungrouped) for a time period.
    func getTotalCost(
        profile: String,
        startDate: String,
        endDate: String,
        granularity: CostGranularity = .monthly
    ) async throws -> [CostPeriodTotal] {
        let args = [
            "ce", "get-cost-and-usage",
            "--profile", profile,
            "--time-period", "Start=\(startDate),End=\(endDate)",
            "--granularity", granularity.rawValue,
            "--metrics", "BlendedCost",
            "--output", "json",
        ]
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else {
            throw AWSCostError.cliFailed(output)
        }
        return try parseTotalCost(output)
    }

    /// Fetch a cost forecast for the upcoming period.
    func getCostForecast(
        profile: String,
        startDate: String,
        endDate: String,
        granularity: CostGranularity = .monthly
    ) async throws -> Double {
        let args = [
            "ce", "get-cost-forecast",
            "--profile", profile,
            "--time-period", "Start=\(startDate),End=\(endDate)",
            "--granularity", granularity.rawValue,
            "--metric", "BLENDED_COST",
            "--output", "json",
        ]
        let (output, exitCode) = try await runAWS(args)
        guard exitCode == 0 else {
            return 0  // Forecast may fail for accounts with insufficient history
        }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = json["Total"] as? [String: Any],
              let amount = total["Amount"] as? String,
              let value = Double(amount) else { return 0 }
        return value
    }

    // MARK: - Parsing

    private func parseCostAndUsage(_ output: String, groupBy: CostGroupBy) throws -> CostResult {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultsByTime = json["ResultsByTime"] as? [[String: Any]] else {
            throw AWSCostError.parseError
        }

        var periods: [CostPeriod] = []

        for period in resultsByTime {
            guard let timePeriod = period["TimePeriod"] as? [String: String],
                  let start = timePeriod["Start"],
                  let end = timePeriod["End"] else { continue }

            let estimated = period["Estimated"] as? Bool ?? false
            var items: [CostItem] = []

            if let groups = period["Groups"] as? [[String: Any]] {
                for group in groups {
                    guard let keys = group["Keys"] as? [String],
                          let key = keys.first,
                          let metrics = group["Metrics"] as? [String: Any],
                          let blended = metrics["BlendedCost"] as? [String: Any],
                          let amountStr = blended["Amount"] as? String,
                          let amount = Double(amountStr) else { continue }

                    // Skip negligible costs (< $0.01)
                    if abs(amount) < 0.01 { continue }

                    items.append(CostItem(name: key, amount: amount))
                }
            }

            // Sort by cost descending
            items.sort { $0.amount > $1.amount }

            periods.append(CostPeriod(
                startDate: start, endDate: end,
                estimated: estimated, items: items
            ))
        }

        return CostResult(periods: periods, groupBy: groupBy)
    }

    private func parseTotalCost(_ output: String) throws -> [CostPeriodTotal] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultsByTime = json["ResultsByTime"] as? [[String: Any]] else {
            throw AWSCostError.parseError
        }

        return resultsByTime.compactMap { period in
            guard let timePeriod = period["TimePeriod"] as? [String: String],
                  let start = timePeriod["Start"],
                  let total = period["Total"] as? [String: Any],
                  let blended = total["BlendedCost"] as? [String: Any],
                  let amountStr = blended["Amount"] as? String,
                  let amount = Double(amountStr) else { return nil }
            let estimated = period["Estimated"] as? Bool ?? false
            return CostPeriodTotal(startDate: start, amount: amount, estimated: estimated)
        }
    }

    // Delegates to shared AWSCLIRunner.run() — see Extensions/AWSCLIRunner.swift
    private func runAWS(_ args: [String]) async throws -> (String, Int32) {
        let result = try await AWSCLIRunner.run(arguments: args)
        return (result.output, result.exitCode)
    }
}

// MARK: - Models

struct CostResult {
    let periods: [CostPeriod]
    let groupBy: CostGroupBy

    /// Aggregate all periods into a single list of items, summed by name.
    var aggregated: [CostItem] {
        var totals: [String: Double] = [:]
        for period in periods {
            for item in period.items {
                totals[item.name, default: 0] += item.amount
            }
        }
        return totals.map { CostItem(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var totalCost: Double {
        aggregated.reduce(0) { $0 + $1.amount }
    }
}

struct CostPeriod: Identifiable {
    let id = UUID()
    let startDate: String
    let endDate: String
    let estimated: Bool
    let items: [CostItem]

    var total: Double { items.reduce(0) { $0 + $1.amount } }

    /// Format start date as "Jan 2025" for display.
    var displayMonth: String {
        let parts = startDate.split(separator: "-")
        guard parts.count >= 2,
              let month = Int(parts[1]) else { return startDate }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let idx = month - 1
        guard idx >= 0 && idx < 12 else { return startDate }
        return "\(months[idx]) \(parts[0])"
    }
}

struct CostPeriodTotal: Identifiable {
    let id = UUID()
    let startDate: String
    let amount: Double
    let estimated: Bool

    var displayMonth: String {
        let parts = startDate.split(separator: "-")
        guard parts.count >= 2, let month = Int(parts[1]) else { return startDate }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let idx = month - 1
        guard idx >= 0 && idx < 12 else { return startDate }
        return "\(months[idx]) \(parts[0])"
    }
}

struct CostItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
}

enum CostGranularity: String, CaseIterable {
    case daily = "DAILY"
    case monthly = "MONTHLY"
}

enum CostGroupBy: String, CaseIterable {
    case service = "SERVICE"
    case region = "REGION"
    case linkedAccount = "LINKED_ACCOUNT"

    var label: String {
        switch self {
        case .service: return "Service"
        case .region: return "Region"
        case .linkedAccount: return "Linked Account"
        }
    }
}

enum CostTimeRange: String, CaseIterable {
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case last6Months = "Last 6 Months"
    case yearToDate = "Year to Date"
    case last12Months = "Last 12 Months"

    /// Returns (startDate, endDate) formatted as YYYY-MM-DD.
    var dateRange: (start: String, end: String) {
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        // End date is always the 1st of this month (CE uses exclusive end)
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let end = fmt.string(from: startOfThisMonth)

        let start: Date
        switch self {
        case .lastMonth:
            start = cal.date(byAdding: .month, value: -1, to: startOfThisMonth)!
        case .last3Months:
            start = cal.date(byAdding: .month, value: -3, to: startOfThisMonth)!
        case .last6Months:
            start = cal.date(byAdding: .month, value: -6, to: startOfThisMonth)!
        case .yearToDate:
            start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!
        case .last12Months:
            start = cal.date(byAdding: .month, value: -12, to: startOfThisMonth)!
        }
        return (fmt.string(from: start), end)
    }
}

enum AWSCostError: LocalizedError {
    case cliFailed(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .cliFailed(let output):
            // Extract the most useful part of the error
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("ExpiredTokenException") || trimmed.contains("expired") {
                return "AWS session expired. Re-authenticate in Settings or sidebar."
            }
            if trimmed.contains("AccessDeniedException") || trimmed.contains("not authorized") {
                return "Access denied. This profile may not have Cost Explorer permissions (ce:GetCostAndUsage)."
            }
            return "AWS CLI error:\n\(String(trimmed.prefix(500)))"
        case .parseError:
            return "Failed to parse AWS Cost Explorer response."
        }
    }
}

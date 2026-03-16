import Foundation
import SwiftUI

// MARK: - BPOP Pillar

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

// MARK: - Metric Unit

enum MetricUnit: String, Codable, CaseIterable {
    case percent    = "%"
    case count      = "#"
    case minutes    = "min"
    case hours      = "hrs"
    case days       = "days"
    case currency   = "$"
    case number     = ""
    case ratio      = "x"
}

// MARK: - Metric Status

enum MetricStatus: String {
    case onTrack  = "On Track"
    case atRisk   = "At Risk"
    case offTrack = "Off Track"
    case noData   = "No Data"

    var color: Color {
        switch self {
        case .onTrack:  return .green
        case .atRisk:   return .yellow
        case .offTrack: return .red
        case .noData:   return .secondary
        }
    }

    var icon: String {
        switch self {
        case .onTrack:  return "checkmark.circle.fill"
        case .atRisk:   return "exclamationmark.triangle.fill"
        case .offTrack: return "xmark.circle.fill"
        case .noData:   return "questionmark.circle"
        }
    }
}

// MARK: - Metric Data Source

enum MetricDataSource: String, Codable, CaseIterable {
    case jira      = "Jira"
    case grafana   = "Grafana"
    case manual    = "Manual"
    case aws       = "AWS"
    case pagerduty = "PagerDuty"
    case github    = "GitHub"
    case jenkins   = "Jenkins"
}

// MARK: - BPOP Metric

/// Direction: `.higherIsBetter` means progress = current/target (higher is good).
/// `.lowerIsBetter` means progress = (2 - current/target).clamp(0,1).
enum MetricDirection: String, Codable {
    case higherIsBetter
    case lowerIsBetter
}

struct BPOPMetric: Identifiable, Codable {
    let id: String
    let pillar: BPOPPillar
    let name: String
    let description: String
    let unit: MetricUnit
    let target: Double
    let direction: MetricDirection
    let dataSource: MetricDataSource
    var currentValue: Double?
    var lastUpdated: Date?

    // MARK: Computed

    /// Progress 0.0 … 1.0 toward the target.
    var progressPercent: Double {
        guard let current = currentValue, target != 0 else { return 0 }
        switch direction {
        case .higherIsBetter:
            return min(current / target, 1.0)
        case .lowerIsBetter:
            // 0% = at or above target (bad), 100% = at 0 (perfect)
            // Linearly interpolate: at 0 → 100%, at target → 50%, at 2×target → 0%
            let ratio = current / target
            return max(0, min(1, 1.0 - (ratio / 2.0)))
        }
    }

    var status: MetricStatus {
        guard currentValue != nil else { return .noData }
        let p = progressPercent
        if p >= 0.9 { return .onTrack }
        if p >= 0.7 { return .atRisk }
        return .offTrack
    }

    var formattedCurrent: String {
        guard let v = currentValue else { return "—" }
        switch unit {
        case .percent:  return String(format: "%.1f%%", v)
        case .currency: return String(format: "$%.0f", v)
        case .number, .count: return String(format: "%.0f", v)
        case .ratio:    return String(format: "%.2fx", v)
        case .minutes:  return String(format: "%.0f min", v)
        case .hours:    return String(format: "%.1f hrs", v)
        case .days:     return String(format: "%.0f days", v)
        }
    }

    var formattedTarget: String {
        switch unit {
        case .percent:  return String(format: "%.1f%%", target)
        case .currency: return String(format: "$%.0f", target)
        case .number, .count: return String(format: "%.0f", target)
        case .ratio:    return String(format: "%.2fx", target)
        case .minutes:  return String(format: "%.0f min", target)
        case .hours:    return String(format: "%.1f hrs", target)
        case .days:     return String(format: "%.0f days", target)
        }
    }
}

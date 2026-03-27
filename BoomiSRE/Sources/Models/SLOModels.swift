import Foundation
import SwiftUI

// MARK: - SLO Category

enum SLOCategory: String, Codable, CaseIterable, Identifiable {
    case availability = "Availability"
    case latency      = "Latency"
    case errorRate    = "Error Rate"
    case throughput   = "Throughput"
    case custom       = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .availability: return "checkmark.shield"
        case .latency:      return "gauge.with.needle"
        case .errorRate:    return "xmark.octagon"
        case .throughput:   return "arrow.up.arrow.down"
        case .custom:       return "slider.horizontal.3"
        }
    }

    var defaultColor: Color {
        switch self {
        case .availability: return .green
        case .latency:      return .blue
        case .errorRate:    return .red
        case .throughput:   return .orange
        case .custom:       return .purple
        }
    }
}

// MARK: - SLO Health Status

enum SLOHealthStatus: Equatable {
    case healthy            // SLI meets target, budget > 50%
    case warning            // Budget 10–50% or SLI near target
    case critical           // Budget < 10% or SLI below target
    case noData
    case error(String)

    var color: Color {
        switch self {
        case .healthy:  return .green
        case .warning:  return .orange
        case .critical: return .red
        case .noData:   return .secondary
        case .error:    return .red
        }
    }

    var icon: String {
        switch self {
        case .healthy:  return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .noData:   return "questionmark.circle"
        case .error:    return "exclamationmark.triangle"
        }
    }

    var label: String {
        switch self {
        case .healthy:      return "Healthy"
        case .warning:      return "Warning"
        case .critical:     return "Critical"
        case .noData:       return "No Data"
        case .error(let m): return "Error: \(m.prefix(50))"
        }
    }
}

// MARK: - SLO Definition (persisted)

/// User-configurable SLO — stored in config.
struct SLODefinition: Identifiable, Codable, Hashable {
    var id: String
    var name: String                // "CAM API Availability"
    var sloDescription: String      // "Measures 2xx success rate..."
    var productId: String           // "cam-sre", "mft-sre", etc.
    var target: Double              // 0.999 = 99.9%
    var windowDays: Int             // 7, 28, or 30
    var metricQuery: String         // PromQL that returns 0..1 ratio
    var category: SLOCategory
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, sloDescription, productId, target, windowDays
        case metricQuery, category, enabled
    }

    init(id: String = UUID().uuidString, name: String, sloDescription: String = "",
         productId: String, target: Double = 0.999, windowDays: Int = 30,
         metricQuery: String = "", category: SLOCategory = .availability, enabled: Bool = true) {
        self.id = id; self.name = name; self.sloDescription = sloDescription
        self.productId = productId; self.target = target; self.windowDays = windowDays
        self.metricQuery = metricQuery; self.category = category; self.enabled = enabled
    }
}

// MARK: - SLO Status (computed at runtime)

/// Live SLO state — not persisted.
struct SLOStatus: Identifiable {
    let id: String                      // same as definition.id
    let definition: SLODefinition
    let currentSLI: Double?             // 0..1, nil if query failed
    let health: SLOHealthStatus
    let errorBudgetRemainingPct: Double  // 0..100
    let burnRate: Double                 // 1.0 = on track, >1 = burning faster than expected
    let lastUpdated: Date
    let queryError: String?
}

// MARK: - SLO Template (built-in presets)

struct SLOTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: SLOCategory
    let defaultTarget: Double
    let defaultWindowDays: Int
    let metricQueryTemplate: String     // with {service} placeholder

    static let builtIn: [SLOTemplate] = [
        SLOTemplate(
            name: "HTTP Availability",
            description: "Success rate of HTTP requests (2xx / total)",
            category: .availability,
            defaultTarget: 0.999,
            defaultWindowDays: 30,
            metricQueryTemplate: "sum(rate(http_requests_total{service=\"{service}\",code=~\"2..\"}[5m])) / sum(rate(http_requests_total{service=\"{service}\"}[5m]))"
        ),
        SLOTemplate(
            name: "Latency P99 < 500ms",
            description: "99th percentile latency below threshold",
            category: .latency,
            defaultTarget: 0.99,
            defaultWindowDays: 30,
            metricQueryTemplate: "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"{service}\"}[5m])) by (le)) < 0.5"
        ),
        SLOTemplate(
            name: "Error Rate < 1%",
            description: "Percentage of requests returning 5xx errors",
            category: .errorRate,
            defaultTarget: 0.99,
            defaultWindowDays: 30,
            metricQueryTemplate: "1 - (sum(rate(http_requests_total{service=\"{service}\",code=~\"5..\"}[5m])) / sum(rate(http_requests_total{service=\"{service}\"}[5m])))"
        ),
        SLOTemplate(
            name: "Uptime (Probe Success)",
            description: "Blackbox probe success rate",
            category: .availability,
            defaultTarget: 0.999,
            defaultWindowDays: 30,
            metricQueryTemplate: "avg_over_time(probe_success{instance=\"{service}\"}[5m])"
        ),
    ]
}

import Foundation

@MainActor
final class ProductivityTracker: ObservableObject {
    static let shared = ProductivityTracker()

    @Published var events: [ProductivityEvent] = []

    private let storageURL: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        storageURL = home.appendingPathComponent(".boomi_sre_productivity.json")
        loadEvents()
    }

    func log(_ action: ProductivityAction, detail: String = "", source: String = "") {
        let event = ProductivityEvent(
            action: action,
            detail: detail.isEmpty ? action.rawValue : detail,
            estimatedMinutesSaved: action.estimatedMinutes,
            source: source
        )
        events.append(event)
        saveEvents()
    }

    var minutesSavedToday: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return events.filter { $0.timestamp >= startOfDay }.reduce(0) { $0 + $1.estimatedMinutesSaved }
    }

    var minutesSavedThisWeek: Double {
        let startOfWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return events.filter { $0.timestamp >= startOfWeek }.reduce(0) { $0 + $1.estimatedMinutesSaved }
    }

    var minutesSavedThisMonth: Double {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let startOfMonth = Calendar.current.date(from: comps) ?? Date()
        return events.filter { $0.timestamp >= startOfMonth }.reduce(0) { $0 + $1.estimatedMinutesSaved }
    }

    var timeSavedTodayFormatted: String {
        let mins = minutesSavedToday
        if mins < 60 { return "\(Int(mins)) min" }
        let hours = mins / 60
        if hours < 10 { return String(format: "%.1f hrs", hours) }
        return "\(Int(hours)) hrs"
    }

    var actionsToday: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return events.filter { $0.timestamp >= startOfDay }.count
    }

    var todayByCategory: [(category: String, minutes: Double, count: Int)] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayEvents = events.filter { $0.timestamp >= startOfDay }
        let grouped = Dictionary(grouping: todayEvents) { $0.action.category }
        return grouped.map { (category: $0.key, minutes: $0.value.reduce(0) { $0 + $1.estimatedMinutesSaved }, count: $0.value.count) }
            .sorted { $0.minutes > $1.minutes }
    }

    var weeklyTrend: [(date: Date, minutes: Double)] {
        let cal = Calendar.current
        return (0..<7).reversed().map { daysAgo in
            let date = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let mins = events.filter { $0.timestamp >= start && $0.timestamp < end }
                .reduce(0) { $0 + $1.estimatedMinutesSaved }
            return (date: start, minutes: mins)
        }
    }

    func resetAll() {
        events = []
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func loadEvents() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ProductivityEvent].self, from: data) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        events = decoded.filter { $0.timestamp >= cutoff }
    }

    private func saveEvents() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

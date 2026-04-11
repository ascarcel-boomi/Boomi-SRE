import Foundation

// MARK: - Centralized Formatters
//
// DateFormatter is expensive to create. Shared static instances avoid
// repeated allocations in view bodies and service methods.

enum Formatters {
    /// Short date + short time (e.g., "3/14/26, 9:30 AM")
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    /// Medium date + short time (e.g., "Mar 14, 2026, 9:30 AM")
    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    /// Long date + short time (e.g., "March 14, 2026 at 9:30 AM")
    static let longDateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .short; return f
    }()

    /// Short date only (e.g., "3/14/26")
    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    /// Medium date only (e.g., "Mar 14, 2026")
    static let mediumDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    /// Full date (e.g., "Sunday, March 14, 2026")
    static let fullDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none; return f
    }()

    /// Time only (e.g., "9:30 AM")
    static let timeOnly: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    /// "MMM d" — abbreviated month + day (e.g., "Mar 14")
    static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    /// "EEE" — abbreviated weekday (e.g., "Sun")
    static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    /// "yyyy-MM-dd" — ISO date only (e.g., "2026-03-14")
    static let isoDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    /// Standard ISO 8601 (with timezone)
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); return f
    }()

    /// Relative date (e.g., "2 hours ago")
    nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
}

import Foundation

/// Shared error type for API service auth checks.
enum ServiceError: LocalizedError {
    case httpError(service: String, status: Int, body: String)
    case invalidURL(String)
    case parseError(service: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let service, let status, let body):
            return "\(service) returned HTTP \(status):\n\(body.prefix(300))"
        case .invalidURL(let detail):
            return "Invalid URL: \(detail)"
        case .parseError(let service, let detail):
            return "\(service): failed to parse response — \(detail)"
        }
    }
}

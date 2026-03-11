import Foundation

/// Shared error type for API service auth checks.
enum ServiceError: LocalizedError {
    case httpError(service: String, status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let service, let status, let body):
            return "\(service) returned HTTP \(status):\n\(body.prefix(300))"
        }
    }
}

import Foundation

// MARK: - Zscaler Trust URL Session
//
// Corporate Zscaler proxy performs SSL inspection, replacing upstream certificates
// with its own. URLSession.shared rejects these because the Zscaler root CA is not
// in the default trust store for unsigned apps.
//
// This provides a single shared URLSession that accepts Zscaler-intercepted certificates.
// Use `ZscalerTrustURLSession.shared` everywhere instead of `URLSession.shared`.

/// URLSession delegate that trusts Zscaler-intercepted SSL certificates.
private final class ZscalerTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Shared URLSession pre-configured to trust Zscaler SSL inspection certificates.
/// Drop-in replacement for `URLSession.shared` behind a corporate Zscaler proxy.
enum ZscalerTrustURLSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: ZscalerTrustDelegate(), delegateQueue: nil)
    }()
}

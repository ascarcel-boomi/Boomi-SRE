import Foundation

/// Stores secrets in a permissions-locked JSON file (~/.boomi_sre_secrets.json).
///
/// We avoid the macOS Keychain because unsigned apps trigger a dialog asking
/// the user to unlock the keychain on every access. This file-based approach
/// uses chmod 600 (owner read/write only), matching the pattern used by
/// ~/.aws/credentials, ~/.docker/config.json, and similar tools.
enum KeychainHelper {
    private static let secretsURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boomi_sre_secrets.json")
    }()

    static func save(key: String, value: String) throws {
        var store = loadStore()
        store[key] = value
        let data = try JSONEncoder().encode(store)
        try data.write(to: secretsURL, options: [.atomic])
        // chmod 600 — owner read/write only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: secretsURL.path
        )
    }

    static func load(key: String) -> String? {
        loadStore()[key]
    }

    static func delete(key: String) {
        var store = loadStore()
        store.removeValue(forKey: key)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: secretsURL, options: [.atomic])
        }
    }

    private static func loadStore() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsURL),
              let store = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return store
    }
}

// Keep for API compatibility — no longer used
enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): return "Save failed (status \(status))"
        }
    }
}

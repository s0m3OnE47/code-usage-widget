import Foundation
import Security

/// Keychain-backed secret storage. Service is fixed; each secret is an
/// account (e.g. `deepseek.api_key`). Resolution order everywhere:
/// Keychain → inline config → environment.
///
/// Reads are cached in memory for the life of the process: without this,
/// every 30s poll re-hits the Keychain and macOS re-prompts for any item
/// the user hasn't "Always Allow"ed (prompt storm).
enum KeychainStore {
    static let service = "com.anakin.code-usage-widget"

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]
    /// Keys known absent/denied this launch. Without negative caching, a
    /// denied item re-prompts on EVERY poll (prompt storm); with it, at
    /// most once per launch. Cleared by `clearCache()` (Reload Secrets).
    private static var negatives: Set<String> = []

    @discardableResult
    static func set(_ value: String, key: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let ok = SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
            if ok { setCached(value, key: key) }
            return ok
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        if ok { setCached(value, key: key) }
        return ok
    }

    static func get(key: String) -> String? {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        if negatives.contains(key) { lock.unlock(); return nil }
        lock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty
        else {
            lock.lock(); negatives.insert(key); lock.unlock()
            return nil
        }
        setCached(s, key: key)
        return s
    }

    /// Drop the in-memory cache (e.g. after migrating or deleting secrets,
    /// or adding keys outside the app). Next read hits the Keychain again.
    static func clearCache() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
        negatives.removeAll()
    }

    private static func cached(key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    private static func setCached(_ value: String, key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = value
        negatives.remove(key)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

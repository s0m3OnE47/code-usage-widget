import Foundation
import AppKit

enum ConfigLoader {
    static let configDir = NSHomeDirectory() + "/.config/code-usage-widget"
    static let configPath = configDir + "/config.json"
    static let appSupportDir = NSHomeDirectory() + "/Library/Application Support/CodeUsageWidget"
    static let windowPath = appSupportDir + "/window.json"

    static func load() -> WidgetConfig {
        let (config, warnings) = loadWithWarnings()
        for w in warnings { NSLog("[CodeUsageWidget] Config: \(w)") }
        return config
    }

    /// Load config plus non-secret validation warnings (surfaced in UI/logs).
    static func loadWithWarnings() -> (WidgetConfig, [String]) {
        ensureDirectories()
        hardenPermissionsIfNeeded()
        var warnings: [String] = []
        if hasInsecureConfigPermissions {
            warnings.append("config.json is group/other-readable — fixing to 0600")
        }
        guard FileManager.default.fileExists(atPath: configPath),
              let data = FileManager.default.contents(atPath: configPath) else {
            return (.default, warnings)
        }
        do {
            let decoder = JSONDecoder()
            var config = try decoder.decode(WidgetConfig.self, from: data)
            // Clamp + validate (never log secret values).
            if config.pollIntervalSeconds < 10 || config.pollIntervalSeconds > 3600 {
                warnings.append("poll_interval_seconds out of range (10–3600) — clamped")
                config.pollIntervalSeconds = min(max(config.pollIntervalSeconds, 10), 3600)
            }
            let known = Set(ProviderID.allCases.map(\.rawValue))
            for id in config.disabledProviders where !known.contains(id) {
                warnings.append("unknown disabled_providers entry: \(id)")
            }
            return (config, warnings)
        } catch {
            NSLog("[CodeUsageWidget] Config parse error: \(error)")
            return (.default, warnings + ["config.json failed to parse — using defaults"])
        }
    }

    static func loadWindowPosition() -> NSPoint? {
        ensureDirectories()
        guard let data = FileManager.default.contents(atPath: windowPath),
              let pos = try? JSONDecoder().decode(WindowPosition.self, from: data) else {
            return nil
        }
        return NSPoint(x: pos.x, y: pos.y)
    }

    static func saveWindowPosition(_ origin: NSPoint) {
        ensureDirectories()
        let pos = WindowPosition(x: origin.x, y: origin.y)
        if let data = try? JSONEncoder().encode(pos) {
            FileManager.default.createFile(atPath: windowPath, contents: data)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: windowPath)
        }
    }

    static func env(_ name: String) -> String? {
        let v = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    static func resolveAPIKey(configured: String?, envName: String) -> String? {
        if let configured, !configured.isEmpty { return configured }
        return env(envName)
    }

    /// Keychain → inline → env. `keychainKey` is e.g. `deepseek.api_key`.
    static func resolveSecret(configured: String?, keychainKey: String, envName: String, useKeychain: Bool = true) -> String? {
        if useKeychain, let v = KeychainStore.get(key: keychainKey), !v.isEmpty { return v }
        if let configured, !configured.isEmpty { return configured }
        return env(envName)
    }

    /// Move non-empty inline secrets into the Keychain and rewrite
    /// config.json with them redacted. Returns number of migrated fields.
    /// Never logs secret values.
    @discardableResult
    static func migrateSecretsToKeychain() -> Int {
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var providers = json["providers"] as? [String: Any]
        else { return 0 }
        var migrated = 0
        func move(_ provider: String, _ field: String, keychainKey: String) {
            guard var p = providers[provider] as? [String: Any],
                  let v = p[field] as? String,
                  !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            if KeychainStore.set(v, key: keychainKey) {
                p[field] = ""
                providers[provider] = p
                migrated += 1
            }
        }
        move("deepseek", "api_key", keychainKey: "deepseek.api_key")
        move("openai", "api_key", keychainKey: "openai.api_key")
        move("openai", "admin_key", keychainKey: "openai.admin_key")
        move("openai", "session_key", keychainKey: "openai.session_key")
        move("openai", "session_token_0", keychainKey: "openai.session_token_0")
        move("openai", "session_token_1", keychainKey: "openai.session_token_1")
        move("openai", "access_token", keychainKey: "openai.access_token")
        move("sarvam", "api_key", keychainKey: "sarvam.api_key")
        move("sarvam", "session_token", keychainKey: "sarvam.session_token")
        move("opencode", "api_key", keychainKey: "opencode.api_key")
        move("opencode", "session_token", keychainKey: "opencode.session_token")
        move("commandcode", "session_token", keychainKey: "commandcode.session_token")
        move("anthropic", "api_key", keychainKey: "anthropic.api_key")
        move("gemini", "api_key", keychainKey: "gemini.api_key")
        move("xai", "api_key", keychainKey: "xai.api_key")
        move("copilot", "github_token", keychainKey: "copilot.github_token")
        move("openrouter", "api_key", keychainKey: "openrouter.api_key")
        guard migrated > 0 else { return 0 }
        json["providers"] = providers
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
            NSLog("[CodeUsageWidget] Migrated %d secrets to Keychain", migrated)
        }
        return migrated
    }

    private static func ensureDirectories() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Harden pre-existing dirs (createDirectory with attributes is a no-op if present).
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDir)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appSupportDir)
    }

    /// Reduce exposure of plaintext secrets: config.json regularly holds
    /// api_key / session_key / session_token values. Best-effort chmod 0600.
    private static func hardenPermissionsIfNeeded() {
        guard FileManager.default.fileExists(atPath: configPath) else { return }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: configPath),
           let perms = attrs[.posixPermissions] as? NSNumber,
           perms.intValue & 0o077 != 0 {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
            NSLog("[CodeUsageWidget] Hardened config.json permissions to 0600")
        }
    }

    /// True when config.json is group/other-readable — surfaced in UI/logs.
    static var hasInsecureConfigPermissions: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: configPath),
              let perms = attrs[.posixPermissions] as? NSNumber else { return false }
        return perms.intValue & 0o077 != 0
    }
}

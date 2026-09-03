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

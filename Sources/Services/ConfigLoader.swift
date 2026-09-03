import Foundation
import AppKit

enum ConfigLoader {
    static let configDir = NSHomeDirectory() + "/.config/code-usage-widget"
    static let configPath = configDir + "/config.json"
    static let appSupportDir = NSHomeDirectory() + "/Library/Application Support/CodeUsageWidget"
    static let windowPath = appSupportDir + "/window.json"

    static func load() -> WidgetConfig {
        ensureDirectories()
        hardenPermissionsIfNeeded()
        guard FileManager.default.fileExists(atPath: configPath),
              let data = FileManager.default.contents(atPath: configPath) else {
            return .default
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WidgetConfig.self, from: data)
        } catch {
            NSLog("[CodeUsageWidget] Config parse error: \(error)")
            return .default
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

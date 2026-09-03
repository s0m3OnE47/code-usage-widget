import Foundation
import AppKit

enum ConfigLoader {
    static let configDir = NSHomeDirectory() + "/.config/code-usage-widget"
    static let configPath = configDir + "/config.json"
    static let appSupportDir = NSHomeDirectory() + "/Library/Application Support/CodeUsageWidget"
    static let windowPath = appSupportDir + "/window.json"

    static func load() -> WidgetConfig {
        ensureDirectories()
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
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)
    }
}

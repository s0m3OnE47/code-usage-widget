import Foundation

enum UsageCache {
    static let appGroupID = "group.com.anakin.code-usage-widget"
    private static let fileName = "usage-snapshot.json"
    private static let widgetBundleID = "com.anakin.code-usage-widget.widget"

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = encode(snapshot) else { return }
        for url in writeURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("[CodeUsageWidget] Failed to save snapshot at \(url.path): \(error)")
            }
        }
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(data, forKey: "snapshot")
            defaults.synchronize()
        }
    }

    static func load() -> UsageSnapshot? {
        if let defaults = UserDefaults(suiteName: appGroupID),
           let data = defaults.data(forKey: "snapshot"),
           let snapshot = decode(data),
           !snapshot.providers.isEmpty {
            return snapshot
        }

        for url in readURLs() {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let snapshot = decode(data),
                  !snapshot.providers.isEmpty else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private static func encode(_ snapshot: UsageSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    private static func decode(_ data: Data) -> UsageSnapshot? {
        try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    private static func writeURLs() -> [URL] {
        uniqueURLs([
            appGroupURL,
            userApplicationSupportURL,
            widgetContainerURL,
        ].compactMap { $0 })
    }

    private static func readURLs() -> [URL] {
        uniqueURLs([
            appGroupURL,
            userApplicationSupportURL,
            widgetContainerURL,
            sandboxedApplicationSupportURL,
        ].compactMap { $0 })
    }

    private static var appGroupURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Real ~/Library/Application Support — not the sandbox container.
    private static var userApplicationSupportURL: URL? {
        realUserHome()?
            .appendingPathComponent("Library/Application Support/CodeUsageWidget")
            .appendingPathComponent(fileName)
    }

    private static var widgetContainerURL: URL? {
        realUserHome()?
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/CodeUsageWidget")
            .appendingPathComponent(fileName)
    }

    private static var sandboxedApplicationSupportURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/CodeUsageWidget")
            .appendingPathComponent(fileName)
    }

    private static func realUserHome() -> URL? {
        if let pw = getpwuid(getuid()) {
            let path = String(cString: pw.pointee.pw_dir)
            if !path.isEmpty, !path.contains("/Library/Containers/") {
                return URL(fileURLWithPath: path)
            }
        }
        let user = NSUserName()
        if !user.isEmpty {
            return URL(fileURLWithPath: "/Users/\(user)")
        }
        return nil
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

import Foundation

/// Append-only usage history (host only, never synced to widget).
/// JSONL at Application Support: `{t, id, pct, used, limit}` per poll.
enum HistoryStore {
    static let fileName = "history.jsonl"
    static let maxLines = 5000

    struct Point: Codable {
        let t: TimeInterval
        let id: String
        let pct: Double
        let used: Double
        let limit: Double
    }

    static var fileURL: URL? {
        let dir = NSHomeDirectory() + "/Library/Application Support/CodeUsageWidget"
        return URL(fileURLWithPath: dir).appendingPathComponent(fileName)
    }

    static func record(_ providers: [ProviderUsage], at date: Date = Date()) {
        guard let url = fileURL, !providers.isEmpty else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var lines = ""
        let enc = JSONEncoder()
        for p in providers {
            // Skip placeholders / errors without meaningful data.
            guard p.limit > 0, p.status != .loading else { continue }
            let pt = Point(t: date.timeIntervalSince1970, id: p.id.rawValue,
                           pct: p.percentUsed, used: p.used, limit: p.limit)
            if let d = try? enc.encode(pt), let s = String(data: d, encoding: .utf8) {
                lines += s + "\n"
            }
        }
        guard !lines.isEmpty, let data = lines.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let fh = try? FileHandle(forWritingTo: url) {
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
                try? fh.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        pruneIfNeeded()
    }

    /// Last `hours` of percent-used points for a provider, ascending by time.
    static func series(for id: ProviderID, hours: Double = 24) -> [(Date, Double)] {
        guard let url = fileURL,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let cutoff = Date().addingTimeInterval(-hours * 3600).timeIntervalSince1970
        let dec = JSONDecoder()
        var out: [(Date, Double)] = []
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let pt = try? dec.decode(Point.self, from: d),
                  pt.id == id.rawValue, pt.t >= cutoff
            else { continue }
            out.append((Date(timeIntervalSince1970: pt.t), pt.pct))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private static func pruneIfNeeded() {
        guard let url = fileURL,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxLines else { return }
        lines.removeFirst(lines.count - maxLines)
        try? lines.joined(separator: "\n").appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }
}

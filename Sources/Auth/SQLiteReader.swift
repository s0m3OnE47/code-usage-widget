import Foundation
import SQLite3

/// Minimal read-only SQLite helper using bound parameters.
/// Replaces shelling out to `/usr/bin/sqlite3` with string-interpolated SQL.
enum SQLiteReader {
    /// Run a SELECT and return rows as string arrays. Non-text columns -> empty string.
    static func query(dbPath: String, sql: String, params: [String] = []) -> [[String]] {
        var db: OpaquePointer?
        // Read-only: never mutate the source copy; immutable avoids WAL sidecars.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, p) in params.enumerated() {
            // SQLITE_TRANSIENT so SQLite copies the string.
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = p.withCString { cstr in
                sqlite3_bind_text(stmt, Int32(i + 1), cstr, -1, transient)
            }
        }

        var rows: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cols = sqlite3_column_count(stmt)
            var row: [String] = []
            for c in 0..<cols {
                if let ptr = sqlite3_column_text(stmt, c) {
                    row.append(String(cString: ptr))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Escape `%`, `_`, `\` for use inside a LIKE pattern.
    static func escapeLike(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if ch == "%" || ch == "_" || ch == "\\" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Allow-list for cookie names / prefixes coming from config.
    /// Rejects control chars, quotes, semicolons, and path separators.
    static func isSafeCookieName(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func isSafeHost(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 253 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

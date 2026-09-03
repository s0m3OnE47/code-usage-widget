import Foundation

enum CursorTokenReader {
    private static let stateDB = NSHomeDirectory()
        + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    static func extractAccessToken() async -> String? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: stateDB) else { return nil }
            let tmp = "/tmp/cuw_cursor_\(ProcessInfo.processInfo.processIdentifier).vscdb"
            let cp = Process()
            cp.executableURL = URL(fileURLWithPath: "/bin/cp")
            cp.arguments = [stateDB, tmp]
            try? cp.run()
            cp.waitUntilExit()
            guard cp.terminationStatus == 0 else { return nil }
            defer { try? FileManager.default.removeItem(atPath: tmp) }

            let sql = Process()
            sql.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            sql.arguments = [tmp, "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken';"]
            let pipe = Pipe()
            sql.standardOutput = pipe
            try? sql.run()
            sql.waitUntilExit()
            let token = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (token?.isEmpty == false) ? token : nil
        }.value
    }
}

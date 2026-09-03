import Foundation

enum CursorTokenReader {
    private static let stateDB = NSHomeDirectory()
        + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    static func extractAccessToken() async -> String? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: stateDB) else { return nil }
            let rows: [[String]]? = SecureTempFile.withSecureCopy(sourcePath: stateDB, prefix: "cuw_cursor") { tmp in
                SQLiteReader.query(
                    dbPath: tmp,
                    sql: "SELECT value FROM ItemTable WHERE key=?;",
                    params: ["cursorAuth/accessToken"]
                )
            }
            guard let rows else { return nil }
            let token = rows.first?.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (token?.isEmpty == false) ? token : nil
        }.value
    }
}

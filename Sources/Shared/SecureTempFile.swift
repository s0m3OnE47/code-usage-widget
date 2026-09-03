import Foundation

/// Helper for creating securely-permissioned temporary copies of
/// browser / app databases. Replaces predictable `/tmp/cuw_*_PID`
/// paths with UUID names + 0600 permissions.
enum SecureTempFile {
    /// Copy a file to a 0600 temp file. Returns the temp path or nil.
    /// Caller is responsible for removing the file (see `withSecureCopy`).
    static func copyToTemp(sourcePath: String, prefix: String) -> String? {
        let tmpDir = FileManager.default.temporaryDirectory
        let dest = tmpDir
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).sqlite")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: dest.path)
            // Lock down: owner read/write only, even if umask is permissive.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: dest.path
            )
            return dest.path
        } catch {
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
    }

    /// Copy `sourcePath` to a secure temp file, run `body`, then securely remove.
    static func withSecureCopy<T>(sourcePath: String, prefix: String, body: (String) -> T) -> T? {
        guard let tmp = copyToTemp(sourcePath: sourcePath, prefix: prefix) else { return nil }
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        return body(tmp)
    }
}

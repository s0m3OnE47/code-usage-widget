import Foundation

enum Browser: String, Codable {
    case auto
    case firefox
    case chrome
}

enum BrowserCookieReader {
    static func cookie(
        name: String,
        host: String,
        browser: Browser,
        firefoxProfile: String,
        manualValue: String? = nil
    ) async -> String? {
        if let manual = manualValue?.trimmingCharacters(in: .whitespacesAndNewlines), !manual.isEmpty {
            return manual
        }
        guard SQLiteReader.isSafeCookieName(name), SQLiteReader.isSafeHost(host) else { return nil }

        switch browser {
        case .firefox:
            return await firefoxCookie(name: name, host: host, profilePath: firefoxProfile)
        case .chrome:
            return await chromeCookie(name: name, host: host)
        case .auto:
            if let ff = await firefoxCookie(name: name, host: host, profilePath: firefoxProfile) {
                return ff
            }
            return await chromeCookie(name: name, host: host)
        }
    }

    static func cookieHeader(name: String, value: String) -> String {
        "\(name)=\(value)"
    }

    /// Reads NextAuth-style chunked cookies (`name.0`, `name.1`, …) and returns a full Cookie header.
    static func chunkedCookieHeader(
        prefix: String,
        host: String,
        browser: Browser,
        firefoxProfile: String
    ) async -> String? {
        let parts = await chunkedCookieParts(prefix: prefix, host: host, browser: browser, firefoxProfile: firefoxProfile)
        guard !parts.isEmpty else { return nil }
        return parts.map { cookieHeader(name: $0.name, value: $0.value) }.joined(separator: "; ")
    }

    /// Returns ordered chunk cookies for a prefix (e.g. session-token.0, session-token.1).
    static func chunkedCookieParts(
        prefix: String,
        host: String,
        browser: Browser,
        firefoxProfile: String
    ) async -> [(name: String, value: String)] {
        guard SQLiteReader.isSafeCookieName(prefix), SQLiteReader.isSafeHost(host) else { return [] }
        switch browser {
        case .firefox:
            return await firefoxChunkedCookies(prefix: prefix, host: host, profilePath: firefoxProfile)
        case .chrome:
            return await chromeChunkedCookies(prefix: prefix, host: host)
        case .auto:
            let ff = await firefoxChunkedCookies(prefix: prefix, host: host, profilePath: firefoxProfile)
            if !ff.isEmpty { return ff }
            return await chromeChunkedCookies(prefix: prefix, host: host)
        }
    }

    /// Concatenates chunked session values into one token string.
    static func combinedChunkedValue(parts: [(name: String, value: String)]) -> String? {
        guard !parts.isEmpty else { return nil }
        let sorted = parts.sorted { lhs, rhs in
            chunkIndex(of: lhs.name) < chunkIndex(of: rhs.name)
        }
        let combined = sorted.map(\.value).joined()
        return combined.isEmpty ? nil : combined
    }

    private static func chunkIndex(of name: String) -> Int {
        guard let dot = name.lastIndex(of: ".") else { return 0 }
        let suffix = name[name.index(after: dot)...]
        return Int(suffix) ?? 0
    }

    private static func firefoxChunkedCookies(
        prefix: String,
        host: String,
        profilePath configured: String
    ) async -> [(name: String, value: String)] {
        await Task.detached(priority: .utility) {
            guard let profile = resolveFirefoxProfile(configured: configured) else { return [] }
            let db = profile + "/cookies.sqlite"
            guard FileManager.default.fileExists(atPath: db) else { return [] }

            let likePattern = SQLiteReader.escapeLike(prefix) + ".%"
            let sql = "SELECT name, value FROM moz_cookies WHERE (name=? OR name LIKE ? ESCAPE '\\') AND host=? ORDER BY name;"
            var results: [(String, String)] = []
            for h in hostVariants(host) {
                let rows: [[String]]? = SecureTempFile.withSecureCopy(sourcePath: db, prefix: "cuw_ff") { tmp in
                    SQLiteReader.query(dbPath: tmp, sql: sql, params: [prefix, likePattern, h])
                }
                guard let rows else { continue }
                for cols in rows where cols.count >= 2 {
                    let cookieName = cols[0]
                    guard SQLiteReader.isSafeCookieName(cookieName) else { continue }
                    if !cols[1].isEmpty { results.append((cookieName, cols[1])) }
                }
                if !results.isEmpty { break }
            }
            return results
        }.value
    }

    // MARK: - Chrome (extract in Python, decrypt in Swift)

    /// Python only reads SQLite (parameterized) and base64-encodes
    /// `encrypted_value`. Decryption happens in Swift via CommonCrypto so the
    /// derived key never appears in `ps` output (previous `openssl -K <hex>`).
    private static func chromeChunkedCookies(prefix: String, host: String) async -> [(name: String, value: String)] {
        let rows = chromeExtractRowsSync(name: nil, prefix: prefix, host: host)
        return decryptChromeRows(rows)
    }

    private static func firefoxCookie(name: String, host: String, profilePath configured: String) async -> String? {
        await Task.detached(priority: .utility) {
            guard let profile = resolveFirefoxProfile(configured: configured) else { return nil }
            let db = profile + "/cookies.sqlite"
            guard FileManager.default.fileExists(atPath: db) else { return nil }

            let sql = "SELECT value FROM moz_cookies WHERE name=? AND host=? ORDER BY lastAccessed DESC LIMIT 1;"
            for h in hostVariants(host) {
                let rows: [[String]]? = SecureTempFile.withSecureCopy(sourcePath: db, prefix: "cuw_ff") { tmp in
                    SQLiteReader.query(dbPath: tmp, sql: sql, params: [name, h])
                }
                guard let rows else { continue }
                if let v = rows.first?.first, !v.isEmpty { return v }
            }
            return nil
        }.value
    }

    private static func chromeCookie(name: String, host: String) async -> String? {
        let rows = chromeExtractRowsSync(name: name, prefix: nil, host: host)
        return decryptChromeRows(rows).first?.value
    }

    /// Raw rows from Chrome: (name, plaintextValue, encryptedB64).
    /// Tries Chrome Default / Profile 1 / Profile 2, then Brave Default.
    private static func chromeExtractRowsSync(name: String?, prefix: String?, host: String) -> [(name: String, value: String, encB64: String)] {
        // Mode selects the WHERE clause; values passed as argv (no shell).
        let mode = name != nil ? "exact" : "prefix"
        let match = name ?? prefix ?? ""
        guard SQLiteReader.isSafeCookieName(match) else { return [] }

        let candidates = [
            "Google/Chrome/Default/Cookies",
            "Google/Chrome/Profile 1/Cookies",
            "Google/Chrome/Profile 2/Cookies",
            "BraveSoftware/Brave-Browser/Default/Cookies",
        ]
        for rel in candidates {
            let db = NSHomeDirectory() + "/Library/Application Support/" + rel
            guard FileManager.default.fileExists(atPath: db) else { continue }
            let rows = chromeExtractFromDB(dbPath: db, mode: mode, match: match, host: host)
            if !rows.isEmpty { return rows }
        }
        return []
    }

    private static func chromeExtractFromDB(dbPath: String, mode: String, match: String, host: String) -> [(name: String, value: String, encB64: String)] {
        // Note: uses mkstemp (not mktemp) + parameterized queries.
        let script = """
        import sqlite3, shutil, tempfile, os, sys, json, base64
        mode, match, host, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
        fd, tmp = tempfile.mkstemp(suffix=".sqlite")
        os.close(fd)
        try:
            shutil.copy2(src, tmp)
            os.chmod(tmp, 0o600)
            conn = sqlite3.connect(tmp)
            cur = conn.cursor()
            hosts = [host, '.' + host.lstrip('.')]
            results = []
            for h in hosts:
                if mode == "exact":
                    cur.execute("SELECT name, value, encrypted_value FROM cookies WHERE name=? AND host_key=? ORDER BY last_access_utc DESC LIMIT 5", (match, h))
                else:
                    cur.execute("SELECT name, value, encrypted_value FROM cookies WHERE (name=? OR name LIKE ? ESCAPE '\\\\') AND host_key=? ORDER BY name", (match, match.replace("%","\\\\%").replace("_","\\\\_") + ".%", h))
                for cname, cval, enc in cur.fetchall():
                    encB64 = ""
                    if enc and len(enc) >= 4 and enc[:3] == b'v10':
                        encB64 = base64.b64encode(enc).decode()
                    results.append([cname, cval or "", encB64])
                if results: break
            print(json.dumps(results))
        finally:
            try: os.remove(tmp)
            except: pass
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-c", script, mode, match, host, dbPath]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        // Restrict child's environment: no secrets passed via argv/env.
        proc.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, let data = out.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
        return arr.compactMap { cols in
            guard cols.count == 3, SQLiteReader.isSafeCookieName(cols[0]) else { return nil }
            return (cols[0], cols[1], cols[2])
        }
    }

    /// Decrypt rows in-process; plaintext `value` preferred, else v10 decrypt.
    /// The AES key is cached per-launch so Chrome's keychain item is touched once.
    private static func decryptChromeRows(_ rows: [(name: String, value: String, encB64: String)]) -> [(name: String, value: String)] {
        var out: [(name: String, value: String)] = []
        var key: Data?
        for row in rows {
            if !row.value.isEmpty {
                out.append((row.name, row.value))
                continue
            }
            guard !row.encB64.isEmpty else { continue }
            if key == nil {
                guard let k = ChromeCookieCrypto.cachedDerivedKey() else { break }
                key = k
            }
            if let key,
               let text = ChromeCookieCrypto.decryptV10Base64(row.encB64, key: key) {
                out.append((row.name, text))
            }
        }
        return out
    }

    private static func resolveFirefoxProfile(configured: String) -> String? {
        if configured != "auto", !configured.isEmpty {
            let expanded = NSString(string: configured).expandingTildeInPath
            // Containment: must resolve inside the Firefox data dir, no traversal.
            let base = NSHomeDirectory() + "/Library/Application Support/Firefox/"
            let url = URL(fileURLWithPath: expanded).standardized
            guard url.path.hasPrefix(base),
                  FileManager.default.fileExists(atPath: url.path + "/cookies.sqlite") else { return nil }
            return url.path
        }
        let iniPath = NSHomeDirectory() + "/Library/Application Support/Firefox/profiles.ini"
        guard let ini = try? String(contentsOfFile: iniPath, encoding: .utf8) else { return nil }
        var defaultPath: String?
        var installDefault: String?
        var section: [String: String] = [:]
        func flush() {
            guard let path = section["Path"], !path.contains("..") else { return }
            let full = NSHomeDirectory() + "/Library/Application Support/Firefox/" + path
            if section["Default"] == "1" { defaultPath = full }
            if section["Locked"] == "1" { installDefault = full }
        }
        for line in ini.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { flush(); section = [:]; continue }
            let p = t.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { section[p[0]] = p[1] }
        }
        flush()
        return installDefault ?? defaultPath
    }

    private static func hostVariants(_ host: String) -> [String] {
        let bare = host.hasPrefix(".") ? String(host.dropFirst()) : host
        return [host, bare, "." + bare]
    }
}

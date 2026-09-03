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

            let tmp = "/tmp/cuw_ff_\(ProcessInfo.processInfo.processIdentifier).sqlite"
            guard shellCopy(from: db, to: tmp) else { return [] }
            defer { try? FileManager.default.removeItem(atPath: tmp) }

            var results: [(String, String)] = []
            for h in hostVariants(host) {
                let q = """
                SELECT name, value FROM moz_cookies \
                WHERE (name = '\(sqlEscape(prefix))' OR name LIKE '\(sqlEscape(prefix)).%') \
                AND host='\(sqlEscape(h))' ORDER BY name;
                """
                guard let out = shellSqlite(db: tmp, sql: q), !out.isEmpty else { continue }
                for line in out.components(separatedBy: .newlines) {
                    let cols = line.split(separator: "|", maxSplits: 1).map(String.init)
                    if cols.count == 2, !cols[1].isEmpty {
                        results.append((cols[0], cols[1]))
                    }
                }
                if !results.isEmpty { break }
            }
            return results
        }.value
    }

    private static func chromeChunkedCookies(prefix: String, host: String) async -> [(name: String, value: String)] {
        await Task.detached(priority: .utility) {
            let db = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies"
            guard FileManager.default.fileExists(atPath: db) else { return [] }

            let script = """
            import sqlite3, shutil, subprocess, hashlib, tempfile, os, sys, json
            prefix, host = sys.argv[1], sys.argv[2]
            src = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/Cookies")
            tmp = tempfile.mktemp(suffix=".sqlite")
            shutil.copy2(src, tmp)
            results = []
            try:
                conn = sqlite3.connect(tmp)
                cur = conn.cursor()
                hosts = [host, '.' + host.lstrip('.')]
                pwd = subprocess.check_output(["security","find-generic-password","-w","-s","Chrome Safe Storage","-a","Chrome"], stderr=subprocess.DEVNULL).decode().strip()
                key = hashlib.pbkdf2_hmac('sha1', pwd.encode(), b'saltysalt', 1003, dklen=16)
                for h in hosts:
                    cur.execute(
                        "SELECT name, value, encrypted_value FROM cookies WHERE (name = ? OR name LIKE ?) AND host_key=? ORDER BY name",
                        (prefix, prefix + '.%', h)
                    )
                    for name, value, enc in cur.fetchall():
                        val = value
                        if not val and enc and len(enc) >= 4 and enc[:3] == b'v10':
                            ct, iv = enc[3:], b' ' * 16
                            p = subprocess.run(["openssl","enc","-aes-128-cbc","-d","-nosalt","-K",key.hex(),"-iv",iv.hex()], input=ct, capture_output=True)
                            if p.returncode != 0: continue
                            valb = p.stdout
                            pad = valb[-1]
                            if 1 <= pad <= 16: valb = valb[:-pad]
                            try:
                                text = valb.decode('utf-8')
                                if text and all(32 <= ord(c) < 127 or c in ' \\\\t' for c in text):
                                    val = text
                            except: continue
                        if val:
                            results.append([name, val])
                    if results: break
            finally:
                os.remove(tmp)
            print(json.dumps(results))
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = ["-c", script, prefix, host]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let out, let data = out.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
            return arr.compactMap { pair in
                guard pair.count == 2, !pair[1].isEmpty else { return nil }
                return (pair[0], pair[1])
            }
        }.value
    }

    private static func firefoxCookie(name: String, host: String, profilePath configured: String) async -> String? {
        await Task.detached(priority: .utility) {
            guard let profile = resolveFirefoxProfile(configured: configured) else { return nil }
            let db = profile + "/cookies.sqlite"
            guard FileManager.default.fileExists(atPath: db) else { return nil }

            let tmp = "/tmp/cuw_ff_\(ProcessInfo.processInfo.processIdentifier).sqlite"
            guard shellCopy(from: db, to: tmp) else { return nil }
            defer { try? FileManager.default.removeItem(atPath: tmp) }

            for h in hostVariants(host) {
                let q = "SELECT value FROM moz_cookies WHERE name='\(sqlEscape(name))' AND host='\(sqlEscape(h))' ORDER BY lastAccessed DESC LIMIT 1;"
                if let v = shellSqlite(db: tmp, sql: q), !v.isEmpty { return v }
            }
            return nil
        }.value
    }

    private static func chromeCookie(name: String, host: String) async -> String? {
        await Task.detached(priority: .utility) {
            let db = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies"
            guard FileManager.default.fileExists(atPath: db) else { return nil }

            let script = """
            import sqlite3, shutil, subprocess, hashlib, tempfile, os, sys
            name, host = sys.argv[1], sys.argv[2]
            src = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/Cookies")
            tmp = tempfile.mktemp(suffix=".sqlite")
            shutil.copy2(src, tmp)
            try:
                conn = sqlite3.connect(tmp)
                cur = conn.cursor()
                hosts = [host, '.' + host.lstrip('.')]
                for h in hosts:
                    cur.execute("SELECT value, encrypted_value FROM cookies WHERE name=? AND host_key=? ORDER BY last_access_utc DESC LIMIT 1", (name, h))
                    row = cur.fetchone()
                    if not row: continue
                    value, enc = row
                    if value: print(value); sys.exit(0)
                    if not enc or len(enc) < 4 or enc[:3] != b'v10': continue
                    pwd = subprocess.check_output(["security","find-generic-password","-w","-s","Chrome Safe Storage","-a","Chrome"], stderr=subprocess.DEVNULL).decode().strip()
                    key = hashlib.pbkdf2_hmac('sha1', pwd.encode(), b'saltysalt', 1003, dklen=16)
                    ct, iv = enc[3:], b' ' * 16
                    p = subprocess.run(["openssl","enc","-aes-128-cbc","-d","-nosalt","-K",key.hex(),"-iv",iv.hex()], input=ct, capture_output=True)
                    if p.returncode != 0: continue
                    val = p.stdout
                    pad = val[-1]
                    if 1 <= pad <= 16: val = val[:-pad]
                    try:
                        text = val.decode('utf-8')
                        if text and all(32 <= ord(c) < 127 or c in ' \\t' for c in text):
                            print(text); sys.exit(0)
                    except: pass
            finally:
                os.remove(tmp)
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = ["-c", script, name, host]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (out?.isEmpty == false) ? out : nil
        }.value
    }

    private static func resolveFirefoxProfile(configured: String) -> String? {
        if configured != "auto", !configured.isEmpty {
            let expanded = NSString(string: configured).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded + "/cookies.sqlite") { return expanded }
        }
        let iniPath = NSHomeDirectory() + "/Library/Application Support/Firefox/profiles.ini"
        guard let ini = try? String(contentsOfFile: iniPath, encoding: .utf8) else { return nil }
        var defaultPath: String?
        var installDefault: String?
        var section: [String: String] = [:]
        func flush() {
            guard let path = section["Path"] else { return }
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

    private static func sqlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    private static func shellCopy(from: String, to: String) -> Bool {
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = [from, to]
        try? cp.run()
        cp.waitUntilExit()
        return cp.terminationStatus == 0
    }

    private static func shellSqlite(db: String, sql: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [db, sql]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }
}

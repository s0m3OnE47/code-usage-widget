import Foundation

protocol UsageFetcher: Sendable {
    var providerID: ProviderID { get }
    func fetch(config: WidgetConfig) async -> ProviderUsage
}

enum HTTPError: Error {
    case status(Int)
}

enum HTTPClient {
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    static let session: URLSession = {
        // Ephemeral + no cookie jar: providers must not leak cookies into each other.
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = false
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private static let fmtLock = NSLock()
    private static let resetFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
    private static let shortFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    static func applyBrowserHeaders(_ request: inout URLRequest, extra: [String: String] = [:]) {
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        for (key, value) in extra {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    static func postJSON<T: Decodable>(
        url: String,
        body: [String: String] = [:],
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        applyBrowserHeaders(&req, extra: headers)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw HTTPError.status(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func getJSON<T: Decodable>(
        url: String,
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        applyBrowserHeaders(&req, extra: headers)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw HTTPError.status(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func getData(url: String, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        applyBrowserHeaders(&req, extra: headers)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    static func parseUnixMs(_ s: String?) -> Date? {
        guard let s, let ms = Double(s) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    static func formatReset(_ date: Date?) -> String {
        guard let date else { return "" }
        fmtLock.lock(); defer { fmtLock.unlock() }
        return "resets \(resetFmt.string(from: date))"
    }

    static func formatUSD(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func formatINR(_ value: Double) -> String {
        String(format: "₹%.0f", value)
    }

    static func formatShortDate(_ date: Date) -> String {
        fmtLock.lock(); defer { fmtLock.unlock() }
        return shortFmt.string(from: date)
    }
}

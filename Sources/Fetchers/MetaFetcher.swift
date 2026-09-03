import Foundation

/// Muse subscription usage from the dev.meta.ai dashboard.
///
/// When `team_id` is set (taken from the dev.meta.ai/usage/ page URL), the
/// fetcher replays the dashboard's own persisted Relay query
/// (`LLMDCUsageQuery`, observed doc_id below) using the browser session
/// (`llm_sess` cookie, Chrome/Firefox auto-read, or `session_cookie`
/// manual override). The Model API reference publishes no usage endpoint,
/// so without a team session only the API-key check is available.
/// Cookie/token values stay in memory and are never logged.
struct MetaFetcher: UsageFetcher {
    let providerID: ProviderID = .meta

    /// Persisted query behind dev.meta.ai/usage/. Rotated by Meta on
    /// occasion — a stale id surfaces as a GraphQL error row.
    private static let usageDocID = "28117303444603430"
    private static let graphqlURL = "https://dev.meta.ai/api/graphql/"
    private static let usagePageURL = "https://dev.meta.ai/usage/"

    private struct Quota: Decodable {
        let tier: String?
        let windowWeightedUsed: String?
        let windowWeightedLimit: String?
        let windowResetsAt: Double?
        let weeklyWeightedUsed: String?
        let weeklyWeightedLimit: String?
        let weeklyResetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case tier
            case windowWeightedUsed = "window_weighted_used"
            case windowWeightedLimit = "window_weighted_limit"
            case windowResetsAt = "window_resets_at"
            case weeklyWeightedUsed = "weekly_weighted_used"
            case weeklyWeightedLimit = "weekly_weighted_limit"
            case weeklyResetsAt = "weekly_resets_at"
        }
    }

    private struct GQLResp: Decodable {
        struct Team: Decodable {
            let subscriptionQuotaUsage: Quota?

            enum CodingKeys: String, CodingKey {
                case subscriptionQuotaUsage = "subscription_quota_usage"
            }
        }
        struct GQLError: Decodable {
            let message: String?
        }
        struct Data_: Decodable {
            let team: Team?
        }
        let data: Data_?
        let errors: [GQLError]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.meta
        if let balance = c.balanceUsd {
            let limit = max(c.budgetUsd, balance, 0.01)
            return ProviderUsage(
                id: .meta, status: balance / limit < 0.2 ? .nearLimit : .ok,
                used: max(limit - balance, 0), limit: limit, unit: "USD",
                subtitle: "From config · dev.meta.ai/usage",
                metricLabel: "\(HTTPClient.formatUSD(balance)) left",
                resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        }
        if let teamID = c.teamId?.trimmingCharacters(in: .whitespacesAndNewlines), !teamID.isEmpty {
            return await fetchSubscription(config: config, teamID: teamID)
        }
        return await fetchKeyCheck(config: config)
    }

    // MARK: - Subscription (dashboard query)

    private func fetchSubscription(config: WidgetConfig, teamID: String) async -> ProviderUsage {
        let c = config.providers.meta
        var manualSession = c.sessionCookie
        if (manualSession == nil || manualSession!.isEmpty), config.useKeychain,
           let v = KeychainStore.get(key: "meta.session_cookie"), !v.isEmpty {
            manualSession = v
        }
        guard let sess = await BrowserCookieReader.cookie(
            name: "llm_sess",
            host: "dev.meta.ai",
            browser: config.browser,
            firefoxProfile: config.firefoxProfile,
            manualValue: manualSession
        ), !sess.isEmpty else {
            return .error(.meta, message: "Log in to dev.meta.ai in Chrome/Firefox, or paste llm_sess as meta.session_cookie")
        }

        var cookieParts = [BrowserCookieReader.cookieHeader(name: "llm_sess", value: sess)]
        for (name, host) in [("datr", "meta.ai"), ("dpr", "meta.ai"), ("wd", "meta.ai")] {
            if let v = await BrowserCookieReader.cookie(
                name: name, host: host, browser: config.browser, firefoxProfile: config.firefoxProfile
            ), !v.isEmpty {
                cookieParts.append(BrowserCookieReader.cookieHeader(name: name, value: v))
            }
        }
        // Meta's edge 500s bare-bones requests: the usage page needs a full
        // browser navigation header set (verified: minimal headers -> HTTP
        // 500, browser headers -> 302 bootstrap -> 200 with quota content).
        var headers = ["Cookie": cookieParts.joined(separator: "; ")]
        headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
        headers["Accept-Language"] = "en-US,en;q=0.9"
        headers["Referer"] = "https://dev.meta.ai/"
        headers["Sec-Fetch-Dest"] = "document"
        headers["Sec-Fetch-Mode"] = "navigate"
        headers["Sec-Fetch-Site"] = "same-origin"
        headers["Sec-Fetch-User"] = "?1"
        headers["Upgrade-Insecure-Requests"] = "1"

        var pageComps = URLComponents(string: Self.usagePageURL)!
        var pageItems = [URLQueryItem(name: "team_id", value: teamID)]
        if let p = c.projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            pageItems.append(URLQueryItem(name: "project_id", value: p))
        }
        pageComps.queryItems = pageItems

        let html: String
        do {
            let (data, resp) = try await HTTPClient.getData(url: pageComps.string ?? Self.usagePageURL, headers: headers)
            guard (200...299).contains(resp.statusCode),
                  resp.url?.host == "dev.meta.ai",
                  let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return .error(.meta, message: "Meta session expired — open dev.meta.ai/usage/ in your browser, then refresh")
            }
            html = text
        } catch {
            return .error(.meta, message: "Meta dashboard unreachable")
        }

        guard let dtsg = Self.extractToken(html, patterns: [
            #""DTSGInitialData",\[\],\{"token":"([^"]+)""#,
            #""dtsg":\{"token":"([^"]+)""#,
            #""fb_dtsg":"([^"]+)""#,
        ]), !dtsg.isEmpty else {
            return .error(.meta, message: "Meta page format changed (dtsg) — update the widget")
        }
        let jazoest = Self.extractToken(html, patterns: [#""jazoest":"?(\d+)"?"#]) ?? ""
        let lsd = Self.extractToken(html, patterns: [#""LSD",\[\],\{"token":"([^"]+)""#]) ?? ""
        let actor = Self.extractToken(html, patterns: [#""actorID":"?(\d+)"?"#, #""userID":"?(\d+)"?"#])

        let vars = Self.queryVariables(teamID: teamID)
        guard let varsString = String(data: (try? JSONSerialization.data(withJSONObject: vars, options: [.sortedKeys])) ?? Data(), encoding: .utf8),
              !varsString.isEmpty else {
            return .error(.meta, message: "Meta query build failed")
        }

        var fields: [(String, String)] = [
            ("__user", "0"),
            ("__a", "1"),
            ("fb_dtsg", dtsg),
            ("doc_id", Self.usageDocID),
            ("variables", varsString),
            ("fb_api_caller_class", "RelayModern"),
            ("fb_api_req_friendly_name", "LLMDCUsageQuery"),
            ("server_timestamps", "true"),
        ]
        if let actor, !actor.isEmpty { fields.insert(("av", actor), at: 0) }
        if !jazoest.isEmpty { fields.append(("jazoest", jazoest)) }
        if !lsd.isEmpty { fields.append(("lsd", lsd)) }

        do {
            // Same-document POST: Origin/Referer pair the page navigation.
            var gqlHeaders = headers
            gqlHeaders["Accept"] = "application/json"
            gqlHeaders["Origin"] = "https://dev.meta.ai"
            gqlHeaders["Referer"] = pageComps.string ?? Self.usagePageURL
            let (data, resp) = try await HTTPClient.postForm(url: Self.graphqlURL, fields: fields, headers: gqlHeaders)
            guard (200...299).contains(resp.statusCode) else {
                return .error(.meta, message: "Meta usage query rejected (HTTP \(resp.statusCode))")
            }
            let body = Self.stripHijackPrefix(data)
            let gql = try JSONDecoder().decode(GQLResp.self, from: body)
            if let msg = gql.errors?.first?.message, !msg.isEmpty {
                return .error(.meta, message: "Meta usage error: \(msg)")
            }
            guard let q = gql.data?.team?.subscriptionQuotaUsage,
                  let used = Double(q.windowWeightedUsed ?? ""), used >= 0,
                  let limit = Double(q.windowWeightedLimit ?? ""), limit > 0 else {
                return .error(.meta, message: "Meta usage reply unreadable — update the widget")
            }
            let pct = min(100, (used / limit) * 100)
            var status: UsageStatus = .ok
            if pct >= 100 { status = .limited }
            else if pct >= 80 { status = .nearLimit }
            var subs: [UsageSubMetric] = []
            if let wu = Double(q.weeklyWeightedUsed ?? ""),
               let wl = Double(q.weeklyWeightedLimit ?? ""), wl > 0 {
                subs.append(UsageSubMetric(id: "weekly", label: "week", percent: min(100, (wu / wl) * 100)))
            }
            return ProviderUsage(
                id: .meta, status: status, used: used, limit: limit, unit: "tokens",
                subtitle: q.tier ?? "Muse subscription",
                metricLabel: "\(Int((100 - pct).rounded()))% of 5h left",
                resetsAt: q.windowResetsAt.map { Date(timeIntervalSince1970: $0) },
                errorMessage: nil, isRefreshing: false, subMetrics: subs
            )
        } catch {
            return .error(.meta, message: "Meta usage query failed")
        }
    }

    /// Relay variables for LLMDCUsageQuery: 7-day cost chart window plus the
    /// subscription-quota flags the usage page itself sends.
    static func queryVariables(teamID: String, now: Date = Date()) -> [String: Any] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        let end = fmt.string(from: now)
        let start = fmt.string(from: now.addingTimeInterval(-6 * 24 * 3600))
        return [
            "api_key_id": NSNull(),
            "end_date": end,
            "model_id": NSNull(),
            "start_date": start,
            "team_id": teamID,
            "timezone": TimeZone.current.identifier,
            "__relay_internal__pv__Usage_ShouldIncludeSubscriptionQuotarelayprovider": true,
            "__relay_internal__pv__Usage_ShouldIncludeBatchMetricsrelayprovider": false,
            "__relay_internal__pv__Usage_ShouldIncludeCostMetricsrelayprovider": true,
            "__relay_internal__pv__Usage_ShouldIncludeImageMetricsrelayprovider": false,
        ]
    }

    /// First capture group of the first matching pattern, else nil.
    static func extractToken(_ html: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let m = re.firstMatch(in: html, range: range), m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: html) {
                let v = String(html[r])
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    /// Meta prefixes JSON with `for (;;);` against hijacking.
    static func stripHijackPrefix(_ data: Data) -> Data {
        let prefix = Array("for (;;);".utf8)
        guard data.count > prefix.count,
              data.prefix(prefix.count).elementsEqual(prefix) else { return data }
        return data.dropFirst(prefix.count)
    }

    // MARK: - API key check (no public usage endpoint)

    private func fetchKeyCheck(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.meta
        guard let key = ConfigLoader.resolveSecret(configured: c.apiKey, keychainKey: "meta.api_key", envName: c.apiKeyEnv, useKeychain: config.useKeychain)
            ?? ConfigLoader.env("MODEL_API_KEY") else {
            return .error(.meta, message: "Set meta.team_id + dev.meta.ai login for subscription, or \(c.apiKeyEnv) for key check")
        }
        do {
            let _: ModelsResp = try await HTTPClient.getJSON(
                url: "https://api.meta.ai/v1/models",
                headers: ["Authorization": "Bearer \(key)"]
            )
            return ProviderUsage(
                id: .meta, status: .unavailable, used: 0, limit: max(c.budgetUsd, 0.01), unit: "USD",
                subtitle: "Key OK · set team_id for subscription usage",
                metricLabel: "Auth OK", resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.meta, message: "Invalid Meta API key")
        }
    }

    private struct ModelsResp: Decodable {
        struct Model: Decodable {
            let id: String?
            let name: String?
        }
        let data: [Model]?
        let models: [Model]?
    }
}

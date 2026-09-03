import Foundation

struct OpenCodeFetcher: UsageFetcher {
    let providerID: ProviderID = .opencode

    private let baseURL = "https://opencode.ai"
    private let workspacesServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private let subscriptionServerID = "7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4"
    private let billingServerID = "c83b78a614689c38ebee981f9b39a8b377716db85c1fd7dbab604adc02d3313d"

    private struct GoUsageResp: Decodable {
        struct Window: Decodable {
            let status: String?
            let percent: Double?
            let resetsAt: String?
        }
        let weekly: Window?
        let monthly: Window?
    }

    private struct ModelsResp: Decodable {
        struct Model: Decodable { let id: String? }
        let data: [Model]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        if let cookie = await resolveCookie(config: config),
           let usage = await fetchFromConsole(cookie: cookie) {
            return usage
        }

        if let key = resolveAPIKey(config: config) {
            return await fetchFromAPIKey(key)
        }

        return .error(.opencode, message: "Set api_key or session_token in config")
    }

    private func resolveCookie(config: WidgetConfig) async -> String? {
        var manual = config.providers.opencode.sessionToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if (manual == nil || manual!.isEmpty), config.useKeychain,
           let v = KeychainStore.get(key: "opencode.session_token"), !v.isEmpty {
            manual = v
        }
        if let manual, !manual.isEmpty {
            return BrowserCookieReader.cookieHeader(name: "auth", value: manual)
        }

        let cookieNames = ["auth", "__Secure-authjs.session-token", "next-auth.session-token"]
        let hosts = ["opencode.ai", "auth.opencode.ai"]
        for host in hosts {
            for name in cookieNames {
                if let token = await BrowserCookieReader.cookie(
                    name: name,
                    host: host,
                    browser: config.browser,
                    firefoxProfile: config.firefoxProfile
                ) {
                    return BrowserCookieReader.cookieHeader(name: name, value: token)
                }
            }
        }
        return nil
    }

    private func fetchFromConsole(cookie: String) async -> ProviderUsage? {
        guard let workspaceID = await fetchWorkspaceID(cookie: cookie) else { return nil }

        if let subscription = await fetchSubscription(workspaceID: workspaceID, cookie: cookie) {
            return subscription
        }
        return await fetchBilling(workspaceID: workspaceID, cookie: cookie)
    }

    private func fetchWorkspaceID(cookie: String) async -> String? {
        guard let text = await fetchServerText(
            serverID: workspacesServerID,
            args: nil,
            method: "GET",
            referer: baseURL + "/",
            cookie: cookie
        ), !looksSignedOut(text) else { return nil }

        return parseWorkspaceIDs(text).first
    }

    private func fetchSubscription(workspaceID: String, cookie: String) async -> ProviderUsage? {
        let referer = "\(baseURL)/workspace/\(workspaceID)/billing"
        guard let text = await fetchServerText(
            serverID: subscriptionServerID,
            args: [workspaceID],
            method: "GET",
            referer: referer,
            cookie: cookie
        ), !looksSignedOut(text), !isExplicitNullPayload(text) else { return nil }

        if let rolling = extractDouble(pattern: #"rollingUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#, text: text),
           let weekly = extractDouble(pattern: #"weeklyUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#, text: text) {
            let pct = max(rolling, weekly)
            var status: UsageStatus = .ok
            if pct >= 100 { status = .limited }
            else if pct >= 80 { status = .nearLimit }

            return ProviderUsage(
                id: .opencode,
                status: status,
                used: pct,
                limit: 100,
                unit: "%",
                subtitle: "Go subscription · rolling \(Int(rolling.rounded()))% · weekly \(Int(weekly.rounded()))%",
                metricLabel: String(format: "%.0f%% used", pct),
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        }
        return nil
    }

    private func fetchBilling(workspaceID: String, cookie: String) async -> ProviderUsage? {
        let referer = "\(baseURL)/workspace/\(workspaceID)"
        guard let text = await fetchServerText(
            serverID: billingServerID,
            args: [workspaceID],
            method: "GET",
            referer: referer,
            cookie: cookie
        ), !looksSignedOut(text) else { return nil }

        return parseBillingPayload(text)
    }

    private func fetchServerText(
        serverID: String,
        args: [Any]?,
        method: String,
        referer: String,
        cookie: String
    ) async -> String? {
        var urlString = "\(baseURL)/_server?id=\(serverID)"
        if method == "GET", let args {
            guard let argsData = try? JSONSerialization.data(withJSONObject: args),
                  let argsJSON = String(data: argsData, encoding: .utf8) else { return nil }
            urlString += "&args=\(argsJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? argsJSON)"
        }

        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        HTTPClient.applyBrowserHeaders(&req, extra: [
            "Cookie": cookie,
            "Accept": "text/javascript, application/json;q=0.9, */*;q=0.8",
            "X-Server-Id": serverID,
            "X-Server-Instance": "server-fn:\(UUID().uuidString)",
            "Origin": baseURL,
            "Referer": referer,
        ])
        if method == "POST", let args {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: args)
        }

        do {
            let (data, resp) = try await HTTPClient.session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        } catch {
            return nil
        }
    }

    private func parseBillingPayload(_ text: String) -> ProviderUsage? {
        if let balance = extractDouble(pattern: #"balance\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)"#, text: text) {
            let balanceUSD = balance / 1e8
            let monthlyUsed = extractDouble(pattern: #"monthlyUsage\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)"#, text: text)
            let monthlyLimit = extractDouble(pattern: #"monthlyLimit\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)"#, text: text)

            if let used = monthlyUsed, let limit = monthlyLimit, limit > 0 {
                let usedUSD = used / 1e8
                let limitUSD = limit / 1e8
                let pct = (usedUSD / limitUSD) * 100
                var status: UsageStatus = .ok
                if pct >= 100 { status = .limited }
                else if pct >= 80 { status = .nearLimit }

                return ProviderUsage(
                    id: .opencode,
                    status: status,
                    used: usedUSD,
                    limit: limitUSD,
                    unit: "USD",
                    subtitle: "Zen · \(HTTPClient.formatUSD(balanceUSD)) balance",
                    metricLabel: "\(HTTPClient.formatUSD(usedUSD)) / \(HTTPClient.formatUSD(limitUSD))",
                    resetsAt: nil,
                    errorMessage: nil,
                    isRefreshing: false,
                    subMetrics: []
                )
            }

            var status: UsageStatus = balanceUSD < 5 ? .nearLimit : .ok
            if balanceUSD <= 0 { status = .nearLimit }
            return ProviderUsage(
                id: .opencode,
                status: status,
                used: 0,
                limit: max(balanceUSD, 1),
                unit: "USD",
                subtitle: "Zen balance",
                metricLabel: HTTPClient.formatUSD(balanceUSD),
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        }
        return nil
    }

    private func parseWorkspaceIDs(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"id\s*:\s*\"(wrk_[^\"]+)\""#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private func isExplicitNullPayload(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("null") == .orderedSame { return true }
        return trimmed.range(of: #"\]\s*=\s*\[\s*\]\s*,\s*null\s*\)\s*$"#, options: .regularExpression) != nil
    }

    private func looksSignedOut(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("login")
            || lower.contains("sign in")
            || lower.contains("auth/authorize")
            || lower.contains("not associated with an account")
            || lower.contains("actor of type \"public\"")
    }

    private func extractDouble(pattern: String, text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    private func resolveAPIKey(config: WidgetConfig) -> String? {
        if let k = ConfigLoader.resolveSecret(
            configured: config.providers.opencode.apiKey,
            keychainKey: "opencode.api_key",
            envName: config.providers.opencode.apiKeyEnv,
            useKeychain: config.useKeychain
        ) { return k }
        if let k = ConfigLoader.env("ZEN_API_KEY") { return k }

        let authPath = NSHomeDirectory() + "/.local/share/opencode/auth.json"
        guard let data = FileManager.default.contents(atPath: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["opencode", "zen", "opencode-go"] {
            if let entry = json[key] as? [String: Any],
               let token = entry["token"] as? String ?? entry["apiKey"] as? String ?? entry["key"] as? String {
                return token
            }
        }
        return nil
    }

    private func fetchFromAPIKey(_ apiKey: String) async -> ProviderUsage {
        if let goUsage = await fetchGoUsage(apiKey: apiKey) {
            return goUsage
        }
        return await fetchModelsOnly(apiKey: apiKey)
    }

    private func fetchGoUsage(apiKey: String) async -> ProviderUsage? {
        do {
            let resp: GoUsageResp = try await HTTPClient.getJSON(
                url: "https://opencode.ai/zen/go/v1/usage",
                headers: ["Authorization": "Bearer \(apiKey)", "Accept": "application/json"]
            )

            let window = resp.monthly ?? resp.weekly
            let pct = window?.percent ?? 0
            let reset = window?.resetsAt.flatMap { ISO8601DateFormatter().date(from: $0) }

            var status: UsageStatus = .ok
            if window?.status == "limited" || pct >= 100 { status = .limited }
            else if pct >= 80 { status = .nearLimit }

            let subtitle = [window != nil ? "Go plan" : "Zen", HTTPClient.formatReset(reset)]
                .filter { !$0.isEmpty }.joined(separator: " · ")

            return ProviderUsage(
                id: .opencode,
                status: status,
                used: pct,
                limit: 100,
                unit: "%",
                subtitle: subtitle,
                metricLabel: String(format: "%.0f%% used", pct),
                resetsAt: reset,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        } catch {
            return nil
        }
    }

    private func fetchModelsOnly(apiKey: String) async -> ProviderUsage {
        do {
            let resp: ModelsResp = try await HTTPClient.getJSON(
                url: "https://opencode.ai/zen/v1/models",
                headers: ["Authorization": "Bearer \(apiKey)", "Accept": "application/json"]
            )
            let count = resp.data?.count ?? 0
            return ProviderUsage(
                id: .opencode,
                status: .ok,
                used: 0,
                limit: 100,
                unit: "%",
                subtitle: "\(count) Zen models · add session_token for balance",
                metricLabel: "Auth OK",
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        } catch {
            return .error(.opencode, message: "Invalid OpenCode API key")
        }
    }
}

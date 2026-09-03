import Foundation

struct SarvamFetcher: UsageFetcher {
    let providerID: ProviderID = .sarvam

    private let indusBase = "https://indus.sarvam.ai"
    private let cookieName = "sarvam_identity_session"

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let sarvam = config.providers.sarvam
        let apiKey = ConfigLoader.resolveAPIKey(configured: sarvam.apiKey, envName: sarvam.apiKeyEnv)

        if let token = sarvam.sessionToken, let usage = await fetchIndusSession(token) {
            return usage
        }

        if let usage = await fetchFromBrowser(config: config) {
            return usage
        }

        if let remaining = sarvam.creditsRemainingInr {
            let limit = max(sarvam.creditLimitInr, remaining, 0.01)
            let used = max(limit - remaining, 0)
            return makeUsage(
                used: used,
                limit: limit,
                subtitle: "From config · indus.sarvam.ai/billing"
            )
        }

        if let key = apiKey, await validateAPIKey(key) {
            return ProviderUsage(
                id: .sarvam,
                status: .unavailable,
                used: 0,
                limit: max(sarvam.creditLimitInr, 0.01),
                unit: "INR",
                subtitle: "API OK · add credits_remaining_inr in config",
                metricLabel: "See indus.sarvam.ai/billing",
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        }

        if apiKey == nil {
            return .error(.sarvam, message: "Set api_key in config")
        }
        return .error(.sarvam, message: "Add credits_remaining_inr from indus.sarvam.ai/billing")
    }

    private func fetchIndusSession(_ token: String) async -> ProviderUsage? {
        let cookie = BrowserCookieReader.cookieHeader(name: cookieName, value: token)
        let headers = indusHeaders(cookie: cookie)

        let apiPaths = [
            "/api/v1/billing/credits",
            "/api/billing/credits",
            "/api/v1/credits",
            "/api/platform/v1/billing",
        ]
        for path in apiPaths {
            if let usage = await fetchJSON(path: path, headers: headers) { return usage }
        }

        let htmlPaths = ["/billing", "/settings/billing", "/usage", "/settings/usage"]
        for path in htmlPaths {
            if let usage = await scrapePage(path: path, headers: headers) { return usage }
        }
        if let usage = await scrapeRSC(headers: headers) { return usage }
        return nil
    }

    private func scrapeRSC(headers: [String: String]) async -> ProviderUsage? {
        var rscHeaders = headers
        rscHeaders["Accept"] = "text/x-component"
        rscHeaders["RSC"] = "1"
        do {
            let (data, http) = try await HTTPClient.getData(url: indusBase + "/billing", headers: rscHeaders)
            guard (200...299).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return extractCreditsFromText(text, subtitle: "indus.sarvam.ai/billing")
        } catch {
            return nil
        }
    }

    private func extractCreditsFromText(_ html: String, subtitle: String) -> ProviderUsage? {
        if let remaining = extractNumber(from: html, patterns: [
            #""creditsRemaining"\s*:\s*([\d.]+)"#,
            #""credits_remaining"\s*:\s*([\d.]+)"#,
            #""remainingCredits"\s*:\s*([\d.]+)"#,
            #"creditsLeft"\s*:\s*([\d.]+)"#,
            #""availableCredits"\s*:\s*([\d.]+)"#,
            #""balance"\s*:\s*([\d.]+)"#,
            #"Credits Left[^₹0-9]*₹?\s*([\d,.]+)"#,
            #"Available Credits[^₹0-9]*₹?\s*([\d,.]+)"#,
            #"₹\s*([\d,.]+)\s*(?:left|remaining|available)"#,
        ]) {
            let total = extractNumber(from: html, patterns: [
                #""creditsTotal"\s*:\s*([\d.]+)"#,
                #""creditLimit"\s*:\s*([\d.]+)"#,
                #""totalCredits"\s*:\s*([\d.]+)"#,
            ]) ?? max(remaining + 1, 100)
            let used = max(total - remaining, 0)
            return makeUsage(used: used, limit: total, subtitle: subtitle)
        }
        return nil
    }

    private func fetchFromBrowser(config: WidgetConfig) async -> ProviderUsage? {
        var token = await BrowserCookieReader.cookie(
            name: cookieName,
            host: "indus.sarvam.ai",
            browser: config.browser,
            firefoxProfile: config.firefoxProfile
        )
        if token == nil {
            token = await BrowserCookieReader.cookie(
                name: cookieName,
                host: "sarvam.ai",
                browser: config.browser,
                firefoxProfile: config.firefoxProfile
            )
        }
        guard let token else { return nil }
        return await fetchIndusSession(token)
    }

    private func indusHeaders(cookie: String) -> [String: String] {
        [
            "Cookie": cookie,
            "Accept": "application/json, text/html",
            "Origin": indusBase,
            "Referer": "\(indusBase)/billing",
        ]
    }

    private func fetchJSON(path: String, headers: [String: String]) async -> ProviderUsage? {
        do {
            let (data, http) = try await HTTPClient.getData(url: indusBase + path, headers: headers)
            guard (200...299).contains(http.statusCode) else { return nil }
            return parseCreditsJSON(data)
        } catch { return nil }
    }

    private func scrapePage(path: String, headers: [String: String]) async -> ProviderUsage? {
        do {
            let (data, http) = try await HTTPClient.getData(url: indusBase + path, headers: headers)
            guard (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8),
                  !html.contains("OpenAuth") else { return nil }

            return extractCreditsFromText(html, subtitle: "indus.sarvam.ai")
        } catch {}
        return nil
    }

    private func validateAPIKey(_ apiKey: String) async -> Bool {
        do {
            let _: ModelsResp = try await HTTPClient.getJSON(
                url: "https://api.sarvam.ai/v2/models",
                headers: ["api-subscription-key": apiKey]
            )
            return true
        } catch { return false }
    }

    private struct ModelsResp: Decodable {
        let object: String?
    }

    private func parseCreditsJSON(_ data: Data) -> ProviderUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let remaining = findDouble(in: json, keys: [
            "creditsRemaining", "credits_remaining", "remainingCredits",
            "credits_left", "balance", "creditsLeft",
        ])
        let total = findDouble(in: json, keys: [
            "creditsTotal", "totalCredits", "total_credits", "creditLimit", "limit",
        ])
        let used = findDouble(in: json, keys: ["creditsUsed", "usedCredits", "spent", "used"])

        if let remaining {
            let limit = total ?? max(remaining + (used ?? 0), 100)
            let usedVal = used ?? max(limit - remaining, 0)
            return makeUsage(used: usedVal, limit: limit, subtitle: "indus.sarvam.ai")
        }
        if let used, let total, total > 0 {
            return makeUsage(used: used, limit: total, subtitle: "indus.sarvam.ai")
        }
        return nil
    }

    private func findDouble(in dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let v = dict[key] as? Double { return v }
            if let v = dict[key] as? Int { return Double(v) }
            if let v = dict[key] as? String, let d = Double(v.replacingOccurrences(of: ",", with: "")) { return d }
        }
        for (_, val) in dict {
            if let nested = val as? [String: Any], let found = findDouble(in: nested, keys: keys) {
                return found
            }
        }
        return nil
    }

    private func extractNumber(from text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: text) {
                let numStr = String(text[r]).replacingOccurrences(of: ",", with: "")
                if let d = Double(numStr) { return d }
            }
        }
        return nil
    }

    private func makeUsage(used: Double, limit: Double, subtitle: String) -> ProviderUsage {
        let pct = limit > 0 ? (used / limit) * 100 : 0
        var status: UsageStatus = .ok
        if pct >= 100 { status = .limited }
        else if pct >= 80 { status = .nearLimit }

        let remaining = max(limit - used, 0)
        return ProviderUsage(
            id: .sarvam,
            status: status,
            used: used,
            limit: max(limit, 0.01),
            unit: "INR",
            subtitle: subtitle,
            metricLabel: "\(HTTPClient.formatINR(remaining)) / \(HTTPClient.formatINR(limit))",
            resetsAt: nil,
            errorMessage: nil,
            isRefreshing: false,
            subMetrics: []
        )
    }
}

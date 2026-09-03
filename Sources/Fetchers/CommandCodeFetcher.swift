import Foundation

struct CommandCodeFetcher: UsageFetcher {
    let providerID: ProviderID = .commandcode

    private struct CreditsResp: Decodable {
        struct Credits: Decodable {
            let monthlyCredits: Double?
            let usedCredits: Double?
        }
        let credits: Credits?
    }

    private struct SummaryResp: Decodable {
        let totalCost: Double?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let cookieName = config.providers.commandcode.sessionCookieName
        var manualToken = config.providers.commandcode.sessionToken
        if (manualToken == nil || manualToken!.isEmpty), config.useKeychain,
           let v = KeychainStore.get(key: "commandcode.session_token"), !v.isEmpty {
            manualToken = v
        }
        guard let token = await BrowserCookieReader.cookie(
            name: cookieName,
            host: "commandcode.ai",
            browser: config.browser,
            firefoxProfile: config.firefoxProfile,
            manualValue: manualToken
        ) else {
            return .error(
                .commandcode,
                message: "Paste session_token in config (Chrome DevTools → Cookies)"
            )
        }

        let cookie = BrowserCookieReader.cookieHeader(name: cookieName, value: token)
        let headers = ["Cookie": cookie]

        async let creditsTask: CreditsResp? = try? HTTPClient.getJSON(
            url: "https://api.commandcode.ai/internal/billing/credits",
            headers: headers
        )
        async let summaryTask: SummaryResp? = try? HTTPClient.getJSON(
            url: "https://api.commandcode.ai/internal/usage/summary",
            headers: headers
        )

        let (credits, summary) = await (creditsTask, summaryTask)

        guard credits != nil || summary != nil else {
            return .error(.commandcode, message: "CommandCode API error")
        }

        let remaining = credits?.credits?.monthlyCredits ?? 0
        let usedFromCredits = credits?.credits?.usedCredits
        let periodCost = summary?.totalCost ?? 0

        let used: Double
        let limit: Double

        if let usedCredits = usedFromCredits, usedCredits + remaining > 0 {
            used = usedCredits
            limit = usedCredits + remaining
        } else if remaining > 0 {
            used = max(periodCost, 0)
            limit = remaining + used
        } else {
            used = periodCost
            limit = max(periodCost, 1)
        }

        let pct = limit > 0 ? (used / limit) * 100 : 0
        var status: UsageStatus = .ok
        if remaining <= 0 && used >= limit { status = .limited }
        else if pct >= 80 || remaining < 1 { status = .nearLimit }

        return ProviderUsage(
            id: .commandcode,
            status: status,
            used: used,
            limit: max(limit, 0.01),
            unit: "USD",
            subtitle: "\(HTTPClient.formatUSD(remaining)) credits left",
            metricLabel: "\(HTTPClient.formatUSD(used)) / \(HTTPClient.formatUSD(limit))",
            resetsAt: nil,
            errorMessage: nil,
            isRefreshing: false,
            subMetrics: []
        )
    }
}

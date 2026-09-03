import Foundation

struct OpenAIFetcher: UsageFetcher {
    let providerID: ProviderID = .openai

    private let sessionCookiePrefix = "__Secure-next-auth.session-token"
    private let sessionHosts = ["chatgpt.com", ".chatgpt.com", "platform.openai.com", ".openai.com", "auth.openai.com"]

    private struct CreditGrantsResp: Decodable {
        struct Grants: Decodable {
            struct Grant: Decodable {
                let grant_amount: Double?
                let used_amount: Double?
                let expires_at: TimeInterval?
            }
            let data: [Grant]?
        }
        let total_granted: Double?
        let total_used: Double?
        let total_available: Double?
        let grants: Grants?
    }

    private struct PendingUsageResp: Decodable {
        let total_usage: Double?
    }

    private struct CostsResp: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                let amount: Amount?
            }
            struct Amount: Decodable {
                let value: String?
            }
            let results: [Result]?
        }
        let data: [Bucket]?
    }

    private struct ModelsResp: Decodable {
        struct Model: Decodable { let id: String? }
        let data: [Model]?
    }

    private struct ChatGPTSessionResp: Decodable {
        let accessToken: String?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let openai = config.providers.openai

        if let sess = trimmed(openai.sessionKey),
           let usage = await fetchCreditBalance(bearer: sess, label: "Platform credits") {
            return usage
        }

        if let token = trimmed(openai.accessToken),
           let usage = await fetchCreditBalance(bearer: token, label: "Platform credits") {
            return usage
        }

        if let usage = await fetchWithSessionAuth(openai: openai, browserConfig: config) {
            return usage
        }

        if let key = resolveKey(configured: openai.apiKey, envName: openai.apiKeyEnv),
           !key.hasPrefix("sk-proj-"),
           let usage = await fetchCreditBalance(bearer: key, label: "API credits") {
            return usage
        }

        if let admin = resolveKey(configured: openai.adminKey, envName: openai.adminKeyEnv),
           let usage = await fetchOrganizationSpend(key: admin, budget: openai.budgetUsd) {
            return usage
        }

        if let balance = openai.balanceUsd {
            let limit = max(openai.budgetUsd, balance, 0.01)
            let used = max(limit - balance, 0)
            return ProviderUsage(
                id: .openai,
                status: balance / limit < 0.2 ? .nearLimit : .ok,
                used: used,
                limit: limit,
                unit: "USD",
                subtitle: "From config · platform.openai.com/billing",
                metricLabel: "\(HTTPClient.formatUSD(balance)) left",
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        }

        if hasPartialSessionConfig(openai) {
            return .error(.openai, message: "Need both session_token_0 and session_token_1")
        }

        if hasLegacyCombinedSessionToken(openai) {
            return .error(
                .openai,
                message: "Remove session_token — use session_key (sess-…) or split cookies into _0/_1"
            )
        }

        if hasAnySessionConfig(openai) {
            return .error(.openai, message: "Session expired — refresh session_key from Network tab")
        }

        if let key = resolveKey(configured: openai.apiKey, envName: openai.apiKeyEnv),
           await validateAPIKey(key) {
            return ProviderUsage(
                id: .openai,
                status: .unavailable,
                used: 0,
                limit: max(openai.budgetUsd, 0.01),
                unit: "USD",
                subtitle: "Project key · use session_key instead",
                metricLabel: "No billing access",
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        }

        return .error(.openai, message: "Set session_key, session_token_0/_1, or balance_usd")
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func hasAnySessionConfig(_ openai: OpenAIConfig) -> Bool {
        [openai.sessionKey, openai.sessionToken, openai.sessionToken0, openai.sessionToken1, openai.accessToken]
            .contains { trimmed($0) != nil }
    }

    private func hasPartialSessionConfig(_ openai: OpenAIConfig) -> Bool {
        let t0 = trimmed(openai.sessionToken0)
        let t1 = trimmed(openai.sessionToken1)
        return (t0 != nil && t1 == nil) || (t0 == nil && t1 != nil)
    }

    private func hasLegacyCombinedSessionToken(_ openai: OpenAIConfig) -> Bool {
        trimmed(openai.sessionToken) != nil
            && trimmed(openai.sessionToken0) == nil
            && trimmed(openai.sessionToken1) == nil
    }

    private func resolveKey(configured: String?, envName: String) -> String? {
        ConfigLoader.resolveAPIKey(configured: configured, envName: envName)
    }

    private func fetchWithSessionAuth(openai: OpenAIConfig, browserConfig: WidgetConfig) async -> ProviderUsage? {
        var cookieHeaders: [String] = []

        if let manual = manualSessionCookieHeader(openai: openai) {
            cookieHeaders.append(manual)
        }

        for host in sessionHosts {
            if let header = await BrowserCookieReader.chunkedCookieHeader(
                prefix: sessionCookiePrefix,
                host: host,
                browser: browserConfig.browser,
                firefoxProfile: browserConfig.firefoxProfile
            ) {
                cookieHeaders.append(header)
            }
        }

        for cookieHeader in cookieHeaders {
            if let accessToken = await fetchChatGPTAccessToken(cookieHeader: cookieHeader),
               let usage = await fetchCreditBalance(bearer: accessToken, label: "Platform credits") {
                return usage
            }
            if let usage = await fetchCreditBalance(cookieHeader: cookieHeader, label: "Platform credits") {
                return usage
            }
            if let combined = combinedToken(from: cookieHeader),
               let usage = await fetchCreditBalance(bearer: combined, label: "Platform credits") {
                return usage
            }
        }
        return nil
    }

    private func fetchChatGPTAccessToken(cookieHeader: String) async -> String? {
        do {
            let session: ChatGPTSessionResp = try await HTTPClient.getJSON(
                url: "https://chatgpt.com/api/auth/session",
                headers: [
                    "Accept": "application/json",
                    "Cookie": cookieHeader,
                    "User-Agent": "Mozilla/5.0",
                ]
            )
            return trimmed(session.accessToken)
        } catch {
            return nil
        }
    }

    private func manualSessionCookieHeader(openai: OpenAIConfig) -> String? {
        let t0 = trimmed(openai.sessionToken0)
        let t1 = trimmed(openai.sessionToken1)
        if let t0, let t1 {
            return [
                BrowserCookieReader.cookieHeader(name: "\(sessionCookiePrefix).0", value: t0),
                BrowserCookieReader.cookieHeader(name: "\(sessionCookiePrefix).1", value: t1),
            ].joined(separator: "; ")
        }
        return nil
    }

    private func combinedToken(from cookieHeader: String) -> String? {
        var parts: [(name: String, value: String)] = []
        for piece in cookieHeader.split(separator: ";") {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            if name.hasPrefix(sessionCookiePrefix) {
                parts.append((name, value))
            }
        }
        return BrowserCookieReader.combinedChunkedValue(parts: parts)
    }

    private func fetchCreditBalance(bearer: String, label: String) async -> ProviderUsage? {
        await fetchCreditBalance(headers: authHeaders(bearer: bearer), label: label)
    }

    private func fetchCreditBalance(cookieHeader: String, label: String) async -> ProviderUsage? {
        var headers = platformHeaders()
        headers["Cookie"] = cookieHeader
        return await fetchCreditBalance(headers: headers, label: label)
    }

    private func fetchCreditBalance(headers: [String: String], label: String) async -> ProviderUsage? {
        do {
            let grants: CreditGrantsResp = try await HTTPClient.getJSON(
                url: "https://api.openai.com/v1/dashboard/billing/credit_grants",
                headers: headers
            )

            var available = grants.total_available ?? 0
            let granted = grants.total_granted ?? available
            let used = grants.total_used ?? max(granted - available, 0)

            if let pending: PendingUsageResp = try? await HTTPClient.getJSON(
                url: "https://api.openai.com/v1/dashboard/billing/pending_usage",
                headers: headers
            ), let pendingCents = pending.total_usage {
                available = max(available - pendingCents / 100, 0)
            }

            let limit = max(granted, available, 0.01)
            let usedAmount = max(limit - available, used)

            var status: UsageStatus = .ok
            if available <= 0 { status = .limited }
            else if available / limit < 0.2 { status = .nearLimit }

            let expiry = grants.grants?.data?
                .compactMap(\.expires_at)
                .map { Date(timeIntervalSince1970: $0) }
                .filter { $0 > Date() }
                .min()

            var subtitle = label
            if let expiry {
                subtitle += " · exp \(HTTPClient.formatShortDate(expiry))"
            }

            return ProviderUsage(
                id: .openai,
                status: status,
                used: usedAmount,
                limit: limit,
                unit: "USD",
                subtitle: subtitle,
                metricLabel: "\(HTTPClient.formatUSD(available)) left",
                resetsAt: expiry,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        } catch {
            return nil
        }
    }

    private func fetchOrganizationSpend(key: String, budget: Double) async -> ProviderUsage? {
        let start = Int(Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970)
        let url = "https://api.openai.com/v1/organization/costs?start_time=\(start)&bucket_width=1d"

        do {
            let resp: CostsResp = try await HTTPClient.getJSON(url: url, headers: authHeaders(bearer: key))
            var totalSpend = 0.0
            for bucket in resp.data ?? [] {
                for result in bucket.results ?? [] {
                    if let value = result.amount?.value, let amount = Double(value) {
                        totalSpend += amount
                    }
                }
            }

            let limit = max(budget, 0.01)
            var status: UsageStatus = .ok
            let pct = (totalSpend / limit) * 100
            if pct >= 100 { status = .limited }
            else if pct >= 80 { status = .nearLimit }

            return ProviderUsage(
                id: .openai,
                status: status,
                used: totalSpend,
                limit: limit,
                unit: "USD",
                subtitle: "30-day org spend",
                metricLabel: "\(HTTPClient.formatUSD(totalSpend)) / \(HTTPClient.formatUSD(limit))",
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        } catch {
            return nil
        }
    }

    private func validateAPIKey(_ key: String) async -> Bool {
        do {
            let _: ModelsResp = try await HTTPClient.getJSON(
                url: "https://api.openai.com/v1/models?limit=1",
                headers: authHeaders(bearer: key)
            )
            return true
        } catch {
            return false
        }
    }

    private func authHeaders(bearer: String) -> [String: String] {
        var headers = platformHeaders()
        headers["Authorization"] = "Bearer \(bearer)"
        return headers
    }

    private func platformHeaders() -> [String: String] {
        [
            "Accept": "application/json",
            "Origin": "https://platform.openai.com",
            "Referer": "https://platform.openai.com/account/billing",
        ]
    }
}

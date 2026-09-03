import Foundation

/// Real credits API: GET /api/v1/credits → {data:{total_credits,total_usage}}.
struct OpenRouterFetcher: UsageFetcher {
    let providerID: ProviderID = .openrouter

    private struct CreditsResp: Decodable {
        struct Data_: Decodable {
            let total_credits: Double?
            let total_usage: Double?
        }
        let data: Data_?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.openrouter
        guard let key = ConfigLoader.resolveSecret(configured: c.apiKey, keychainKey: "openrouter.api_key", envName: c.apiKeyEnv, useKeychain: config.useKeychain) else {
            return .error(.openrouter, message: "Set \(c.apiKeyEnv) in env or Keychain")
        }
        do {
            let resp: CreditsResp = try await HTTPClient.getJSON(
                url: "https://openrouter.ai/api/v1/credits",
                headers: ["Authorization": "Bearer \(key)"]
            )
            let total = resp.data?.total_credits ?? 0
            let used = resp.data?.total_usage ?? 0
            let limit = max(total, used, 0.01)
            let remaining = max(limit - used, 0)
            var status: UsageStatus = .ok
            if remaining <= 0 { status = .limited }
            else if remaining / limit < 0.2 { status = .nearLimit }
            return ProviderUsage(
                id: .openrouter, status: status, used: used, limit: limit, unit: "USD",
                subtitle: "OpenRouter credits",
                metricLabel: "\(HTTPClient.formatUSD(remaining)) left",
                resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.openrouter, message: "Invalid OpenRouter API key")
        }
    }
}

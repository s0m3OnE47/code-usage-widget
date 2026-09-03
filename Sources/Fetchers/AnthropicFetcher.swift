import Foundation

/// Validates the Anthropic key via GET /v1/models; no public spend API,
/// so manual `balance_usd` is honored when set.
struct AnthropicFetcher: UsageFetcher {
    let providerID: ProviderID = .anthropic

    private struct ModelsResp: Decodable {
        struct Model: Decodable { let id: String? }
        let data: [Model]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.anthropic
        if let balance = c.balanceUsd {
            let limit = max(c.budgetUsd, balance, 0.01)
            return ProviderUsage(
                id: .anthropic, status: balance / limit < 0.2 ? .nearLimit : .ok,
                used: max(limit - balance, 0), limit: limit, unit: "USD",
                subtitle: "From config · console.anthropic.com",
                metricLabel: "\(HTTPClient.formatUSD(balance)) left",
                resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        }
        guard let key = ConfigLoader.resolveSecret(configured: c.apiKey, keychainKey: "anthropic.api_key", envName: c.apiKeyEnv, useKeychain: config.useKeychain) else {
            return .error(.anthropic, message: "Set \(c.apiKeyEnv) in env or Keychain")
        }
        do {
            let _: ModelsResp = try await HTTPClient.getJSON(
                url: "https://api.anthropic.com/v1/models?limit=1",
                headers: ["x-api-key": key, "anthropic-version": "2023-06-01"]
            )
            return ProviderUsage(
                id: .anthropic, status: .unavailable, used: 0, limit: max(c.budgetUsd, 0.01), unit: "USD",
                subtitle: "Key OK · no usage API · set balance_usd for tracking",
                metricLabel: "Auth OK", resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.anthropic, message: "Invalid Anthropic API key")
        }
    }
}

import Foundation

/// Validates the xAI key via GET /v1/models; manual `balance_usd` honored.
struct XAIFetcher: UsageFetcher {
    let providerID: ProviderID = .xai

    private struct ModelsResp: Decodable {
        struct Model: Decodable { let id: String? }
        let data: [Model]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.xai
        if let balance = c.balanceUsd {
            let limit = max(c.budgetUsd, balance, 0.01)
            return ProviderUsage(
                id: .xai, status: balance / limit < 0.2 ? .nearLimit : .ok,
                used: max(limit - balance, 0), limit: limit, unit: "USD",
                subtitle: "From config · console.x.ai",
                metricLabel: "\(HTTPClient.formatUSD(balance)) left",
                resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        }
        guard let key = ConfigLoader.resolveSecret(configured: c.apiKey, keychainKey: "xai.api_key", envName: c.apiKeyEnv, useKeychain: config.useKeychain) else {
            return .error(.xai, message: "Set \(c.apiKeyEnv) in env or Keychain")
        }
        do {
            let _: ModelsResp = try await HTTPClient.getJSON(
                url: "https://api.x.ai/v1/models",
                headers: ["Authorization": "Bearer \(key)"]
            )
            return ProviderUsage(
                id: .xai, status: .unavailable, used: 0, limit: max(c.budgetUsd, 0.01), unit: "USD",
                subtitle: "Key OK · no usage API · set balance_usd for tracking",
                metricLabel: "Auth OK", resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.xai, message: "Invalid xAI API key")
        }
    }
}

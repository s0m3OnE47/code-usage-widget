import Foundation

/// Validates the Gemini key via generativelanguage models list;
/// manual `balance_usd` is honored when set (no public spend API).
struct GeminiFetcher: UsageFetcher {
    let providerID: ProviderID = .gemini

    private struct ModelsResp: Decodable {
        struct Model: Decodable { let name: String? }
        let models: [Model]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.gemini
        if let balance = c.balanceUsd {
            let limit = max(c.budgetUsd, balance, 0.01)
            return ProviderUsage(
                id: .gemini, status: balance / limit < 0.2 ? .nearLimit : .ok,
                used: max(limit - balance, 0), limit: limit, unit: "USD",
                subtitle: "From config · aistudio.google.com",
                metricLabel: "\(HTTPClient.formatUSD(balance)) left",
                resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        }
        guard let key = ConfigLoader.resolveSecret(configured: c.apiKey, keychainKey: "gemini.api_key", envName: c.apiKeyEnv, useKeychain: config.useKeychain) else {
            return .error(.gemini, message: "Set \(c.apiKeyEnv) in env or Keychain")
        }
        do {
            let resp: ModelsResp = try await HTTPClient.getJSON(
                url: "https://generativelanguage.googleapis.com/v1/models?pageSize=1&key=\(key)"
            )
            let n = resp.models?.count ?? 0
            return ProviderUsage(
                id: .gemini, status: .unavailable, used: 0, limit: max(c.budgetUsd, 0.01), unit: "USD",
                subtitle: "Key OK (\(n > 0 ? "models listed" : "no models")) · set balance_usd for tracking",
                metricLabel: "Auth OK", resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.gemini, message: "Invalid Gemini API key")
        }
    }
}

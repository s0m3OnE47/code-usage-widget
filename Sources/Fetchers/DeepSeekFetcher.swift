import Foundation

struct DeepSeekFetcher: UsageFetcher {
    let providerID: ProviderID = .deepseek

    private struct BalanceResp: Decodable {
        struct Info: Decodable {
            let currency: String?
            let total_balance: String?
            let granted_balance: String?
            let topped_up_balance: String?
        }
        let is_available: Bool?
        let balance_infos: [Info]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let envName = config.providers.deepseek.apiKeyEnv
        guard let apiKey = ConfigLoader.resolveSecret(
            configured: config.providers.deepseek.apiKey,
            keychainKey: "deepseek.api_key",
            envName: envName,
            useKeychain: config.useKeychain
        ) else {
            return .error(.deepseek, message: "Set \(envName) in env")
        }

        do {
            let resp: BalanceResp = try await HTTPClient.getJSON(
                url: "https://api.deepseek.com/user/balance",
                headers: ["Authorization": "Bearer \(apiKey)", "Accept": "application/json"]
            )

            let infos = resp.balance_infos ?? []
            let preferred = infos.first(where: { $0.currency == "USD" }) ?? infos.first
            let total = Double(preferred?.total_balance ?? "0") ?? 0
            let granted = Double(preferred?.granted_balance ?? "0") ?? 0
            let topped = Double(preferred?.topped_up_balance ?? "0") ?? 0
            let budget = max(config.providers.deepseek.budgetUsd, 0.01)

            var status: UsageStatus = .ok
            if total <= 0 { status = .limited }
            else if total / budget < 0.2 { status = .nearLimit }
            if resp.is_available == false && total > 0 { status = .unavailable }

            let subtitle = "Granted \(HTTPClient.formatUSD(granted)) · Paid \(HTTPClient.formatUSD(topped))"

            return ProviderUsage(
                id: .deepseek,
                status: status,
                used: max(budget - total, 0),
                limit: budget,
                unit: "USD",
                subtitle: subtitle,
                metricLabel: "\(HTTPClient.formatUSD(total)) remaining",
                resetsAt: nil,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: []
            )
        } catch {
            return .error(.deepseek, message: "DeepSeek API error")
        }
    }
}

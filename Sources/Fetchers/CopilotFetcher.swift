import Foundation

/// Validates a GitHub token via GET /user. No personal Copilot quota API,
/// so this reports auth state; org billing lives on github.com/settings/billing.
struct CopilotFetcher: UsageFetcher {
    let providerID: ProviderID = .copilot

    private struct UserResp: Decodable { let login: String? }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let c = config.providers.copilot
        guard let token = ConfigLoader.resolveSecret(configured: c.githubToken, keychainKey: "copilot.github_token", envName: c.githubTokenEnv, useKeychain: config.useKeychain) else {
            return .error(.copilot, message: "Set \(c.githubTokenEnv) in env or Keychain")
        }
        do {
            let user: UserResp = try await HTTPClient.getJSON(
                url: "https://api.github.com/user",
                headers: ["Authorization": "Bearer \(token)", "Accept": "application/vnd.github+json"]
            )
            return ProviderUsage(
                id: .copilot, status: .unavailable, used: 0, limit: 100, unit: "%",
                subtitle: "@\(user.login ?? "github") · no quota API",
                metricLabel: "Auth OK", resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.copilot, message: "Invalid GitHub token")
        }
    }
}

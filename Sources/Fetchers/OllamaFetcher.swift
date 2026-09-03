import Foundation

/// Local Ollama: lists models via /api/tags. No quota — shows model count.
struct OllamaFetcher: UsageFetcher {
    let providerID: ProviderID = .ollama

    private struct TagsResp: Decodable {
        struct Model: Decodable { let name: String? }
        let models: [Model]?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        let base = config.providers.ollama.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = base.isEmpty ? "http://localhost:11434" : base.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        do {
            let resp: TagsResp = try await HTTPClient.getJSON(url: "\(prefix)/api/tags")
            let names = (resp.models ?? []).compactMap { $0.name }
            return ProviderUsage(
                id: .ollama, status: .ok, used: 0, limit: 100, unit: "%",
                subtitle: "Local · \(names.prefix(2).joined(separator: ", "))\(names.count > 2 ? "…" : "")",
                metricLabel: "\(names.count) models",
                resetsAt: nil, errorMessage: nil, isRefreshing: false, subMetrics: []
            )
        } catch {
            return .error(.ollama, message: "Ollama not running at \(prefix)")
        }
    }
}

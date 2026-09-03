import Foundation

/// Codable usage data shared between the host app and WidgetKit extension.
struct ProviderUsageSnapshot: Codable, Identifiable {
    let id: String
    let displayName: String
    let status: String
    let percentUsed: Double
    let metricLabel: String
    let subtitle: String
}

struct UsageSnapshot: Codable {
    let updatedAt: Date
    let providers: [ProviderUsageSnapshot]

    static let empty = UsageSnapshot(updatedAt: .distantPast, providers: [])

    enum CodingKeys: String, CodingKey {
        case updatedAt, providers
    }

    init(updatedAt: Date, providers: [ProviderUsageSnapshot]) {
        self.updatedAt = updatedAt
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = try c.decode([ProviderUsageSnapshot].self, forKey: .providers)
        if let interval = try? c.decode(TimeInterval.self, forKey: .updatedAt) {
            updatedAt = Date(timeIntervalSince1970: interval)
        } else if let string = try? c.decode(String.self, forKey: .updatedAt) {
            updatedAt = ISO8601DateFormatter().date(from: string) ?? .distantPast
        } else {
            updatedAt = .distantPast
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
        try c.encode(providers, forKey: .providers)
    }
}

#if !WIDGET_EXTENSION
extension UsageSnapshot {
    static func from(_ providers: [ProviderUsage], updatedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            updatedAt: updatedAt,
            providers: providers.map {
                ProviderUsageSnapshot(
                    id: $0.id.rawValue,
                    displayName: $0.id.displayName,
                    status: $0.status.rawValue,
                    percentUsed: $0.percentUsed,
                    metricLabel: $0.metricLabel,
                    subtitle: $0.subtitle
                )
            }
        )
    }
}
#endif

import Foundation
import SwiftUI

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case cursor
    case commandcode
    case deepseek
    case openai
    case sarvam
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .commandcode: return "CommandCode"
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .sarvam: return "Sarvam AI"
        case .opencode: return "OpenCode"
        }
    }

    var accentColor: Color {
        switch self {
        case .cursor: return Color(red: 0.35, green: 0.72, blue: 1.0)
        case .commandcode: return Color(red: 0.62, green: 0.45, blue: 1.0)
        case .deepseek: return Color(red: 0.45, green: 0.58, blue: 1.0)
        case .openai: return Color(red: 0.10, green: 0.78, blue: 0.55)
        case .sarvam: return Color(red: 1.0, green: 0.72, blue: 0.35)
        case .opencode: return Color(red: 0.25, green: 0.88, blue: 0.65)
        }
    }

    func subMetricColor(index: Int) -> Color {
        switch self {
        case .cursor:
            return index == 0
                ? Color(red: 0.35, green: 0.72, blue: 1.0)
                : Color(red: 0.72, green: 0.55, blue: 1.0)
        default:
            return accentColor.opacity(0.85)
        }
    }

    var systemIcon: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .commandcode: return "terminal.fill"
        case .deepseek: return "fish.fill"
        case .openai: return "sparkles"
        case .sarvam: return "waveform.circle.fill"
        case .opencode: return "curlybraces"
        }
    }

    var billingURL: URL? {
        switch self {
        case .cursor: return URL(string: "https://cursor.com/dashboard")
        case .commandcode: return URL(string: "https://commandcode.ai/settings/billing")
        case .deepseek: return URL(string: "https://platform.deepseek.com/usage")
        case .openai: return URL(string: "https://platform.openai.com/account/billing")
        case .sarvam: return URL(string: "https://indus.sarvam.ai/billing")
        case .opencode: return URL(string: "https://opencode.ai")
        }
    }
}

enum UsageStatus: String, Codable {
    case ok
    case nearLimit
    case limited
    case authError
    case unavailable
    case loading
}

struct UsageSubMetric: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Double
}

struct ProviderUsage: Identifiable, Equatable {
    let id: ProviderID
    var status: UsageStatus
    var used: Double
    var limit: Double
    var unit: String
    var subtitle: String
    var metricLabel: String
    var resetsAt: Date?
    var errorMessage: String?
    var isRefreshing: Bool
    var subMetrics: [UsageSubMetric]

    var percentUsed: Double {
        guard limit > 0 else { return 0 }
        return min(100, max(0, (used / limit) * 100))
    }

    var percentRemaining: Double {
        100 - percentUsed
    }

    static func placeholder(_ provider: ProviderID) -> ProviderUsage {
        ProviderUsage(
            id: provider,
            status: .loading,
            used: 0,
            limit: 100,
            unit: "",
            subtitle: "Loading…",
            metricLabel: "—",
            resetsAt: nil,
            errorMessage: nil,
            isRefreshing: true,
            subMetrics: []
        )
    }

    static func error(_ provider: ProviderID, message: String) -> ProviderUsage {
        ProviderUsage(
            id: provider,
            status: .authError,
            used: 0,
            limit: 100,
            unit: "",
            subtitle: message,
            metricLabel: "—",
            resetsAt: nil,
            errorMessage: message,
            isRefreshing: false,
            subMetrics: []
        )
    }
}

struct WidgetConfig: Codable {
    var pollIntervalSeconds: Int
    var browser: Browser
    var firefoxProfile: String
    var providers: ProviderConfigs
    var disabledProviders: [String]
    var privacyMode: Bool
    var notificationsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds = "poll_interval_seconds"
        case browser
        case firefoxProfile = "firefox_profile"
        case providers
        case disabledProviders = "disabled_providers"
        case privacyMode = "privacy_mode"
        case notificationsEnabled = "notifications_enabled"
    }

    static let `default` = WidgetConfig(
        pollIntervalSeconds: 30,
        browser: .auto,
        firefoxProfile: "auto",
        providers: .default,
        disabledProviders: [],
        privacyMode: false,
        notificationsEnabled: true
    )

    init(pollIntervalSeconds: Int, browser: Browser, firefoxProfile: String, providers: ProviderConfigs, disabledProviders: [String] = [], privacyMode: Bool = false, notificationsEnabled: Bool = true) {
        self.pollIntervalSeconds = pollIntervalSeconds
        self.browser = browser
        self.firefoxProfile = firefoxProfile
        self.providers = providers
        self.disabledProviders = disabledProviders
        self.privacyMode = privacyMode
        self.notificationsEnabled = notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 30
        browser = try c.decodeIfPresent(Browser.self, forKey: .browser) ?? .auto
        firefoxProfile = try c.decodeIfPresent(String.self, forKey: .firefoxProfile) ?? "auto"
        providers = try c.decode(ProviderConfigs.self, forKey: .providers)
        disabledProviders = try c.decodeIfPresent([String].self, forKey: .disabledProviders) ?? []
        privacyMode = try c.decodeIfPresent(Bool.self, forKey: .privacyMode) ?? false
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
    }

    /// Clamped refresh interval (10s minimum, 1h maximum).
    var effectivePollInterval: TimeInterval {
        TimeInterval(min(max(pollIntervalSeconds, 10), 3600))
    }

    func isEnabled(_ id: ProviderID) -> Bool {
        !disabledProviders.contains(id.rawValue)
    }

    var enabledProviderIDs: [ProviderID] {
        ProviderID.allCases.filter { isEnabled($0) }
    }
}

struct ProviderConfigs: Codable {
    var deepseek: DeepSeekConfig
    var openai: OpenAIConfig
    var sarvam: SarvamConfig
    var opencode: OpenCodeConfig
    var commandcode: CommandCodeConfig

    enum CodingKeys: String, CodingKey {
        case deepseek, openai, sarvam, opencode, commandcode
    }

    static let `default` = ProviderConfigs(
        deepseek: DeepSeekConfig(apiKeyEnv: "DEEPSEEK_API_KEY", budgetUsd: 50),
        openai: OpenAIConfig(),
        sarvam: SarvamConfig(apiKeyEnv: "SARVAM_API_KEY"),
        opencode: OpenCodeConfig(apiKeyEnv: "OPENCODE_API_KEY"),
        commandcode: CommandCodeConfig(sessionCookieName: "__Secure-commandcode_prod_.session_token")
    )

    init(
        deepseek: DeepSeekConfig,
        openai: OpenAIConfig,
        sarvam: SarvamConfig,
        opencode: OpenCodeConfig,
        commandcode: CommandCodeConfig
    ) {
        self.deepseek = deepseek
        self.openai = openai
        self.sarvam = sarvam
        self.opencode = opencode
        self.commandcode = commandcode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deepseek = try c.decodeIfPresent(DeepSeekConfig.self, forKey: .deepseek)
            ?? DeepSeekConfig(apiKeyEnv: "DEEPSEEK_API_KEY", budgetUsd: 50)
        openai = try c.decodeIfPresent(OpenAIConfig.self, forKey: .openai) ?? OpenAIConfig()
        sarvam = try c.decodeIfPresent(SarvamConfig.self, forKey: .sarvam)
            ?? SarvamConfig(apiKeyEnv: "SARVAM_API_KEY")
        opencode = try c.decodeIfPresent(OpenCodeConfig.self, forKey: .opencode)
            ?? OpenCodeConfig(apiKeyEnv: "OPENCODE_API_KEY")
        commandcode = try c.decodeIfPresent(CommandCodeConfig.self, forKey: .commandcode)
            ?? CommandCodeConfig(sessionCookieName: "__Secure-commandcode_prod_.session_token")
    }
}

struct OpenAIConfig: Codable {
    var apiKeyEnv: String
    var apiKey: String?
    var adminKeyEnv: String
    var adminKey: String?
    var sessionToken: String?
    var sessionToken0: String?
    var sessionToken1: String?
    var sessionKey: String?
    var accessToken: String?
    var balanceUsd: Double?
    var budgetUsd: Double

    enum CodingKeys: String, CodingKey {
        case apiKeyEnv = "api_key_env"
        case apiKey = "api_key"
        case adminKeyEnv = "admin_key_env"
        case adminKey = "admin_key"
        case sessionToken = "session_token"
        case sessionToken0 = "session_token_0"
        case sessionToken1 = "session_token_1"
        case sessionKey = "session_key"
        case accessToken = "access_token"
        case balanceUsd = "balance_usd"
        case budgetUsd = "budget_usd"
    }

    init(
        apiKeyEnv: String = "OPENAI_API_KEY",
        apiKey: String? = nil,
        adminKeyEnv: String = "OPENAI_ADMIN_KEY",
        adminKey: String? = nil,
        sessionToken: String? = nil,
        sessionToken0: String? = nil,
        sessionToken1: String? = nil,
        sessionKey: String? = nil,
        accessToken: String? = nil,
        balanceUsd: Double? = nil,
        budgetUsd: Double = 50
    ) {
        self.apiKeyEnv = apiKeyEnv
        self.apiKey = apiKey
        self.adminKeyEnv = adminKeyEnv
        self.adminKey = adminKey
        self.sessionToken = sessionToken
        self.sessionToken0 = sessionToken0
        self.sessionToken1 = sessionToken1
        self.sessionKey = sessionKey
        self.accessToken = accessToken
        self.balanceUsd = balanceUsd
        self.budgetUsd = budgetUsd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKeyEnv = try c.decodeIfPresent(String.self, forKey: .apiKeyEnv) ?? "OPENAI_API_KEY"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        adminKeyEnv = try c.decodeIfPresent(String.self, forKey: .adminKeyEnv) ?? "OPENAI_ADMIN_KEY"
        adminKey = try c.decodeIfPresent(String.self, forKey: .adminKey)
        sessionToken = try c.decodeIfPresent(String.self, forKey: .sessionToken)
        sessionToken0 = try c.decodeIfPresent(String.self, forKey: .sessionToken0)
        sessionToken1 = try c.decodeIfPresent(String.self, forKey: .sessionToken1)
        sessionKey = try c.decodeIfPresent(String.self, forKey: .sessionKey)
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
        balanceUsd = try c.decodeIfPresent(Double.self, forKey: .balanceUsd)
        budgetUsd = try c.decodeIfPresent(Double.self, forKey: .budgetUsd) ?? 50
    }
}

struct DeepSeekConfig: Codable {
    var apiKeyEnv: String
    var apiKey: String?
    var budgetUsd: Double

    enum CodingKeys: String, CodingKey {
        case apiKeyEnv = "api_key_env"
        case apiKey = "api_key"
        case budgetUsd = "budget_usd"
    }

    init(apiKeyEnv: String, apiKey: String? = nil, budgetUsd: Double) {
        self.apiKeyEnv = apiKeyEnv
        self.apiKey = apiKey
        self.budgetUsd = budgetUsd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKeyEnv = try c.decodeIfPresent(String.self, forKey: .apiKeyEnv) ?? "DEEPSEEK_API_KEY"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        budgetUsd = try c.decodeIfPresent(Double.self, forKey: .budgetUsd) ?? 50
    }
}

struct SarvamConfig: Codable {
    var apiKeyEnv: String
    var apiKey: String?
    var sessionToken: String?
    var creditLimitInr: Double
    var creditsRemainingInr: Double?

    enum CodingKeys: String, CodingKey {
        case apiKeyEnv = "api_key_env"
        case apiKey = "api_key"
        case sessionToken = "session_token"
        case creditLimitInr = "credit_limit_inr"
        case creditsRemainingInr = "credits_remaining_inr"
    }

    init(
        apiKeyEnv: String,
        apiKey: String? = nil,
        sessionToken: String? = nil,
        creditLimitInr: Double = 100,
        creditsRemainingInr: Double? = nil
    ) {
        self.apiKeyEnv = apiKeyEnv
        self.apiKey = apiKey
        self.sessionToken = sessionToken
        self.creditLimitInr = creditLimitInr
        self.creditsRemainingInr = creditsRemainingInr
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKeyEnv = try c.decodeIfPresent(String.self, forKey: .apiKeyEnv) ?? "SARVAM_API_KEY"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        sessionToken = try c.decodeIfPresent(String.self, forKey: .sessionToken)
        creditLimitInr = try c.decodeIfPresent(Double.self, forKey: .creditLimitInr) ?? 100
        creditsRemainingInr = try c.decodeIfPresent(Double.self, forKey: .creditsRemainingInr)
    }
}

struct OpenCodeConfig: Codable {
    var apiKeyEnv: String
    var apiKey: String?
    var sessionToken: String?

    enum CodingKeys: String, CodingKey {
        case apiKeyEnv = "api_key_env"
        case apiKey = "api_key"
        case sessionToken = "session_token"
    }

    init(apiKeyEnv: String, apiKey: String? = nil, sessionToken: String? = nil) {
        self.apiKeyEnv = apiKeyEnv
        self.apiKey = apiKey
        self.sessionToken = sessionToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKeyEnv = try c.decodeIfPresent(String.self, forKey: .apiKeyEnv) ?? "OPENCODE_API_KEY"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        sessionToken = try c.decodeIfPresent(String.self, forKey: .sessionToken)
    }
}

struct CommandCodeConfig: Codable {
    var sessionCookieName: String
    var sessionToken: String?

    enum CodingKeys: String, CodingKey {
        case sessionCookieName = "session_cookie_name"
        case sessionToken = "session_token"
    }

    init(sessionCookieName: String, sessionToken: String? = nil) {
        self.sessionCookieName = sessionCookieName
        self.sessionToken = sessionToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionCookieName = try c.decodeIfPresent(String.self, forKey: .sessionCookieName)
            ?? "__Secure-commandcode_prod_.session_token"
        sessionToken = try c.decodeIfPresent(String.self, forKey: .sessionToken)
    }
}

struct WindowPosition: Codable {
    var x: Double
    var y: Double
}

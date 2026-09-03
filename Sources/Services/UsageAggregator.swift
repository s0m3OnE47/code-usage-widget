import Foundation
import Combine
import WidgetKit
import UserNotifications

@MainActor
final class UsageAggregator: ObservableObject {
    @Published private(set) var providers: [ProviderUsage] = ProviderID.sortedAllCases.map { .placeholder($0) }
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var configWarnings: [String] = []
    @Published private(set) var privacyMode = false

    private var config: WidgetConfig
    private var timer: Timer?
    private var timerInterval: TimeInterval = 30
    private var fetchTask: Task<Void, Never>?
    private var currentFetchGeneration = UUID()
    private var lastNotifiedPercent: [ProviderID: Double] = [:]

    private let fetchers: [UsageFetcher] = [
        CursorFetcher(),
        CommandCodeFetcher(),
        DeepSeekFetcher(),
        OpenAIFetcher(),
        SarvamFetcher(),
        OpenCodeFetcher(),
        AnthropicFetcher(),
        GeminiFetcher(),
        XAIFetcher(),
        CopilotFetcher(),
        OllamaFetcher(),
        OpenRouterFetcher(),
        MetaFetcher(),
    ]

    init(config: WidgetConfig = ConfigLoader.load()) {
        self.config = config
    }

    func start() {
        if config.notificationsEnabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        refresh()
        scheduleTimerIfNeeded(force: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fetchTask?.cancel()
    }

    private func scheduleTimerIfNeeded(force: Bool = false) {
        let interval = config.effectivePollInterval
        guard force || timer == nil || abs(timerInterval - interval) > 0.5 else { return }
        timer?.invalidate()
        timerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let (cfg, warnings) = ConfigLoader.loadWithWarnings()
        config = cfg
        configWarnings = warnings
        privacyMode = cfg.privacyMode
        scheduleTimerIfNeeded()
        let enabledIDs = Set(cfg.enabledProviderIDs)
        fetchTask?.cancel()
        isRefreshing = true
        providers = ProviderID.sortedAllCases.filter { enabledIDs.contains($0) }.map { id in
            providers.first(where: { $0.id == id }) ?? .placeholder(id)
        }.map { usage in
            var u = usage
            u.isRefreshing = true
            return u
        }

        let generation = UUID()
        currentFetchGeneration = generation

        fetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self, self.currentFetchGeneration == generation else { return }
                    self.isRefreshing = false
                }
            }

            let cfg = self.config
            let activeFetchers = self.fetchers.filter { enabledIDs.contains($0.providerID) }
            let results = await withTaskGroup(of: ProviderUsage.self) { group in
                for fetcher in activeFetchers {
                    group.addTask { await fetcher.fetch(config: cfg) }
                }
                var collected: [ProviderUsage] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            guard !Task.isCancelled, self.currentFetchGeneration == generation else { return }

            var ordered = cfg.enabledProviderIDs.compactMap { id in
                results.first(where: { $0.id == id })
            }
            if cfg.privacyMode {
                ordered = ordered.map { u in
                    var m = u
                    m.metricLabel = "•••"
                    m.subtitle = u.id.displayName
                    return m
                }
            }
            self.providers = ordered
            let updated = Date()
            self.lastUpdated = updated
            if !ordered.isEmpty {
                UsageCache.save(UsageSnapshot.from(ordered, updatedAt: updated))
                HistoryStore.record(ordered, at: updated)
                WidgetCenter.shared.reloadAllTimelines()
            }
            self.notifyIfNeeded(ordered, enabled: cfg.notificationsEnabled)
        }
    }

    private func notifyIfNeeded(_ usages: [ProviderUsage], enabled: Bool) {
        guard enabled else { return }
        for u in usages {
            let pct = u.percentUsed
            let prev = lastNotifiedPercent[u.id] ?? 0
            defer { lastNotifiedPercent[u.id] = pct }
            let crossed80 = pct >= 80 && prev < 80
            let crossed100 = pct >= 100 && prev < 100
            guard crossed80 || crossed100 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(u.id.displayName) usage \(Int(pct.rounded()))%"
            content.body = crossed100 ? "Limit reached." : "Near limit."
            let req = UNNotificationRequest(
                identifier: "cuw-\(u.id.rawValue)-\(crossed100 ? "100" : "80")",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req)
        }
    }

    func reloadConfig() {
        config = ConfigLoader.load()
    }
}

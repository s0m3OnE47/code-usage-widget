import Foundation
import Combine
import WidgetKit

@MainActor
final class UsageAggregator: ObservableObject {
    @Published private(set) var providers: [ProviderUsage] = ProviderID.allCases.map { .placeholder($0) }
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private var config: WidgetConfig
    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var currentFetchGeneration = UUID()

    private let fetchers: [UsageFetcher] = [
        CursorFetcher(),
        CommandCodeFetcher(),
        DeepSeekFetcher(),
        OpenAIFetcher(),
        SarvamFetcher(),
        OpenCodeFetcher(),
    ]

    init(config: WidgetConfig = ConfigLoader.load()) {
        self.config = config
    }

    func start() {
        refresh()
        let interval = TimeInterval(max(config.pollIntervalSeconds, 10))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fetchTask?.cancel()
    }

    func refresh() {
        config = ConfigLoader.load()
        fetchTask?.cancel()
        isRefreshing = true
        providers = providers.map { usage in
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
            let results = await withTaskGroup(of: ProviderUsage.self) { group in
                for fetcher in self.fetchers {
                    group.addTask { await fetcher.fetch(config: cfg) }
                }
                var collected: [ProviderUsage] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            guard !Task.isCancelled, self.currentFetchGeneration == generation else { return }

            let ordered = ProviderID.allCases.compactMap { id in
                results.first(where: { $0.id == id })
            }
            self.providers = ordered
            let updated = Date()
            self.lastUpdated = updated
            UsageCache.save(UsageSnapshot.from(ordered, updatedAt: updated))
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func reloadConfig() {
        config = ConfigLoader.load()
    }
}

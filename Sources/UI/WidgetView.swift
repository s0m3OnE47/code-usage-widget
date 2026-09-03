import SwiftUI

struct WidgetView: View {
    @EnvironmentObject var aggregator: UsageAggregator
    @EnvironmentObject var widgetState: WidgetState

    var body: some View {
        ZStack {
            Rectangle()
                .fill(widgetState.focused ? .regularMaterial : .ultraThinMaterial)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 8) {
                            ForEach(aggregator.providers) { usage in
                                ProviderRowView(usage: usage)
                                    .id(usage.id.rawValue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                    }
                    .frame(maxHeight: WidgetLayout.height - 48)
                    .onChange(of: widgetState.scrollTargetID) { _, target in
                        guard let target,
                              aggregator.providers.contains(where: { $0.id.rawValue == target })
                        else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }

            if widgetState.dragging {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: WidgetLayout.width, height: WidgetLayout.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    widgetState.focused ? .white.opacity(0.12) : .white.opacity(0.04),
                    lineWidth: 0.5
                )
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("AI Usage")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(.white.opacity(0.95))
            }
            Spacer()
            if let updated = aggregator.lastUpdated {
                Text(timeAgo(updated))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
            scrollButton(systemName: "chevron.up", help: "Scroll up") {
                scrollPage(up: true)
            }
            scrollButton(systemName: "chevron.down", help: "Scroll down") {
                scrollPage(up: false)
            }
            Button(action: { aggregator.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .rotationEffect(.degrees(aggregator.isRefreshing ? 360 : 0))
                    .animation(
                        aggregator.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: aggregator.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh (⌘R)")
        }
        .frame(height: 28)
    }

    private func scrollButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Deterministic paging that works even when wheel/drag gestures
    /// never reach the panel (e.g. non-key desktop-level window).
    private func scrollPage(up: Bool) {
        let ids = aggregator.providers.map(\.id.rawValue)
        guard !ids.isEmpty else { return }
        let current = widgetState.scrollIndex.flatMap { idx in
            (0..<ids.count).contains(idx) ? idx : nil
        } ?? (up ? ids.count - 1 : 0)
        let next = min(max(up ? current - 4 : current + 4, 0), ids.count - 1)
        widgetState.scrollIndex = next
        widgetState.scrollTargetID = ids[next]
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 5 { return "now" }
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
    }
}

@MainActor
final class WidgetState: ObservableObject {
    @Published var dragging = false
    @Published var focused = false
    @Published var scrollTargetID: String?
    @Published var scrollIndex: Int?
}

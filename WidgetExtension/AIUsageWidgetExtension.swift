import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: UsageCache.load() ?? previewSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = UsageCache.load() ?? .empty
        let entry = UsageEntry(date: Date(), snapshot: snapshot)
        // Host pushes reloads on every poll; 5m fallback keeps stale banners fresh.
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var previewSnapshot: UsageSnapshot {
        UsageSnapshot(
            updatedAt: Date(),
            providers: [
                ProviderUsageSnapshot(id: "cursor", displayName: "Cursor", status: "ok", percentUsed: 42, metricLabel: "58% left", subtitle: "Pro plan"),
                ProviderUsageSnapshot(id: "openai", displayName: "OpenAI", status: "ok", percentUsed: 71, metricLabel: "$1.45 left", subtitle: "Platform credits"),
                ProviderUsageSnapshot(id: "deepseek", displayName: "DeepSeek", status: "nearLimit", percentUsed: 85, metricLabel: "$0.75 left", subtitle: "API credits"),
                ProviderUsageSnapshot(id: "anthropic", displayName: "Anthropic", status: "ok", percentUsed: 18, metricLabel: "Auth OK", subtitle: "API key"),
                ProviderUsageSnapshot(id: "ollama", displayName: "Ollama", status: "ok", percentUsed: 0, metricLabel: "3 models", subtitle: "Local"),
                ProviderUsageSnapshot(id: "openrouter", displayName: "OpenRouter", status: "limited", percentUsed: 100, metricLabel: "$0.00 left", subtitle: "Credits"),
            ]
        )
    }
}

struct AIUsageWidgetEntryView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    private var columns: [GridItem] {
        // Single column on Small; two columns fill the width on M/L.
        switch family {
        case .systemSmall: return [GridItem(.flexible(), spacing: 8)]
        default: return [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("AI Usage")
                    .font(.caption.weight(.semibold))
                Spacer()
                StatusDot(providers: entry.snapshot.providers)
                if entry.snapshot.providers.isEmpty {
                    Text("Open app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(relativeTime(entry.snapshot.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.snapshot.providers.isEmpty {
                Text("Waiting for usage data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // Always alphabetical by display name (also normalizes
                // snapshots cached before sorting was enforced).
                let ordered = entry.snapshot.providers.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                let visible = Array(ordered.prefix(maxCells))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(visible) { provider in
                        ProviderWidgetRow(provider: provider)
                    }
                }
                if entry.snapshot.providers.count > maxCells {
                    Text("+\(entry.snapshot.providers.count - maxCells) more in app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .containerBackground(for: .widget) {
            Color(.windowBackgroundColor).opacity(0.85)
        }
        .widgetURL(URL(string: "codeusagewidget://show"))
    }

    /// Cell budget per family. Large fits all 13 providers (2×7).
    private var maxCells: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 6
        case .systemLarge: return 14
        default: return 6
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 5 { return "now" }
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}

/// Worst-status dot in the header: red if anything limited, orange if near limit.
struct StatusDot: View {
    let providers: [ProviderUsageSnapshot]

    var body: some View {
        let level = worstLevel
        if level > 0 {
            Circle()
                .fill(level == 2 ? Color.red : Color.orange)
                .frame(width: 7, height: 7)
        }
    }

    private var worstLevel: Int {
        var level = 0
        for p in providers {
            if p.status == "authError" || p.status == "limited" { return 2 }
            if p.status == "nearLimit" { level = 1 }
        }
        return level
    }
}

struct ProviderWidgetRow: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        Group {
            if let url = billingURL {
                Link(destination: url) { rowContent }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 14, height: 14)
                    .background(statusColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(trailingLabel)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.6))
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: max(4, geo.size.width * min(max(provider.percentUsed, 0), 100) / 100))
                }
            }
            .frame(height: 3)
        }
        .padding(4)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    /// Line-1 trailing text: percent remaining (e.g. "93% left").
    /// Absolute amounts stay in the floating panel; "Auth OK" is kept for
    /// key checks without a usage API, dashes for errors/loading.
    private var trailingLabel: String {
        switch provider.status {
        case "authError", "loading":
            return "—"
        case "unavailable":
            return provider.metricLabel
        default:
            let remaining = 100 - min(max(provider.percentUsed, 0), 100)
            return "\(Int(remaining.rounded()))% left"
        }
    }

    private var billingURL: URL? {
        switch provider.id {
        case "cursor": return URL(string: "https://cursor.com/dashboard")
        case "commandcode": return URL(string: "https://commandcode.ai/settings/billing")
        case "deepseek": return URL(string: "https://platform.deepseek.com/usage")
        case "openai": return URL(string: "https://platform.openai.com/account/billing")
        case "sarvam": return URL(string: "https://indus.sarvam.ai/billing")
        case "opencode": return URL(string: "https://opencode.ai")
        case "anthropic": return URL(string: "https://console.anthropic.com/settings/billing")
        case "gemini": return URL(string: "https://aistudio.google.com/")
        case "xai": return URL(string: "https://console.x.ai/")
        case "copilot": return URL(string: "https://github.com/settings/billing")
        case "ollama": return URL(string: "https://ollama.com/")
        case "openrouter": return URL(string: "https://openrouter.ai/activity")
        case "meta": return URL(string: "https://dev.meta.ai/usage/")
        default: return nil
        }
    }

    private var statusColor: Color {
        if provider.status == "authError" || provider.status == "limited" { return .red }
        if provider.status == "nearLimit" { return .orange }
        return accent(for: provider.id)
    }

    private var iconName: String {
        switch provider.id {
        case "cursor": return "cursorarrow.rays"
        case "commandcode": return "terminal.fill"
        case "deepseek": return "fish.fill"
        case "openai": return "sparkles"
        case "sarvam": return "waveform.circle.fill"
        case "opencode": return "curlybraces"
        case "anthropic": return "brain.head.profile"
        case "gemini": return "sparkle"
        case "xai": return "bolt.fill"
        case "copilot": return "chevron.left.forwardslash.chevron.right"
        case "ollama": return "server.rack"
        case "openrouter": return "network"
        case "meta": return "infinity"
        default: return "circle.grid.2x2"
        }
    }

    private func accent(for id: String) -> Color {
        switch id {
        case "cursor": return Color(red: 0.35, green: 0.72, blue: 1.0)
        case "commandcode": return Color(red: 0.62, green: 0.45, blue: 1.0)
        case "deepseek": return Color(red: 0.45, green: 0.58, blue: 1.0)
        case "openai": return Color(red: 0.10, green: 0.78, blue: 0.55)
        case "sarvam": return Color(red: 1.0, green: 0.72, blue: 0.35)
        case "opencode": return Color(red: 0.25, green: 0.88, blue: 0.65)
        case "anthropic": return Color(red: 0.85, green: 0.55, blue: 0.35)
        case "gemini": return Color(red: 0.45, green: 0.55, blue: 0.95)
        case "xai": return Color(red: 0.75, green: 0.75, blue: 0.80)
        case "copilot": return Color(red: 0.55, green: 0.60, blue: 0.65)
        case "ollama": return Color(red: 0.95, green: 0.95, blue: 0.95)
        case "openrouter": return Color(red: 0.55, green: 0.85, blue: 0.95)
        case "meta": return Color(red: 0.0, green: 0.39, blue: 0.88)
        default: return .accentColor
        }
    }
}

@main
struct AIUsageWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        AIUsageWidget()
    }
}

struct AIUsageWidget: Widget {
    let kind = "AIUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            AIUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("Usage limits for Cursor, OpenAI, Anthropic, Gemini, and other AI providers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

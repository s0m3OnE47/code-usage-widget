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
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var previewSnapshot: UsageSnapshot {
        UsageSnapshot(
            updatedAt: Date(),
            providers: [
                ProviderUsageSnapshot(id: "cursor", displayName: "Cursor", status: "ok", percentUsed: 42, metricLabel: "58% left", subtitle: "Pro plan"),
                ProviderUsageSnapshot(id: "openai", displayName: "OpenAI", status: "ok", percentUsed: 71, metricLabel: "$1.45 left", subtitle: "Platform credits"),
            ]
        )
    }
}

struct CodeUsageWidgetEntryView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold))
                Text("AI Usage")
                    .font(.caption.weight(.semibold))
                Spacer()
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
                let visible = Array(entry.snapshot.providers.prefix(maxRows))
                ForEach(visible) { provider in
                    ProviderWidgetRow(provider: provider)
                }
                if entry.snapshot.providers.count > maxRows {
                    Text("+\(entry.snapshot.providers.count - maxRows) more in app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            Color(.windowBackgroundColor).opacity(0.85)
        }
        .widgetURL(URL(string: "codeusagewidget://show"))
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 4
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}

struct ProviderWidgetRow: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(provider.metricLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: max(4, geo.size.width * provider.percentUsed / 100))
                }
            }
            .frame(height: 5)
        }
    }

    private var statusColor: Color {
        if provider.status == "authError" || provider.status == "limited" { return .red }
        if provider.status == "nearLimit" { return .orange }
        return accent(for: provider.id)
    }

    private func accent(for id: String) -> Color {
        switch id {
        case "cursor": return Color(red: 0.35, green: 0.72, blue: 1.0)
        case "commandcode": return Color(red: 0.62, green: 0.45, blue: 1.0)
        case "deepseek": return Color(red: 0.45, green: 0.58, blue: 1.0)
        case "openai": return Color(red: 0.10, green: 0.78, blue: 0.55)
        case "sarvam": return Color(red: 1.0, green: 0.72, blue: 0.35)
        case "opencode": return Color(red: 0.25, green: 0.88, blue: 0.65)
        default: return .accentColor
        }
    }
}

@main
struct CodeUsageWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        CodeUsageWidget()
    }
}

struct CodeUsageWidget: Widget {
    let kind = "CodeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            CodeUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("Usage limits for Cursor, OpenAI, DeepSeek, and other AI providers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

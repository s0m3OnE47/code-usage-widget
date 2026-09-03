import SwiftUI

struct ProviderRowView: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProviderIconView(
                    provider: usage.id,
                    status: usage.status,
                    isRefreshing: usage.isRefreshing
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(usage.id.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        if let url = usage.id.billingURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Open billing")
                        }
                        Spacer()
                        Text(usage.metricLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(labelColor)
                    }
                    Text(subtitleText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(usage.id == .cursor ? 2 : 1)
                }
            }

            if usage.status == .authError || usage.status == .unavailable {
                errorBanner
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    barLabel(usage.id == .cursor ? "Total usage" : "Included usage", percent: usage.percentUsed)
                    AnimatedProgressBar(
                        percent: usage.percentUsed,
                        accent: usage.id.accentColor,
                        status: usage.status
                    )

                    ForEach(Array(usage.subMetrics.enumerated()), id: \.element.id) { index, sub in
                        barLabel(sub.label, percent: sub.percent)
                        AnimatedProgressBar(
                            percent: sub.percent,
                            accent: usage.id.subMetricColor(index: index),
                            status: subStatus(sub.percent)
                        )
                    }
                }

                HStack {
                    Text(String(format: "%.0f%% used", usage.percentUsed))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    if usage.status == .nearLimit {
                        Text("Near limit")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    } else if usage.status == .limited {
                        Text("Limit reached")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }

                HistorySparkline(provider: usage.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(usage.id.accentColor.opacity(0.28), lineWidth: 0.5)
                )
        )
    }

    private func barLabel(_ title: String, percent: Double) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(String(format: "%.0f%%", percent))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func subStatus(_ percent: Double) -> UsageStatus {
        if percent >= 100 { return .limited }
        if percent >= 80 { return .nearLimit }
        return .ok
    }

    private var labelColor: Color {
        switch usage.status {
        case .limited: return .red
        case .nearLimit: return .orange
        case .authError: return .secondary
        default: return .white.opacity(0.92)
        }
    }

    private var subtitleText: String {
        if let err = usage.errorMessage { return err }
        return usage.subtitle
    }

    private var errorBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(usage.errorMessage ?? usage.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

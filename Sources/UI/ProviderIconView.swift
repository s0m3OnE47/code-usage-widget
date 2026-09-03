import SwiftUI

struct ProviderIconView: View {
    let provider: ProviderID
    let status: UsageStatus
    let isRefreshing: Bool

    @State private var pulse = false

    private var shouldPulseFast: Bool {
        status == .nearLimit || status == .limited
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(provider.accentColor.opacity(0.15))
                .frame(width: 32, height: 32)
                .scaleEffect(pulse ? (shouldPulseFast ? 1.12 : 1.06) : 1.0)
                .opacity(pulse ? 0.7 : 1.0)

            iconContent
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(provider.accentColor)
        }
        .onAppear { startPulse() }
        .onChange(of: isRefreshing) { _, refreshing in
            if refreshing { startPulse() }
        }
        .onChange(of: status) { _, _ in startPulse() }
    }

    @ViewBuilder
    private var iconContent: some View {
        switch provider {
        case .cursor:
            Image(systemName: "cursorarrow.rays")
        case .commandcode:
            Image(systemName: "terminal.fill")
        case .deepseek:
            Image(systemName: "fish.fill")
        case .openai:
            Image(systemName: "sparkles")
        case .sarvam:
            Text("Sa")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        case .opencode:
            Text("{")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .offset(x: pulse ? 1 : -1)
        case .anthropic:
            Image(systemName: "brain.head.profile")
        case .gemini:
            Image(systemName: "sparkle")
        case .xai:
            Image(systemName: "bolt.fill")
        case .copilot:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
        case .ollama:
            Image(systemName: "server.rack")
        case .openrouter:
            Image(systemName: "network")
        case .meta:
            Image(systemName: "infinity")
        }
    }

    private func startPulse() {
        let duration = shouldPulseFast ? 0.6 : (isRefreshing ? 1.0 : 1.8)
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

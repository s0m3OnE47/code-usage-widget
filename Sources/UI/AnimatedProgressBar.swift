import SwiftUI

struct AnimatedProgressBar: View {
    let percent: Double
    let accent: Color
    let status: UsageStatus

    @State private var animatedPercent: Double = 0

    private var barColor: Color {
        switch status {
        case .limited: return .red
        case .nearLimit: return .orange
        case .authError, .unavailable: return .gray
        default:
            if percent >= 90 { return .red }
            if percent >= 70 { return .orange }
            return accent
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.16))
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.95), barColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * CGFloat(animatedPercent / 100), animatedPercent > 0 ? 6 : 0))
                    .shadow(color: barColor.opacity(0.65), radius: 5, x: 0, y: 0)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                animatedPercent = percent
            }
        }
        .onChange(of: percent) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                animatedPercent = newValue
            }
        }
    }
}

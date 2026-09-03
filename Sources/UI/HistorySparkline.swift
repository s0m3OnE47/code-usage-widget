import SwiftUI

/// 24h percent-used sparkline for a provider (host panel only).
struct HistorySparkline: View {
    let provider: ProviderID
    var hours: Double = 24

    var body: some View {
        let pts = HistoryStore.series(for: provider, hours: hours)
        if pts.count >= 2 {
            GeometryReader { geo in
                Path { path in
                    let w = geo.size.width, h = geo.size.height
                    let minX = pts.first!.0.timeIntervalSince1970
                    let maxX = max(pts.last!.0.timeIntervalSince1970, minX + 1)
                    for (i, pt) in pts.enumerated() {
                        let x = w * CGFloat((pt.0.timeIntervalSince1970 - minX) / (maxX - minX))
                        let y = h * (1 - CGFloat(min(max(pt.1, 0), 100) / 100))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(provider.accentColor.opacity(0.8), lineWidth: 1)
            }
            .frame(height: 22)
            .help("Last \(Int(hours))h usage")
        }
    }
}

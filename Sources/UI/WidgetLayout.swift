import CoreGraphics

enum WidgetLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 780
    /// Matches macOS desktop widget alignment (~20pt tiles).
    static let gridSpacing: CGFloat = 20
    static var size: CGSize { CGSize(width: width, height: height) }
}

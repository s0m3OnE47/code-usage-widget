import AppKit

enum WindowPositioning {
    static func visibleFrame(for window: NSWindow) -> NSRect {
        (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    }

    static func clamp(origin: NSPoint, size: NSSize, to visible: NSRect) -> NSPoint {
        NSPoint(
            x: max(visible.minX, min(origin.x, visible.maxX - size.width)),
            y: max(visible.minY, min(origin.y, visible.maxY - size.height))
        )
    }

    static func snapToGrid(origin: NSPoint, visible: NSRect, grid: CGFloat = WidgetLayout.gridSpacing) -> NSPoint {
        NSPoint(
            x: round((origin.x - visible.minX) / grid) * grid + visible.minX,
            y: round((origin.y - visible.minY) / grid) * grid + visible.minY
        )
    }

    static func clampedSnap(origin: NSPoint, size: NSSize, window: NSWindow) -> NSPoint {
        let visible = visibleFrame(for: window)
        let snapped = snapToGrid(origin: origin, visible: visible)
        return clamp(origin: snapped, size: size, to: visible)
    }

    static func isDragExcludedView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v is NSButton || v is NSScrollView || v is NSScroller { return true }
            let name = String(describing: type(of: v))
            if name.contains("ScrollView") || name.contains("Scroller") { return true }
            current = v.superview
        }
        return false
    }
}

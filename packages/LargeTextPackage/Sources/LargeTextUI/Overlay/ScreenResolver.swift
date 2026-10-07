import CoreGraphics

/// Picks the screen for the overlay / HUD. Pure.
package enum ScreenResolver {
    /// Order: the screen containing most of `targetFrame` → the screen under `mouseLocation` → the primary
    /// screen (`screens.first`, as in `NSScreen.screens`). Returns `nil` only when `screens` is empty.
    package static func resolve(
        targetFrame: CGRect?,
        mouseLocation: CGPoint,
        screens: [ScreenDescriptor]
    ) -> ScreenDescriptor? {
        if let targetFrame, let screen = screen(containingMostOf: targetFrame, in: screens) {
            return screen
        }
        if let screen = screens.first(where: { contains($0.frame, mouseLocation) }) {
            return screen
        }
        return screens.first
    }

    private static func screen(containingMostOf frame: CGRect, in screens: [ScreenDescriptor]) -> ScreenDescriptor? {
        let rect = frame.standardized
        guard !rect.isNull, !rect.isInfinite else { return nil }

        var best: (screen: ScreenDescriptor, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) {
                best = (screen, area)
            }
        }
        if let best { return best.screen }

        // Degenerate frames (zero width or height, e.g. a caret) have no area: use the centre point.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screens.first { contains($0.frame, center) }
    }

    /// Closed on all edges, so the very top / right pixel row (where the mouse can rest) still counts.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }
}

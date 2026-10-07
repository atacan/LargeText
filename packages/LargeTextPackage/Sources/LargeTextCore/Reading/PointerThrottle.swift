import CoreGraphics
import Foundation

/// Decides whether a pointer position while following is worth a new read (§4.4). Pure: the caller passes
/// the elapsed time.
package enum PointerThrottle {
    package static let minimumInterval: Duration = .milliseconds(60)
    /// Points, in AppKit global coordinates.
    package static let minimumDistance: CGFloat = 4

    /// At least `minimumInterval` since the last read started, **and** either moved more than
    /// `minimumDistance` from where it was read, or left the frame of the last displayed result (the
    /// element or the highlighted unit). Every point is in AppKit global coordinates.
    package static func shouldRead(
        at point: CGPoint,
        lastReadAt lastPoint: CGPoint,
        elapsed: Duration,
        lastFrame: CGRect?
    ) -> Bool {
        guard elapsed >= minimumInterval else { return false }
        let moved = hypot(point.x - lastPoint.x, point.y - lastPoint.y) > minimumDistance
        let leftFrame = lastFrame.map { !$0.contains(point) } ?? false
        return moved || leftFrame
    }
}

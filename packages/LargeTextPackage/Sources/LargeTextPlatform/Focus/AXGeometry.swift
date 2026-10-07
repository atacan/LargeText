import CoreGraphics
import LargeTextCore

/// Coordinate conversion between Accessibility and AppKit global coordinates.
///
/// AX and CG report top-left-origin global coordinates (y grows downwards) anchored at the top-left corner
/// of the **primary** screen (`NSScreen.screens.first`). AppKit uses bottom-left-origin global coordinates
/// (y grows upwards) anchored at the bottom-left corner of the same screen. One flip around the primary
/// screen converts between them for every display, including displays left of, above or below it with a
/// different height.
///
/// `primaryScreenFrame` must be the primary screen's AppKit frame (normally origin 0,0), not
/// `NSScreen.main`, which is merely the screen with the key window.
package enum AXGeometry {
    package static func appKitRect(axPosition: CGPoint, axSize: CGSize, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: primaryScreenFrame.minX + axPosition.x,
            y: primaryScreenFrame.maxY - axPosition.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )
    }

    /// A top-left-origin global rect (e.g. from `kAXBoundsForRangeParameterizedAttribute`) in AppKit coordinates.
    package static func appKitRect(globalRect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        appKitRect(axPosition: globalRect.origin, axSize: globalRect.size, primaryScreenFrame: primaryScreenFrame)
    }

    /// The inverse of `appKitRect(globalRect:primaryScreenFrame:)`.
    package static func globalRect(appKitRect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: appKitRect.minX - primaryScreenFrame.minX,
            y: primaryScreenFrame.maxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    package static func globalPoint(appKitPoint: CGPoint, primaryScreenFrame: CGRect) -> CGPoint {
        CGPoint(x: appKitPoint.x - primaryScreenFrame.minX, y: primaryScreenFrame.maxY - appKitPoint.y)
    }

    package static func appKitPoint(globalPoint: CGPoint, primaryScreenFrame: CGRect) -> CGPoint {
        CGPoint(x: primaryScreenFrame.minX + globalPoint.x, y: primaryScreenFrame.maxY - globalPoint.y)
    }

    /// One pointer sample: `global` is derived from `appKit`, so the two never disagree by a tick (§4.2).
    package static func pointerSample(appKit: CGPoint, primaryScreenFrame: CGRect) -> PointerSample {
        PointerSample(appKit: appKit, global: globalPoint(appKitPoint: appKit, primaryScreenFrame: primaryScreenFrame))
    }

    /// The primary screen's frame from CoreGraphics. The main display sits at the global origin and is the
    /// same screen as `NSScreen.screens.first`, so its bounds equal that screen's AppKit frame. Unlike
    /// `NSScreen`, it is safe to call from the reader's queue.
    package static func primaryScreenFrame() -> CGRect {
        CGDisplayBounds(CGMainDisplayID())
    }
}

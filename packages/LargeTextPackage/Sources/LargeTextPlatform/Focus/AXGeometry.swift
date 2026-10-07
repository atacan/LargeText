import CoreGraphics

/// Coordinate conversion between Accessibility and AppKit global coordinates.
package enum AXGeometry {
    /// AX reports top-left-origin global coordinates (y grows downwards) anchored at the top-left corner of
    /// the **primary** screen (`NSScreen.screens.first`). AppKit uses bottom-left-origin global coordinates
    /// (y grows upwards) anchored at the bottom-left corner of the same screen.
    ///
    /// `primaryScreenFrame` must be the primary screen's AppKit frame (normally origin 0,0), not
    /// `NSScreen.main`, which is merely the screen with the key window.
    package static func appKitRect(axPosition: CGPoint, axSize: CGSize, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: primaryScreenFrame.minX + axPosition.x,
            y: primaryScreenFrame.maxY - axPosition.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )
    }
}

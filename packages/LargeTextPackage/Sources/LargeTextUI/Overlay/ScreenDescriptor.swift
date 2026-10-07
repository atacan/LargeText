import CoreGraphics

/// A display, as plain values (AppKit global coordinates, origin at the primary screen's bottom-left).
package struct ScreenDescriptor: Equatable, Sendable {
    /// `CGDirectDisplayID` (`NSScreenNumber`).
    package var id: UInt32
    package var frame: CGRect
    package var visibleFrame: CGRect

    package init(id: UInt32, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

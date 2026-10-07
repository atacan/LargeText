import CoreGraphics
import Foundation

/// One pointer position in both coordinate systems, sampled once (§4.2).
///
/// Platform samples `appKit` and derives `global` from it with the primary-screen flip, so the two can never
/// disagree by a tick. AX and CG code only use `global`; UI code only uses `appKit`.
package struct PointerSample: Equatable, Sendable {
    /// AppKit global coordinates (bottom-left origin), e.g. `NSEvent.mouseLocation`.
    package var appKit: CGPoint
    /// Top-left-origin global coordinates anchored at the primary screen, as CG and AX expect.
    package var global: CGPoint

    package init(appKit: CGPoint, global: CGPoint) {
        self.appKit = appKit
        self.global = global
    }
}

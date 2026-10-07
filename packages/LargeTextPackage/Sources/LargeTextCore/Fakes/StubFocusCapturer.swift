import Foundation

/// Returns a fixed target. Used by scenarios and tests.
@MainActor
package final class StubFocusCapturer: FocusCapturing {
    package var target: FocusTarget
    package var keyboardFocusProcessIdentifier: Int32?

    /// `keyboardFocusProcessIdentifier` defaults to the target's pid, so the focus-return guard passes.
    package init(target: FocusTarget, keyboardFocusProcessIdentifier: Int32? = nil) {
        self.target = target
        self.keyboardFocusProcessIdentifier = keyboardFocusProcessIdentifier ?? target.application?.processIdentifier
    }

    package func captureFocus() -> FocusTarget { target }
}

import Foundation

/// Reports a settable key state for every combo.
@MainActor
package final class FixedKeyState: KeyStateReading {
    /// `nil` = unknown, the default: sessions rely on the hotkey release and the cap.
    package var isDown: Bool?

    package init(isDown: Bool? = nil) {
        self.isDown = isDown
    }

    package func isPhysicallyDown(_ combo: KeyCombo) -> Bool? { isDown }
}

import Foundation

/// Stuck-key protection while following (§3.1): asked on the pointer tick whether the shortcut is still held.
@MainActor
package protocol KeyStateReading: AnyObject {
    /// Whether `combo` is physically held right now; `nil` = unknown (rely on the hotkey release and the cap).
    func isPhysicallyDown(_ combo: KeyCombo) -> Bool?
}

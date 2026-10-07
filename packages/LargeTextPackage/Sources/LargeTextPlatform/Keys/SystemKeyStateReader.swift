import CoreGraphics
import LargeTextCore

/// The live stuck-key check while following (§3.1): is the reader shortcut still physically held?
@MainActor
package final class SystemKeyStateReader: KeyStateReading {
    package enum Mode: Sendable {
        /// `CGEventSource.keyState(.combinedSessionState, key:)` for the key, plus the modifier flags.
        case keyState
        /// Modifiers only, from `flagsState(.hidSystemState)`, for when `keyState` is gated behind Input
        /// Monitoring: any of the combo's modifiers being up means released.
        case modifierFallback
    }

    private let mode: Mode

    /// Spike R1 decides whether `keyState` returns real values without Input Monitoring; until then the
    /// default is `.keyState`.
    package init(mode: Mode = .keyState) {
        self.mode = mode
    }

    package func isPhysicallyDown(_ combo: KeyCombo) -> Bool? {
        switch mode {
        case .keyState:
            Self.isDown(
                keyDown: CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(combo.keyCode)),
                flags: CGEventSource.flagsState(.combinedSessionState),
                combo: combo
            )
        case .modifierFallback:
            Self.modifiersDown(flags: CGEventSource.flagsState(.hidSystemState), combo: combo)
        }
    }

    /// The key and every modifier of the combo are down. Extra modifiers don't count as a release.
    package nonisolated static func isDown(keyDown: Bool, flags: CGEventFlags, combo: KeyCombo) -> Bool {
        keyDown && flags.contains(modifierMask(for: combo))
    }

    /// Every modifier of the combo is down; `nil` (unknown) for a combo without modifiers, which the fallback
    /// can't observe.
    package nonisolated static func modifiersDown(flags: CGEventFlags, combo: KeyCombo) -> Bool? {
        guard !combo.modifiers.isEmpty else { return nil }
        return flags.contains(modifierMask(for: combo))
    }

    package nonisolated static func modifierMask(for combo: KeyCombo) -> CGEventFlags {
        combo.modifiers.cgEventFlags
    }
}

import Foundation

package enum HotkeyPhase: Equatable, Sendable {
    case pressed
    case released
}

/// One hotkey transition, as delivered by `HotkeyRegistering`.
package struct HotkeyEvent: Equatable, Sendable {
    package var phase: HotkeyPhase
    /// `GetEventTime(event)`: seconds of system uptime, taken from the Carbon event itself, so a busy main
    /// thread cannot skew it. Only differences between two stamps are meaningful.
    package var at: TimeInterval

    package init(phase: HotkeyPhase, at: TimeInterval) {
        self.phase = phase
        self.at = at
    }
}

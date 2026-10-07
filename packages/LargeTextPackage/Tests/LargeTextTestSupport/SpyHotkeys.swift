import Foundation
import LargeTextCore

/// Records registrations; can be scripted to fail with `HotkeyError.unavailable`.
@MainActor
package final class SpyHotkeys: HotkeyRegistering {
    package final class Registration: HotkeyRegistration {
        package let combo: KeyCombo
        package let handler: @MainActor (HotkeyEvent) -> Void
        package private(set) var isUnregistered = false

        init(combo: KeyCombo, handler: @escaping @MainActor (HotkeyEvent) -> Void) {
            self.combo = combo
            self.handler = handler
        }

        package func unregister() {
            isUnregistered = true
        }

        /// Delivers a press or release, as Carbon would, unless unregistered.
        package func simulate(_ phase: HotkeyPhase, at time: TimeInterval) {
            guard !isUnregistered else { return }
            handler(HotkeyEvent(phase: phase, at: time))
        }
    }

    package var failsRegistration: Bool
    package private(set) var registrations: [Registration] = []

    package init(failsRegistration: Bool = false) {
        self.failsRegistration = failsRegistration
    }

    package func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor (HotkeyEvent) -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        guard !failsRegistration else { throw .unavailable(combo) }
        let registration = Registration(combo: combo, handler: handler)
        registrations.append(registration)
        return registration
    }

    /// Delivers a press or release to the latest live registration (for `combo`, if given).
    package func simulate(_ phase: HotkeyPhase, at time: TimeInterval, for combo: KeyCombo? = nil) {
        registrations.last { !$0.isUnregistered && (combo == nil || $0.combo == combo) }?.simulate(phase, at: time)
    }
}

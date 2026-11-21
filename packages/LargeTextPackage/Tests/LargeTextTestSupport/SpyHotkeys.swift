import Foundation
import LargeTextCore

/// Records registrations; can be scripted to fail with `HotkeyError.unavailable`. Like Carbon, it also
/// refuses a combo that is still registered (`eventHotKeyExistsErr`), so ordering bugs in a rebind show up.
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

    /// Refuses every combo.
    package var failsRegistration: Bool
    /// Refuses these combos, as if another app held them.
    package var refusing: Set<KeyCombo>
    /// Successful registrations only, in order, including those since unregistered.
    package private(set) var registrations: [Registration] = []

    package init(failsRegistration: Bool = false, refusing: Set<KeyCombo> = []) {
        self.failsRegistration = failsRegistration
        self.refusing = refusing
    }

    /// The registrations not yet unregistered, in order.
    package var live: [Registration] {
        registrations.filter { !$0.isUnregistered }
    }

    package func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor (HotkeyEvent) -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        guard !failsRegistration, !refusing.contains(combo), !live.contains(where: { $0.combo == combo }) else {
            throw .unavailable(combo)
        }
        let registration = Registration(combo: combo, handler: handler)
        registrations.append(registration)
        return registration
    }

    /// Delivers a press or release to the latest live registration (for `combo`, if given).
    package func simulate(_ phase: HotkeyPhase, at time: TimeInterval, for combo: KeyCombo? = nil) {
        registrations.last { !$0.isUnregistered && (combo == nil || $0.combo == combo) }?.simulate(phase, at: time)
    }
}

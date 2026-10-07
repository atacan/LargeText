import Foundation
import LargeTextCore

/// Records registrations; can be scripted to fail with `HotkeyError.unavailable`.
@MainActor
package final class SpyHotkeys: HotkeyRegistering {
    package final class Registration: HotkeyRegistration {
        package let combo: KeyCombo
        package let handler: @MainActor () -> Void
        package private(set) var isUnregistered = false

        init(combo: KeyCombo, handler: @escaping @MainActor () -> Void) {
            self.combo = combo
            self.handler = handler
        }

        package func unregister() {
            isUnregistered = true
        }
    }

    package var failsRegistration: Bool
    package private(set) var registrations: [Registration] = []

    package init(failsRegistration: Bool = false) {
        self.failsRegistration = failsRegistration
    }

    package func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor () -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        guard !failsRegistration else { throw .unavailable(combo) }
        let registration = Registration(combo: combo, handler: handler)
        registrations.append(registration)
        return registration
    }
}

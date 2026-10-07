import Foundation

@MainActor
package protocol HotkeyRegistering: AnyObject {
    /// `handler` receives both the press and the release of `combo`, each stamped with the event's own time.
    func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor (HotkeyEvent) -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration
}

extension HotkeyRegistering {
    /// Press-only convenience for the editor. It has a distinct name, so overload resolution between two
    /// trailing-closure signatures can't silently pick the wrong one.
    package func registerPressOnly(
        _ combo: KeyCombo,
        _ onPress: @escaping @MainActor () -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        try register(combo) { event in
            guard event.phase == .pressed else { return }
            onPress()
        }
    }
}

@MainActor
package protocol HotkeyRegistration: AnyObject {
    func unregister()
}

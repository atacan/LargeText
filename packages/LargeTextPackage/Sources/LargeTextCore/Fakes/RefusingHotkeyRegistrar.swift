import Foundation
import os

/// Wraps any registrar and refuses a fixed set of combos with `HotkeyError.unavailable`, as if another app held
/// them; everything else goes to `wrapped`. The `settings-hotkey-taken` scenario puts it around the live
/// Carbon registrar, so a refused recording can be tried by hand (Settings plan §5).
@MainActor
package final class RefusingHotkeyRegistrar: HotkeyRegistering {
    package let wrapped: any HotkeyRegistering
    package let refusing: Set<KeyCombo>

    package init(wrapping wrapped: any HotkeyRegistering, refusing: Set<KeyCombo>) {
        self.wrapped = wrapped
        self.refusing = refusing
    }

    package func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor (HotkeyEvent) -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        if refusing.contains(combo) {
            Logger.core.info("RefusingHotkeyRegistrar: refused \(String(describing: combo), privacy: .public)")
            throw .unavailable(combo)
        }
        return try wrapped.register(combo, handler: handler)
    }
}

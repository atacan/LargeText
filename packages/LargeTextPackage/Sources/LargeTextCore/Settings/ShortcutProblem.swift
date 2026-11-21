import Foundation

/// Why a shortcut can't be used, shown next to its recorder (Settings plan §2.1).
package enum ShortcutProblem: Equatable, Sendable {
    /// No modifier, or ⇧ only. F1–F20 don't need one.
    case needsModifier
    /// ⌥ or ⌥⇧ only: macOS 15 refuses to register these (`IMPLEMENTATION_PLAN.md` §2.1).
    case optionOnlyRefused
    /// A combo the system or every app already uses, such as ⌘Space or ⌘Q.
    case reservedBySystem
    /// Equal to the other slot's combo, which is named here (`HotkeyConflicts`).
    case sameAsOther(ShortcutSlot)
    /// Passed the rules but couldn't be registered, probably because another app holds it. Set by
    /// `SettingsCoordinator`, never by `ShortcutRules`.
    case unavailable
}

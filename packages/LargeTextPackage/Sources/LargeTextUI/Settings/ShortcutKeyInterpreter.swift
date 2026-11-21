import LargeTextCore

/// What a key press means to a recording `ShortcutRecorderView` (Settings plan §4). Pure.
///
/// It only turns the press into a combo: whether that combo may be used (a modifier, ⌥ alone, reserved, the
/// other slot) is `ShortcutRules`' decision, made by `SettingsCoordinator`, so the window can say why.
/// The combo keeps the physical key code, which is what Carbon registers, whatever the layout prints on it.
package enum ShortcutKeyInterpreter {
    package enum Result: Equatable, Sendable {
        /// ⎋ with no modifiers: stop recording and keep the saved combo.
        case cancel
        /// A key with whatever modifiers were held, for `ShortcutRules` to check.
        case candidate(KeyCombo)
        /// A modifier key on its own (they normally arrive as `flagsChanged`, not `keyDown`).
        case ignore
    }

    /// ⌘, ⇧, ⇪, ⌥, ⌃ (left and right) and fn (`kVK_Command` … `kVK_Function`, `kVK_RightCommand`).
    package static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]

    package static func interpret(_ input: KeyInput) -> Result {
        if modifierKeyCodes.contains(input.keyCode) {
            return .ignore
        }
        if input.isEscape, input.modifiers.isEmpty {
            return .cancel
        }
        return .candidate(KeyCombo(keyCode: UInt32(input.keyCode), modifiers: input.modifiers))
    }
}

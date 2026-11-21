import Foundation

/// The checks a recorded combo must pass before Settings tries to register it (Settings plan §2.1). Pure;
/// conflicts with other apps can't be detected here, only by a failed registration (`.unavailable`).
package enum ShortcutRules {
    /// F1–F20 (`kVK_F1` … `kVK_F20`): usable without a modifier.
    package static let functionKeyCodes: Set<UInt32> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]

    /// Exact combos taken by the system or by every app. Not exhaustive: anything else that is taken shows up
    /// as `.unavailable`, or not at all (spike 0g).
    package static let reserved: Set<KeyCombo> = [
        KeyCombo(keyCode: 0x31, modifiers: .command),               // ⌘Space: Spotlight
        KeyCombo(keyCode: 0x31, modifiers: .control),               // ⌃Space: input sources
        KeyCombo(keyCode: 0x30, modifiers: .command),               // ⌘Tab: app switcher
        KeyCombo(keyCode: 0x32, modifiers: .command),               // ⌘`: window switcher
        KeyCombo(keyCode: 0x0C, modifiers: .command),               // ⌘Q
        KeyCombo(keyCode: 0x0D, modifiers: .command),               // ⌘W
        KeyCombo(keyCode: 0x2B, modifiers: .command),               // ⌘,: Settings in every app
        KeyCombo(keyCode: 0x04, modifiers: .command),               // ⌘H: hide
        KeyCombo(keyCode: 0x2E, modifiers: .command),               // ⌘M: minimize
        // The edit keys: taken globally they'd stop working in every app, and ⌘V would swallow the
        // editor's own synthesized paste.
        KeyCombo(keyCode: 0x06, modifiers: .command),               // ⌘Z
        KeyCombo(keyCode: 0x06, modifiers: [.command, .shift]),     // ⌘⇧Z
        KeyCombo(keyCode: 0x07, modifiers: .command),               // ⌘X
        KeyCombo(keyCode: 0x08, modifiers: .command),               // ⌘C
        KeyCombo(keyCode: 0x09, modifiers: .command),               // ⌘V
        KeyCombo(keyCode: 0x00, modifiers: .command),               // ⌘A
        KeyCombo(keyCode: 0x14, modifiers: [.command, .shift]),     // ⌘⇧3: screenshot
        KeyCombo(keyCode: 0x15, modifiers: [.command, .shift]),     // ⌘⇧4: screenshot
        KeyCombo(keyCode: 0x17, modifiers: [.command, .shift]),     // ⌘⇧5: screenshot
    ]

    /// The first rule `combo` breaks as the shortcut for `slot`, or `nil` when it may be registered.
    /// - Parameter other: the other slot's combo; `nil` when it is off, which skips `.sameAsOther`.
    package static func validate(_ combo: KeyCombo, for slot: ShortcutSlot, other: KeyCombo?) -> ShortcutProblem? {
        let modifiers = combo.modifiers
        if modifiers.subtracting(.shift).isEmpty, !functionKeyCodes.contains(combo.keyCode) {
            return .needsModifier
        }
        if modifiers == .option || modifiers == [.option, .shift] {
            return .optionOnlyRefused
        }
        if reserved.contains(combo) {
            return .reservedBySystem
        }
        if let other {
            // HotkeyConflicts stays the one definition of a conflict; the launch-time apply uses it too.
            let conflict = switch slot {
            case .editor: HotkeyConflicts.validate(editor: combo, reader: other)
            case .reader: HotkeyConflicts.validate(editor: other, reader: combo)
            }
            if case .failure = conflict {
                return .sameAsOther(slot.other)
            }
        }
        return nil
    }
}

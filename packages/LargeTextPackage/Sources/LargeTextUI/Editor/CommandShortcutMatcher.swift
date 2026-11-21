import LargeTextCore

/// ANSI virtual key codes (`kVK_*`), layout-independent physical positions.
package enum ANSIKeyCode {
    package static let returnKey: UInt16 = 0x24
    package static let keypadEnter: UInt16 = 0x4C
    package static let escape: UInt16 = 0x35
    package static let space: UInt16 = 0x31
    package static let equal: UInt16 = 0x18
    package static let minus: UInt16 = 0x1B
    package static let zero: UInt16 = 0x1D
    package static let keypadPlus: UInt16 = 0x45
    package static let keypadMinus: UInt16 = 0x4E
    package static let keypadZero: UInt16 = 0x52
    package static let a: UInt16 = 0x00
    package static let z: UInt16 = 0x06
    package static let x: UInt16 = 0x07
    package static let c: UInt16 = 0x08
    package static let v: UInt16 = 0x09
    package static let comma: UInt16 = 0x2B
}

/// A ⌘-shortcut shared by the editor and the reader, after the shift rules are applied.
package enum CommandShortcut: Equatable, Sendable {
    case zoom(ZoomStep)
    case edit(StandardEdit)
    /// ⌘, (Settings plan §3.5).
    case openSettings
}

/// Pure ⌘-shortcut matcher shared by `EditorKeyBindings` and `ReaderKeyBindings`, so both handle
/// keyboard layouts the same way. Requires ⌘; ⌃ or ⌥ disable every shortcut.
///
/// **Layout strategy.** ⌘-shortcuts are matched by *character* first (what the user's layout prints on
/// the key), then by *ANSI key code* — but the key-code fallback is used **only when the character is not
/// ASCII** (or missing). That gives:
/// - US / most Latin layouts: matched by character.
/// - German: ⌘+ (own key) and ⌘- match by character; the ANSI "=" and "-" positions print "´" and "ß",
///   which are non-ASCII, so they fall back to the key code and still zoom.
/// - Dvorak: ⌘Z/⌘X/⌘C/⌘V/⌘A follow the printed letters (as the system menus do). The QWERTY
///   positions print other ASCII characters there, so they do **not** fire by key code.
/// - Russian and other non-Latin layouts: the letter keys print non-ASCII characters, so the
///   QWERTY positions work by key code (⌘V on the "м" key pastes), as in the system menus.
///
/// Caps Lock and fn are ignored: `KeyInput.modifiers` cannot express them and characters are compared
/// case-insensitively.
package enum CommandShortcutMatcher {
    package static func match(_ input: KeyInput) -> CommandShortcut? {
        guard input.modifiers.contains(.command),
              input.modifiers.isDisjoint(with: [.control, .option])
        else { return nil }

        let character = input.charactersIgnoringModifiers?.lowercased()
        let match: CommandShortcut?
        if let character, let first = character.unicodeScalars.first, first.isASCII {
            match = shortcut(forCharacter: character)
        } else {
            match = shortcut(forKeyCode: input.keyCode)
        }
        guard let match else { return nil }
        return resolve(match, shift: input.modifiers.contains(.shift))
    }

    private static func shortcut(forCharacter character: String) -> CommandShortcut? {
        switch character {
        case "=", "+": .zoom(.bigger)
        case "-": .zoom(.smaller)
        case "0": .zoom(.reset)
        case "z": .edit(.undo)
        case "x": .edit(.cut)
        case "c": .edit(.copy)
        case "v": .edit(.paste)
        case "a": .edit(.selectAll)
        case ",": .openSettings
        default: nil
        }
    }

    private static func shortcut(forKeyCode keyCode: UInt16) -> CommandShortcut? {
        switch keyCode {
        case ANSIKeyCode.equal, ANSIKeyCode.keypadPlus: .zoom(.bigger)
        case ANSIKeyCode.minus, ANSIKeyCode.keypadMinus: .zoom(.smaller)
        case ANSIKeyCode.zero, ANSIKeyCode.keypadZero: .zoom(.reset)
        case ANSIKeyCode.z: .edit(.undo)
        case ANSIKeyCode.x: .edit(.cut)
        case ANSIKeyCode.c: .edit(.copy)
        case ANSIKeyCode.v: .edit(.paste)
        case ANSIKeyCode.a: .edit(.selectAll)
        case ANSIKeyCode.comma: .openSettings
        default: nil
        }
    }

    /// Applies the shift rules: ⇧ is allowed for ⌘+ / ⌘- (⌘⇧= types "+"), turns ⌘Z into redo,
    /// and disables every other shortcut (⌘⇧0 on German types "=", handled by character).
    private static func resolve(_ shortcut: CommandShortcut, shift: Bool) -> CommandShortcut? {
        switch shortcut {
        case .zoom(.reset): shift ? nil : .zoom(.reset)
        case .zoom: shortcut
        case .edit(.undo): .edit(shift ? .redo : .undo)
        case .edit, .openSettings: shift ? nil : shortcut
        }
    }
}

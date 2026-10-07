import LargeTextCore

/// Pure key → action table for the overlay editor (§2.3). `nil` means "normal typing, let AppKit handle it".
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
package enum EditorKeyBindings {
    /// ANSI virtual key codes (`kVK_*`), layout-independent physical positions.
    package enum KeyCode {
        package static let returnKey: UInt16 = 0x24
        package static let keypadEnter: UInt16 = 0x4C
        package static let escape: UInt16 = 0x35
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
    }

    package static func action(for input: KeyInput) -> EditorAction? {
        if isReturn(input) { return returnAction(input.modifiers) }
        if isEscape(input) { return input.modifiers.isEmpty ? .cancel : nil }
        guard input.modifiers.contains(.command),
              input.modifiers.isDisjoint(with: [.control, .option])
        else { return nil }
        return commandAction(input)
    }

    // MARK: - Return / Escape

    private static func isReturn(_ input: KeyInput) -> Bool {
        if input.keyCode == KeyCode.returnKey || input.keyCode == KeyCode.keypadEnter { return true }
        return input.charactersIgnoringModifiers == "\r" || input.charactersIgnoringModifiers == "\u{3}"
    }

    private static func isEscape(_ input: KeyInput) -> Bool {
        input.keyCode == KeyCode.escape || input.charactersIgnoringModifiers == "\u{1B}"
    }

    private static func returnAction(_ modifiers: Modifiers) -> EditorAction? {
        if modifiers.isEmpty { return .commit(.insert) }
        if modifiers == .command { return .commit(.insertAndSubmit) }
        // ⇧↩, ⌥↩, ⇧⌥↩ — but never with ⌘ or ⌃.
        if modifiers.isDisjoint(with: [.command, .control]) { return .newline }
        return nil
    }

    // MARK: - ⌘ shortcuts

    private enum Shortcut {
        case zoom(ZoomStep)
        case edit(StandardEdit)
    }

    private static func commandAction(_ input: KeyInput) -> EditorAction? {
        let character = input.charactersIgnoringModifiers?.lowercased()
        let match: Shortcut?
        if let character, let first = character.unicodeScalars.first, first.isASCII {
            match = shortcut(forCharacter: character)
        } else {
            match = shortcut(forKeyCode: input.keyCode)
        }
        guard let match else { return nil }
        return resolve(match, shift: input.modifiers.contains(.shift))
    }

    private static func shortcut(forCharacter character: String) -> Shortcut? {
        switch character {
        case "=", "+": .zoom(.bigger)
        case "-": .zoom(.smaller)
        case "0": .zoom(.reset)
        case "z": .edit(.undo)
        case "x": .edit(.cut)
        case "c": .edit(.copy)
        case "v": .edit(.paste)
        case "a": .edit(.selectAll)
        default: nil
        }
    }

    private static func shortcut(forKeyCode keyCode: UInt16) -> Shortcut? {
        switch keyCode {
        case KeyCode.equal, KeyCode.keypadPlus: .zoom(.bigger)
        case KeyCode.minus, KeyCode.keypadMinus: .zoom(.smaller)
        case KeyCode.zero, KeyCode.keypadZero: .zoom(.reset)
        case KeyCode.z: .edit(.undo)
        case KeyCode.x: .edit(.cut)
        case KeyCode.c: .edit(.copy)
        case KeyCode.v: .edit(.paste)
        case KeyCode.a: .edit(.selectAll)
        default: nil
        }
    }

    /// Applies the shift rules: ⇧ is allowed for ⌘+ / ⌘- (⌘⇧= types "+"), turns ⌘Z into redo,
    /// and disables every other shortcut (⌘⇧0 on German types "=", handled by character).
    private static func resolve(_ shortcut: Shortcut, shift: Bool) -> EditorAction? {
        switch shortcut {
        case .zoom(.reset): shift ? nil : .zoom(.reset)
        case .zoom(let step): .zoom(step)
        case .edit(.undo): .standardEdit(shift ? .redo : .undo)
        case .edit(let edit): shift ? nil : .standardEdit(edit)
        }
    }
}

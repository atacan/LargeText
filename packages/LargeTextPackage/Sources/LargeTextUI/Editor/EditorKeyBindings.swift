import LargeTextCore

/// Pure key → action table for the overlay editor (§2.3). `nil` means "normal typing, let AppKit handle it".
///
/// ⌘-shortcuts go through `CommandShortcutMatcher`, which documents the keyboard-layout strategy.
package enum EditorKeyBindings {
    package typealias KeyCode = ANSIKeyCode

    package static func action(for input: KeyInput) -> EditorAction? {
        if isReturn(input) { return returnAction(input.modifiers) }
        if input.isEscape { return input.modifiers.isEmpty ? .cancel : nil }
        switch CommandShortcutMatcher.match(input) {
        case .zoom(let step): return .zoom(step)
        case .edit(let edit): return .standardEdit(edit)
        case .openSettings: return .openSettings
        case nil: return nil
        }
    }

    // MARK: - Return / Escape

    private static func isReturn(_ input: KeyInput) -> Bool {
        if input.keyCode == KeyCode.returnKey || input.keyCode == KeyCode.keypadEnter { return true }
        return input.charactersIgnoringModifiers == "\r" || input.charactersIgnoringModifiers == "\u{3}"
    }

    private static func returnAction(_ modifiers: Modifiers) -> EditorAction? {
        if modifiers.isEmpty { return .commit(.insert) }
        if modifiers == .command { return .commit(.insertAndSubmit) }
        // ⇧↩, ⌥↩, ⇧⌥↩ — but never with ⌘ or ⌃.
        if modifiers.isDisjoint(with: [.command, .control]) { return .newline }
        return nil
    }
}

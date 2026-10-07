import LargeTextCore

/// A key press, reduced to what `EditorKeyBindings` and `ReaderKeyBindings` need. Built from an `NSEvent`
/// in the view, constructed directly in tests.
package struct KeyInput: Equatable, Sendable {
    /// Carbon / `NSEvent.keyCode` virtual key code (ANSI positions, layout-independent).
    package var keyCode: UInt16
    /// `NSEvent.charactersIgnoringModifiers` (layout-dependent).
    package var charactersIgnoringModifiers: String?
    /// Caps Lock, fn and the numeric-pad flag are deliberately not represented.
    package var modifiers: Modifiers

    package init(keyCode: UInt16, charactersIgnoringModifiers: String?, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
    }
}

extension KeyInput {
    /// ⎋, by key code or character, with any modifiers.
    package var isEscape: Bool {
        keyCode == ANSIKeyCode.escape || charactersIgnoringModifiers == "\u{1B}"
    }
}

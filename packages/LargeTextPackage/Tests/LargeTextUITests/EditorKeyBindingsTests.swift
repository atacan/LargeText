import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("EditorKeyBindings")
struct EditorKeyBindingsTests {
    private typealias K = EditorKeyBindings.KeyCode

    private func action(_ keyCode: UInt16, _ characters: String?, _ modifiers: Modifiers = []) -> EditorAction? {
        EditorKeyBindings.action(for: KeyInput(keyCode: keyCode, charactersIgnoringModifiers: characters, modifiers: modifiers))
    }

    // MARK: Return

    @Test func returnCommitsInsert() {
        #expect(action(K.returnKey, "\r") == .commit(.insert))
    }

    @Test func keypadEnterCommitsInsert() {
        #expect(action(K.keypadEnter, "\u{3}") == .commit(.insert))
    }

    @Test func commandReturnCommitsAndSubmits() {
        #expect(action(K.returnKey, "\r", .command) == .commit(.insertAndSubmit))
        #expect(action(K.keypadEnter, "\u{3}", .command) == .commit(.insertAndSubmit))
    }

    @Test(arguments: [Modifiers.shift, .option, [.shift, .option]])
    func shiftOrOptionReturnInsertsNewline(_ modifiers: Modifiers) {
        #expect(action(K.returnKey, "\r", modifiers) == .newline)
    }

    @Test(arguments: [Modifiers.control, [.command, .shift], [.command, .option], [.control, .shift]])
    func otherReturnCombosFallThrough(_ modifiers: Modifiers) {
        #expect(action(K.returnKey, "\r", modifiers) == nil)
    }

    // MARK: Escape

    @Test func escapeCancels() {
        #expect(action(K.escape, "\u{1B}") == .cancel)
    }

    @Test func modifiedEscapeFallsThrough() {
        #expect(action(K.escape, "\u{1B}", .command) == nil)
    }

    // MARK: Zoom — US layout

    @Test func usCommandEqualZoomsIn() {
        #expect(action(K.equal, "=", .command) == .zoom(.bigger))
    }

    @Test func usCommandShiftEqualZoomsIn() {
        // AppKit may report either the shifted or the unshifted character.
        #expect(action(K.equal, "+", [.command, .shift]) == .zoom(.bigger))
        #expect(action(K.equal, "=", [.command, .shift]) == .zoom(.bigger))
    }

    @Test func usCommandMinusZoomsOut() {
        #expect(action(K.minus, "-", .command) == .zoom(.smaller))
    }

    @Test func commandZeroResets() {
        #expect(action(K.zero, "0", .command) == .zoom(.reset))
    }

    @Test func keypadZoomKeys() {
        #expect(action(K.keypadPlus, "+", .command) == .zoom(.bigger))
        #expect(action(K.keypadMinus, "-", .command) == .zoom(.smaller))
        #expect(action(K.keypadZero, "0", .command) == .zoom(.reset))
    }

    @Test func zoomNeedsCommand() {
        #expect(action(K.equal, "=") == nil)
        #expect(action(K.minus, "-") == nil)
        #expect(action(K.zero, "0") == nil)
    }

    @Test func zoomWithControlOrOptionFallsThrough() {
        #expect(action(K.equal, "=", [.command, .option]) == nil)
        #expect(action(K.minus, "-", [.command, .control]) == nil)
    }

    // MARK: Zoom — German layout (QWERTZ)

    /// German: "+" has its own key at the ANSI "]" position.
    @Test func germanCommandPlusZoomsIn() {
        #expect(action(0x1E, "+", .command) == .zoom(.bigger))
    }

    /// German: "-" sits at the ANSI "/" position.
    @Test func germanCommandMinusZoomsOut() {
        #expect(action(0x2C, "-", .command) == .zoom(.smaller))
    }

    /// German: the ANSI "-" and "=" positions print "ß" and "´" (non-ASCII) → matched by key code.
    @Test func germanAnsiPositionsFallBackToKeyCode() {
        #expect(action(K.minus, "ß", .command) == .zoom(.smaller))
        #expect(action(K.equal, "´", .command) == .zoom(.bigger))
    }

    /// German: "=" is ⇧0. Matched by character, so it zooms in rather than resetting.
    @Test func germanCommandShiftZeroTypesEqualAndZoomsIn() {
        #expect(action(K.zero, "=", [.command, .shift]) == .zoom(.bigger))
        #expect(action(K.zero, "0", [.command, .shift]) == nil)
    }

    // MARK: Standard edits

    @Test func standardEdits() {
        #expect(action(K.z, "z", .command) == .standardEdit(.undo))
        #expect(action(K.z, "z", [.command, .shift]) == .standardEdit(.redo))
        #expect(action(K.z, "Z", [.command, .shift]) == .standardEdit(.redo))
        #expect(action(K.x, "x", .command) == .standardEdit(.cut))
        #expect(action(K.c, "c", .command) == .standardEdit(.copy))
        #expect(action(K.v, "v", .command) == .standardEdit(.paste))
        #expect(action(K.a, "a", .command) == .standardEdit(.selectAll))
    }

    @Test func capsLockUppercaseIsIgnored() {
        #expect(action(K.v, "V", .command) == .standardEdit(.paste))
        #expect(action(K.a, "A", .command) == .standardEdit(.selectAll))
    }

    @Test func shiftedEditsOtherThanRedoFallThrough() {
        #expect(action(K.v, "v", [.command, .shift]) == nil)
        #expect(action(K.a, "a", [.command, .shift]) == nil)
    }

    @Test func optionCommandPasteFallsThrough() {
        #expect(action(K.v, "v", [.command, .option]) == nil)
    }

    /// Dvorak: the printed letter wins; the QWERTY position printing another ASCII char does not fire.
    @Test func dvorakMatchesByCharacter() {
        #expect(action(0x2F, "v", .command) == .standardEdit(.paste))   // Dvorak "v" is on ANSI "."
        #expect(action(K.v, ".", .command) == nil)                      // ANSI "v" prints "."
    }

    /// Russian: letter keys print Cyrillic → matched by the QWERTY key code.
    @Test func russianFallsBackToKeyCode() {
        #expect(action(K.v, "м", .command) == .standardEdit(.paste))
        #expect(action(K.c, "с", .command) == .standardEdit(.copy))
        #expect(action(K.z, "я", .command) == .standardEdit(.undo))
        #expect(action(K.z, "Я", [.command, .shift]) == .standardEdit(.redo))
    }

    @Test func missingCharactersFallBackToKeyCode() {
        #expect(action(K.a, nil, .command) == .standardEdit(.selectAll))
        #expect(action(K.equal, "", .command) == .zoom(.bigger))
    }

    // MARK: Normal typing

    @Test(arguments: ["a", "Z", "1", "=", "-", " ", "ß"])
    func plainCharactersFallThrough(_ character: String) {
        #expect(action(0x00, character) == nil)
        #expect(action(0x00, character, .shift) == nil)
    }

    @Test func unboundCommandShortcutsFallThrough() {
        #expect(action(0x01, "s", .command) == nil)
        #expect(action(0x0C, "q", .command) == nil)
        #expect(action(0x2F, ".", .command) == nil)
    }
}

import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("CommandShortcutMatcher")
struct CommandShortcutMatcherTests {
    private typealias K = ANSIKeyCode

    private func match(_ keyCode: UInt16, _ characters: String?, _ modifiers: Modifiers = .command) -> CommandShortcut? {
        CommandShortcutMatcher.match(KeyInput(keyCode: keyCode, charactersIgnoringModifiers: characters, modifiers: modifiers))
    }

    // MARK: Modifiers

    @Test func requiresCommand() {
        #expect(match(K.c, "c", []) == nil)
        #expect(match(K.c, "c", .shift) == nil)
        #expect(match(K.equal, "=", []) == nil)
    }

    @Test(arguments: [Modifiers([.command, .control]), [.command, .option], [.command, .control, .option]])
    func controlOrOptionDisablesEveryShortcut(_ modifiers: Modifiers) {
        #expect(match(K.c, "c", modifiers) == nil)
        #expect(match(K.a, "a", modifiers) == nil)
        #expect(match(K.equal, "=", modifiers) == nil)
    }

    // MARK: US layout

    @Test func usShortcuts() {
        #expect(match(K.equal, "=") == .zoom(.bigger))
        #expect(match(K.minus, "-") == .zoom(.smaller))
        #expect(match(K.zero, "0") == .zoom(.reset))
        #expect(match(K.z, "z") == .edit(.undo))
        #expect(match(K.x, "x") == .edit(.cut))
        #expect(match(K.c, "c") == .edit(.copy))
        #expect(match(K.v, "v") == .edit(.paste))
        #expect(match(K.a, "a") == .edit(.selectAll))
    }

    // MARK: Shift rules

    @Test func shiftKeepsZoomInAndOut() {
        #expect(match(K.equal, "+", [.command, .shift]) == .zoom(.bigger))
        #expect(match(K.minus, "-", [.command, .shift]) == .zoom(.smaller))
    }

    @Test func shiftTurnsUndoIntoRedo() {
        #expect(match(K.z, "z", [.command, .shift]) == .edit(.redo))
    }

    @Test func shiftDisablesResetAndOtherEdits() {
        #expect(match(K.zero, "0", [.command, .shift]) == nil)
        #expect(match(K.c, "c", [.command, .shift]) == nil)
        #expect(match(K.a, "a", [.command, .shift]) == nil)
    }

    // MARK: Character vs. key code

    @Test func capsLockUppercaseIsIgnored() {
        #expect(match(K.c, "C") == .edit(.copy))
        #expect(match(K.a, "A") == .edit(.selectAll))
    }

    /// German QWERTZ: "+" has its own key; the ANSI "=" position prints the non-ASCII "´".
    @Test func germanZoom() {
        #expect(match(0x1E, "+") == .zoom(.bigger))
        #expect(match(K.equal, "´") == .zoom(.bigger))
        #expect(match(K.minus, "ß") == .zoom(.smaller))
    }

    /// German: copy and select-all print the same letters as US.
    @Test func germanCopyAndSelectAll() {
        #expect(match(K.c, "c") == .edit(.copy))
        #expect(match(K.a, "a") == .edit(.selectAll))
    }

    /// French AZERTY: "a" sits on the ANSI "q" key and prints an ASCII letter, so it matches by character;
    /// the ANSI "a" position prints "q" and does not fire.
    @Test func frenchSelectAllFollowsThePrintedLetter() {
        #expect(match(0x0C, "a") == .edit(.selectAll))
        #expect(match(K.a, "q") == nil)
        #expect(match(K.c, "c") == .edit(.copy))
    }

    /// Dvorak: "c" is on the ANSI "i" key; the ANSI "c" position prints "j".
    @Test func dvorakFollowsThePrintedLetter() {
        #expect(match(0x22, "c") == .edit(.copy))
        #expect(match(K.c, "j") == nil)
        #expect(match(K.a, "a") == .edit(.selectAll))
    }

    /// Russian and Greek print non-ASCII letters: the QWERTY positions work by key code.
    @Test func nonLatinLayoutsFallBackToKeyCode() {
        #expect(match(K.c, "с") == .edit(.copy))
        #expect(match(K.a, "ф") == .edit(.selectAll))
        #expect(match(K.c, "ψ") == .edit(.copy))
        #expect(match(K.a, "α") == .edit(.selectAll))
        #expect(match(K.z, "Я", [.command, .shift]) == .edit(.redo))
    }

    @Test func missingCharactersFallBackToKeyCode() {
        #expect(match(K.c, nil) == .edit(.copy))
        #expect(match(K.keypadZero, "") == .zoom(.reset))
    }

    @Test func keypadZoomKeys() {
        #expect(match(K.keypadPlus, "+") == .zoom(.bigger))
        #expect(match(K.keypadMinus, "-") == .zoom(.smaller))
        #expect(match(K.keypadZero, "0") == .zoom(.reset))
    }

    @Test func unboundShortcutsFallThrough() {
        #expect(match(0x01, "s") == nil)
        #expect(match(0x0C, "q") == nil)
        #expect(match(0x2F, ".") == nil)
    }
}

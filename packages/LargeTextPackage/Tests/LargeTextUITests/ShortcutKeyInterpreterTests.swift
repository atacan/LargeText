import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("ShortcutKeyInterpreter")
struct ShortcutKeyInterpreterTests {
    private let hyper: Modifiers = [.control, .option, .command]

    private func interpret(_ keyCode: UInt16, _ characters: String?, _ modifiers: Modifiers) -> ShortcutKeyInterpreter.Result {
        ShortcutKeyInterpreter.interpret(KeyInput(keyCode: keyCode, charactersIgnoringModifiers: characters, modifiers: modifiers))
    }

    private func candidate(_ keyCode: UInt32, _ modifiers: Modifiers) -> ShortcutKeyInterpreter.Result {
        .candidate(KeyCombo(keyCode: keyCode, modifiers: modifiers))
    }

    @Test func theDefaultsAreCandidates() {
        #expect(interpret(0x11, "t", hyper) == .candidate(.default))
        #expect(interpret(0x0F, "r", hyper) == .candidate(.readerDefault))
    }

    @Test func commandCombosAreCandidates() {
        #expect(interpret(0x0E, "e", [.command, .shift]) == candidate(0x0E, [.command, .shift]))
        #expect(interpret(0x2B, ",", .command) == candidate(0x2B, .command))
        // Reserved combos are still candidates: ShortcutRules refuses them, so the window can say why.
        #expect(interpret(0x0C, "q", .command) == candidate(0x0C, .command))
        #expect(interpret(0x31, " ", .command) == candidate(0x31, .command))
    }

    @Test func escapeWithoutModifiersCancels() {
        #expect(interpret(ANSIKeyCode.escape, "\u{1B}", []) == .cancel)
    }

    @Test func escapeWithModifiersIsACandidate() {
        #expect(interpret(ANSIKeyCode.escape, "\u{1B}", .control) == candidate(0x35, .control))
        #expect(interpret(ANSIKeyCode.escape, "\u{1B}", .shift) == candidate(0x35, .shift))
    }

    @Test(arguments: [UInt16(0x36), 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F])
    func modifierKeysAreIgnored(_ keyCode: UInt16) {
        #expect(interpret(keyCode, "", [.control, .option]) == .ignore)
        #expect(interpret(keyCode, nil, []) == .ignore)
    }

    @Test func functionKeysAreCandidatesWithOrWithoutModifiers() {
        #expect(interpret(0x60, "\u{F708}", []) == candidate(0x60, []))      // F5
        #expect(interpret(0x5A, "\u{F717}", []) == candidate(0x5A, []))      // F20
        #expect(interpret(0x7A, "\u{F704}", .control) == candidate(0x7A, .control))  // ⌃F1
    }

    /// Bare and ⇧-only keys are candidates too; `.needsModifier` comes from ShortcutRules.
    @Test func keysWithoutAModifierAreLeftToTheRules() {
        #expect(interpret(0x00, "a", []) == candidate(0x00, []))
        #expect(interpret(0x00, "A", .shift) == candidate(0x00, .shift))
        #expect(interpret(ANSIKeyCode.returnKey, "\r", []) == candidate(0x24, []))
    }

    /// German (QWERTZ): Z and Y swap places, "ß" sits on the ANSI "-" key and "´" on "=". The combo keeps the
    /// physical key code, which is what Carbon registers, whatever the key prints.
    @Test func germanLayoutKeepsThePhysicalKeyCode() {
        #expect(interpret(0x10, "z", hyper) == candidate(0x10, hyper))      // ANSI Y position prints "z"
        #expect(interpret(0x06, "y", hyper) == candidate(0x06, hyper))      // ANSI Z position prints "y"
        #expect(interpret(0x1B, "ß", [.control, .command]) == candidate(0x1B, [.control, .command]))
        #expect(interpret(0x18, "´", .command) == candidate(0x18, .command))
        #expect(interpret(0x29, "ö", [.option, .command]) == candidate(0x29, [.option, .command]))
    }

    /// ⌥ changes the character a key types ("†" for ⌥T on US); only the key code counts.
    @Test func charactersDoNotChangeTheCombo() {
        #expect(interpret(0x11, "†", hyper) == candidate(0x11, hyper))
        #expect(interpret(0x11, nil, hyper) == candidate(0x11, hyper))
    }
}

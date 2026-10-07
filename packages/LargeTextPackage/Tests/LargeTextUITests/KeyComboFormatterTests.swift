import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("KeyComboFormatter")
struct KeyComboFormatterTests {
    @Test func defaultHotkey() {
        #expect(KeyComboFormatter.string(for: .default) == "⌃⌥⌘T")
    }

    @Test func modifiersInStandardOrder() {
        let combo = KeyCombo(keyCode: 0x00, modifiers: [.command, .shift, .option, .control])
        #expect(KeyComboFormatter.string(for: combo) == "⌃⌥⇧⌘A")
    }

    @Test func digitsAndPunctuation() {
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x12, modifiers: .command)) == "⌘1")
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x1D, modifiers: .command)) == "⌘0")
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x18, modifiers: .command)) == "⌘=")
    }

    @Test func specialKeys() {
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x31, modifiers: [.control, .option])) == "⌃⌥Space")
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x24, modifiers: .command)) == "⌘↩")
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x35, modifiers: [])) == "⎋")
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0x7A, modifiers: .shift)) == "⇧F1")
    }

    @Test func unknownKeyCodeFallsBack() {
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: 0xFF, modifiers: .command)) == "⌘Key 255")
    }
}

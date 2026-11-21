import Testing
import LargeTextCore

/// Settings plan §2.1: one test per rule.
struct ShortcutRulesTests {
    static let keyT: UInt32 = 0x11
    static let keyF5: UInt32 = 0x60

    func combo(_ keyCode: UInt32, _ modifiers: Modifiers) -> KeyCombo {
        KeyCombo(keyCode: keyCode, modifiers: modifiers)
    }

    @Test func theDefaultsPass() {
        #expect(ShortcutRules.validate(.default, for: .editor, other: .readerDefault) == nil)
        #expect(ShortcutRules.validate(.readerDefault, for: .reader, other: .default) == nil)
    }

    @Test func aBareKeyOrShiftOnlyNeedsAModifier() {
        #expect(ShortcutRules.validate(combo(Self.keyT, []), for: .editor, other: nil) == .needsModifier)
        #expect(ShortcutRules.validate(combo(Self.keyT, .shift), for: .reader, other: nil) == .needsModifier)
    }

    @Test func functionKeysNeedNoModifier() {
        #expect(ShortcutRules.validate(combo(Self.keyF5, []), for: .editor, other: nil) == nil)
        #expect(ShortcutRules.validate(combo(Self.keyF5, .shift), for: .editor, other: nil) == nil)
        #expect(ShortcutRules.validate(combo(0x5A, []), for: .reader, other: nil) == nil)    // F20
    }

    @Test func optionOnlyAndOptionShiftOnlyAreRefused() {
        #expect(ShortcutRules.validate(combo(Self.keyT, .option), for: .editor, other: nil) == .optionOnlyRefused)
        #expect(ShortcutRules.validate(combo(Self.keyT, [.option, .shift]), for: .editor, other: nil) == .optionOnlyRefused)
        #expect(ShortcutRules.validate(combo(Self.keyF5, .option), for: .editor, other: nil) == .optionOnlyRefused)
    }

    @Test func optionWithAnotherModifierPasses() {
        #expect(ShortcutRules.validate(combo(Self.keyT, [.option, .control]), for: .editor, other: nil) == nil)
        #expect(ShortcutRules.validate(combo(Self.keyT, [.option, .command]), for: .editor, other: nil) == nil)
    }

    @Test(arguments: [
        KeyCombo(keyCode: 0x31, modifiers: .command),
        KeyCombo(keyCode: 0x31, modifiers: .control),
        KeyCombo(keyCode: 0x30, modifiers: .command),
        KeyCombo(keyCode: 0x32, modifiers: .command),
        KeyCombo(keyCode: 0x0C, modifiers: .command),
        KeyCombo(keyCode: 0x0D, modifiers: .command),
        KeyCombo(keyCode: 0x2B, modifiers: .command),
        KeyCombo(keyCode: 0x14, modifiers: [.command, .shift]),
        KeyCombo(keyCode: 0x15, modifiers: [.command, .shift]),
        KeyCombo(keyCode: 0x17, modifiers: [.command, .shift]),
        KeyCombo(keyCode: 0x04, modifiers: .command),
        KeyCombo(keyCode: 0x2E, modifiers: .command),
        KeyCombo(keyCode: 0x06, modifiers: .command),
        KeyCombo(keyCode: 0x06, modifiers: [.command, .shift]),
        KeyCombo(keyCode: 0x07, modifiers: .command),
        KeyCombo(keyCode: 0x08, modifiers: .command),
        KeyCombo(keyCode: 0x09, modifiers: .command),
        KeyCombo(keyCode: 0x00, modifiers: .command),
    ])
    func reservedCombosAreRefused(_ reserved: KeyCombo) {
        #expect(ShortcutRules.validate(reserved, for: .editor, other: nil) == .reservedBySystem)
    }

    @Test func reservedKeysWithOtherModifiersPass() {
        #expect(ShortcutRules.validate(combo(0x31, [.command, .control]), for: .editor, other: nil) == nil)    // ⌃⌘Space
        #expect(ShortcutRules.validate(combo(0x0C, [.command, .option]), for: .editor, other: nil) == nil)     // ⌥⌘Q
    }

    @Test func theOtherSlotsComboIsNamed() {
        #expect(ShortcutRules.validate(.readerDefault, for: .editor, other: .readerDefault) == .sameAsOther(.reader))
        #expect(ShortcutRules.validate(.default, for: .reader, other: .default) == .sameAsOther(.editor))
    }

    @Test func otherSlotOffSkipsTheConflictCheck() {
        #expect(ShortcutRules.validate(.readerDefault, for: .editor, other: nil) == nil)
    }

    @Test func theFirstBrokenRuleWins() {
        // ⌘Q equal to the other slot: reserved is reported, not the conflict.
        let quit = combo(0x0C, .command)
        #expect(ShortcutRules.validate(quit, for: .reader, other: quit) == .reservedBySystem)
    }

    @Test func slotHelpers() {
        #expect(ShortcutSlot.editor.other == .reader)
        #expect(ShortcutSlot.reader.other == .editor)
        #expect(ShortcutSlot.editor.defaultCombo == .default)
        #expect(ShortcutSlot.reader.defaultCombo == .readerDefault)
    }
}

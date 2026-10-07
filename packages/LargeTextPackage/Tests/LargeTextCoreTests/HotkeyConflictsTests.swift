import Testing
import LargeTextCore

struct HotkeyConflictsTests {
    @Test func defaultsDontConflict() {
        #expect(HotkeyConflicts.validate(editor: .default, reader: .readerDefault) == .success(.readerDefault))
    }

    @Test func readerEqualToTheEditorIsUnavailable() {
        #expect(HotkeyConflicts.validate(editor: .default, reader: .default) == .failure(.unavailable(.default)))
    }

    @Test func sameKeyWithOtherModifiersIsFine() {
        let reader = KeyCombo(keyCode: KeyCombo.default.keyCode, modifiers: [.control, .option])

        #expect(HotkeyConflicts.validate(editor: .default, reader: reader) == .success(reader))
    }
}

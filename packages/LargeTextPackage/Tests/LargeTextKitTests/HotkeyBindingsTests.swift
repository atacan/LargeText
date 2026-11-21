import Foundation
import LargeTextCore
import LargeTextTestSupport
import Testing
@testable import LargeTextKit

/// Registering both shortcuts as one unit (Settings plan §3.8). `SpyHotkeys` refuses a combo that is still
/// registered, as Carbon does, so a rebind that registers before unregistering fails here.
@MainActor
@Suite struct HotkeyBindingsTests {
    let hotkeys = SpyHotkeys()
    let other = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])    // ⌃⌥⌘E

    final class Calls {
        var editorPresses = 0
        var readerEvents: [HotkeyEvent] = []
        var changes = 0
    }

    func makeBindings(_ calls: Calls = Calls()) -> HotkeyBindings {
        let bindings = HotkeyBindings(
            hotkeys: hotkeys,
            onEditor: { calls.editorPresses += 1 },
            onReader: { calls.readerEvents.append($0) }
        )
        bindings.onChange = { calls.changes += 1 }
        return bindings
    }

    @Test func nothingIsRegisteredBeforeApply() {
        let bindings = makeBindings()

        #expect(hotkeys.registrations.isEmpty)
        #expect(bindings.editorCombo == nil)
        #expect(bindings.unavailable.isEmpty)
    }

    @Test func applyRegistersBothAndRoutesTheirEvents() {
        let calls = Calls()
        let bindings = makeBindings(calls)

        let failures = bindings.apply(editor: .default, reader: .readerDefault)
        hotkeys.simulate(.pressed, at: 1, for: .default)
        hotkeys.simulate(.released, at: 2, for: .default)
        hotkeys.simulate(.pressed, at: 3, for: .readerDefault)
        hotkeys.simulate(.released, at: 4, for: .readerDefault)

        #expect(failures.isEmpty)
        #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])
        // The editor is press-only; the reader gets both phases.
        #expect(calls.editorPresses == 1)
        #expect(calls.readerEvents == [HotkeyEvent(phase: .pressed, at: 3), HotkeyEvent(phase: .released, at: 4)])
        #expect(bindings.editorCombo == .default)
        #expect(bindings.readerCombo == .readerDefault)
        #expect(calls.changes == 1)
    }

    @Test func applyUnregistersEverythingBeforeRegistering() {
        let bindings = makeBindings()
        bindings.apply(editor: .default, reader: .readerDefault)
        let first = hotkeys.registrations

        let failures = bindings.apply(editor: other, reader: .readerDefault)

        #expect(failures.isEmpty)
        #expect(first.allSatisfy { $0.isUnregistered })
        #expect(hotkeys.live.map(\.combo) == [other, .readerDefault])
    }

    @Test func swappedCombosBothRegister() {
        let calls = Calls()
        let bindings = makeBindings(calls)
        bindings.apply(editor: .default, reader: .readerDefault)

        let failures = bindings.apply(editor: .readerDefault, reader: .default)
        hotkeys.simulate(.pressed, at: 1, for: .readerDefault)
        hotkeys.simulate(.pressed, at: 2, for: .default)

        #expect(failures.isEmpty)
        #expect(bindings.unavailable.isEmpty)
        #expect(hotkeys.live.map(\.combo) == [.readerDefault, .default])
        #expect(calls.editorPresses == 1)
        #expect(calls.readerEvents == [HotkeyEvent(phase: .pressed, at: 2)])
    }

    @Test func conflictingReaderIsNotRegistered() {
        let bindings = makeBindings()

        let failures = bindings.apply(editor: .default, reader: .default)

        #expect(failures == [.reader: .unavailable(.default)])
        #expect(hotkeys.live.map(\.combo) == [.default])
        #expect(bindings.unavailable == [.default])
        #expect(bindings.unavailableSlots == [.reader])    // the combo alone can't tell which slot failed
        #expect(bindings.readerCombo == .default)
    }

    @Test func readerOffIsNotRegisteredAndSkipsTheConflictCheck() {
        let calls = Calls()
        let bindings = makeBindings(calls)
        bindings.apply(editor: .default, reader: .readerDefault)

        let failures = bindings.apply(editor: .default, reader: nil)

        #expect(failures.isEmpty)
        #expect(hotkeys.live.map(\.combo) == [.default])
        #expect(bindings.readerCombo == nil)
        #expect(bindings.unavailable.isEmpty)
        #expect(calls.changes == 2)
    }

    @Test func unavailableListsRefusedCombosEditorFirst() {
        hotkeys.refusing = [.default, .readerDefault]
        let bindings = makeBindings()

        let failures = bindings.apply(editor: .default, reader: .readerDefault)

        #expect(failures == [.editor: .unavailable(.default), .reader: .unavailable(.readerDefault)])
        #expect(bindings.unavailable == [.default, .readerDefault])
        #expect(bindings.unavailableSlots == [.editor, .reader])
        #expect(hotkeys.live.isEmpty)
    }

    @Test func aSuccessfulApplyClearsUnavailable() {
        hotkeys.refusing = [other]
        let bindings = makeBindings()
        bindings.apply(editor: other, reader: .readerDefault)
        #expect(bindings.unavailable == [other])

        // The rollback a failed rebind does.
        bindings.apply(editor: .default, reader: .readerDefault)

        #expect(bindings.unavailable.isEmpty)
        #expect(bindings.unavailableSlots.isEmpty)
        #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])
    }

    @Test func suspendUnregistersBothAndApplyRestoresThem() {
        let calls = Calls()
        let bindings = makeBindings(calls)
        bindings.apply(editor: .default, reader: .readerDefault)

        bindings.suspend()
        hotkeys.simulate(.pressed, at: 1, for: .default)

        #expect(hotkeys.live.isEmpty)
        #expect(calls.editorPresses == 0)
        // The menu keeps its titles while recording.
        #expect(bindings.editorCombo == .default)
        #expect(calls.changes == 1)

        bindings.apply(editor: .default, reader: .readerDefault)
        hotkeys.simulate(.pressed, at: 2, for: .default)

        #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])
        #expect(calls.editorPresses == 1)
    }
}

import Testing
import LargeTextCore
import LargeTextTestSupport

/// The `settings-hotkey-taken` scenario's registrar: refuses its combos, passes the rest through.
@MainActor
struct RefusingHotkeyRegistrarTests {
    let taken = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])    // ⌃⌥⌘E
    let wrapped = SpyHotkeys()

    @Test func refusesItsCombosWithoutReachingTheWrappedRegistrar() {
        let registrar = RefusingHotkeyRegistrar(wrapping: wrapped, refusing: [taken])

        #expect(throws: HotkeyError.unavailable(taken)) {
            try registrar.register(taken) { _ in }
        }
        #expect(wrapped.registrations.isEmpty)
    }

    @Test func passesEverythingElseThrough() throws {
        let registrar = RefusingHotkeyRegistrar(wrapping: wrapped, refusing: [taken])
        var events: [HotkeyEvent] = []

        let registration = try registrar.register(.default) { events.append($0) }
        wrapped.simulate(.pressed, at: 1, for: .default)
        registration.unregister()

        #expect(wrapped.registrations.map(\.combo) == [.default])
        #expect(wrapped.live.isEmpty)
        #expect(events == [HotkeyEvent(phase: .pressed, at: 1)])
    }

    @Test func theWrappedRegistrarsOwnRefusalsStillApply() {
        wrapped.refusing = [.readerDefault]
        let registrar = RefusingHotkeyRegistrar(wrapping: wrapped, refusing: [taken])

        #expect(throws: HotkeyError.unavailable(.readerDefault)) {
            try registrar.register(.readerDefault) { _ in }
        }
    }
}

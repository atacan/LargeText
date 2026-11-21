import Testing
import LargeTextCore
import LargeTextTestSupport

/// `SpyHotkeys` refuses like Carbon, so the rebind tests built on it can catch ordering bugs.
@MainActor
struct SpyHotkeysTests {
    @Test func refusesConfiguredCombos() throws {
        let hotkeys = SpyHotkeys(refusing: [.readerDefault])

        #expect(throws: HotkeyError.unavailable(.readerDefault)) {
            try hotkeys.register(.readerDefault) { _ in }
        }
        _ = try hotkeys.register(.default) { _ in }
        #expect(hotkeys.registrations.map(\.combo) == [.default])
    }

    @Test func refusesAComboThatIsStillRegisteredUntilItIsUnregistered() throws {
        let hotkeys = SpyHotkeys()
        let first = try hotkeys.register(.default) { _ in }

        #expect(throws: HotkeyError.unavailable(.default)) {
            try hotkeys.register(.default) { _ in }
        }

        first.unregister()
        _ = try hotkeys.register(.default) { _ in }
        #expect(hotkeys.live.count == 1)
        #expect(hotkeys.registrations.count == 2)
    }
}

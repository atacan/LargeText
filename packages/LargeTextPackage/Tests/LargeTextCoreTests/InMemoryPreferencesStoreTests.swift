import Testing
import LargeTextCore

/// The fake must keep the live store's semantics, or suites built on it would test something else.
@MainActor
struct InMemoryPreferencesStoreTests {
    @Test func defaults() {
        let store = InMemoryPreferencesStore()

        #expect(store.readerHotkey == .readerDefault)
        #expect(store.readerFontSize == FontSizePolicy.default)
        #expect(store.hasCompletedFirstLaunch == false)
    }

    @Test func readerFontSizeFollowsTheEditorsUntilWritten() {
        let store = InMemoryPreferencesStore()

        store.fontSize = FontSize(points: 96)
        #expect(store.readerFontSize == FontSize(points: 96))

        store.readerFontSize = FontSize(points: 72)
        store.fontSize = FontSize(points: 120)
        #expect(store.readerFontSize == FontSize(points: 72))
    }

    @Test func initialReaderFontSizeIsKept() {
        let store = InMemoryPreferencesStore(fontSize: FontSize(points: 96), readerFontSize: FontSize(points: 48))

        #expect(store.readerFontSize == FontSize(points: 48))
    }

    @Test func readerHotkeyCanBeTurnedOff() {
        let store = InMemoryPreferencesStore(readerHotkey: nil)

        #expect(store.readerHotkey == nil)
    }
}

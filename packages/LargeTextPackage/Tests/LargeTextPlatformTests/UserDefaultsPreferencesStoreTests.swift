import Foundation
import LargeTextCore
import Testing
@testable import LargeTextPlatform

@Suite @MainActor struct UserDefaultsPreferencesStoreTests {
    func withDefaults(_ body: (UserDefaults, UserDefaultsPreferencesStore) throws -> Void) throws {
        let suiteName = "LargeText.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, UserDefaultsPreferencesStore(defaults: defaults))
    }

    @Test func defaultsWhenEmpty() throws {
        try withDefaults { _, store in
            #expect(store.fontSize == FontSize(points: 64))
            #expect(store.hotkey == .default)
            #expect(store.clipboardRestore == .default)
        }
    }

    @Test func roundTripsAllValues() throws {
        try withDefaults { defaults, store in
            store.fontSize = FontSize(points: 96)
            store.hotkey = KeyCombo(keyCode: 0x31, modifiers: [.command, .shift])
            store.clipboardRestore = .restore(maxBytes: 4096)

            let reread = UserDefaultsPreferencesStore(defaults: defaults)
            #expect(reread.fontSize == FontSize(points: 96))
            #expect(reread.hotkey == KeyCombo(keyCode: 0x31, modifiers: [.command, .shift]))
            #expect(reread.clipboardRestore == .restore(maxBytes: 4096))

            store.clipboardRestore = .none
            #expect(reread.clipboardRestore == .none)
        }
    }

    @Test func storedFormatsUsePrefixedKeys() throws {
        try withDefaults { defaults, store in
            store.fontSize = FontSize(points: 72)
            store.hotkey = .default
            store.clipboardRestore = .none
            #expect(defaults.double(forKey: "LargeText.fontSize") == 72)
            let hotkey = defaults.dictionary(forKey: "LargeText.hotkey")
            #expect(hotkey?["keyCode"] as? Int == 0x11)
            #expect(hotkey?["modifiers"] as? Int == Int(Modifiers([.control, .option, .command]).rawValue))
            #expect(defaults.string(forKey: "LargeText.clipboardRestore") == "none")
        }
    }

    /// Mirrors `defaults write <bundle id> LargeText.clipboardRestore none`.
    @Test func acceptsHandWrittenNoneString() throws {
        try withDefaults { defaults, store in
            defaults.set("none", forKey: "LargeText.clipboardRestore")
            #expect(store.clipboardRestore == .none)
            defaults.set(" NONE\n", forKey: "LargeText.clipboardRestore")
            #expect(store.clipboardRestore == .none)
            defaults.set("restore", forKey: "LargeText.clipboardRestore")
            #expect(store.clipboardRestore == .default)
        }
    }

    @Test func malformedValuesFallBackToDefaults() throws {
        try withDefaults { defaults, store in
            defaults.set("sometimes", forKey: "LargeText.clipboardRestore")
            defaults.set(-5.0, forKey: "LargeText.fontSize")
            defaults.set("⌘T", forKey: "LargeText.hotkey")
            #expect(store.clipboardRestore == .default)
            #expect(store.fontSize == FontSize(points: 64))
            #expect(store.hotkey == .default)
        }
    }

    @Test func handWrittenIntegerFontSizeAndHotkeyDictionary() throws {
        try withDefaults { defaults, store in
            defaults.set(120, forKey: "LargeText.fontSize")
            defaults.set(["keyCode": 0x23, "modifiers": 5], forKey: "LargeText.hotkey")
            #expect(store.fontSize == FontSize(points: 120))
            #expect(store.hotkey == KeyCombo(keyCode: 0x23, modifiers: [.command, .control]))
        }
    }
}

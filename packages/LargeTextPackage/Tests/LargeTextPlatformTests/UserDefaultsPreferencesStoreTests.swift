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
            #expect(store.readerHotkey == .readerDefault)
            #expect(store.readerHoldThreshold == .milliseconds(300))
            #expect(store.followingUnit == .sentence)
            #expect(store.pinnedUnit == .paragraph)
        }
    }

    @Test func roundTripsAllValues() throws {
        try withDefaults { defaults, store in
            store.fontSize = FontSize(points: 96)
            store.hotkey = KeyCombo(keyCode: 0x31, modifiers: [.command, .shift])
            store.clipboardRestore = .restore(maxBytes: 4096)
            store.readerHotkey = KeyCombo(keyCode: 0x0F, modifiers: [.option, .shift])
            store.readerHoldThreshold = .milliseconds(250)
            store.followingUnit = .line
            store.pinnedUnit = .sentence

            let reread = UserDefaultsPreferencesStore(defaults: defaults)
            #expect(reread.fontSize == FontSize(points: 96))
            #expect(reread.hotkey == KeyCombo(keyCode: 0x31, modifiers: [.command, .shift]))
            #expect(reread.clipboardRestore == .restore(maxBytes: 4096))
            #expect(reread.readerHotkey == KeyCombo(keyCode: 0x0F, modifiers: [.option, .shift]))
            #expect(reread.readerHoldThreshold == .milliseconds(250))
            #expect(reread.followingUnit == .line)
            #expect(reread.pinnedUnit == .sentence)

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

    @Test func readerStoredFormatsUsePrefixedKeys() throws {
        try withDefaults { defaults, store in
            store.readerHotkey = .readerDefault
            store.readerHoldThreshold = .milliseconds(350)
            store.followingUnit = .paragraph
            store.pinnedUnit = .line
            let hotkey = defaults.dictionary(forKey: "LargeText.readerHotkey")
            #expect(hotkey?["keyCode"] as? Int == 0x0F)
            #expect(hotkey?["modifiers"] as? Int == Int(Modifiers([.control, .option, .command]).rawValue))
            #expect(defaults.double(forKey: "LargeText.readerHoldThreshold") == 350)
            #expect(defaults.string(forKey: "LargeText.followingUnit") == "paragraph")
            #expect(defaults.string(forKey: "LargeText.pinnedUnit") == "line")
        }
    }

    /// Mirrors `defaults write <bundle id> LargeText.readerHoldThreshold -int 250` and hand-typed unit names.
    @Test func handWrittenReaderValues() throws {
        try withDefaults { defaults, store in
            defaults.set(250, forKey: "LargeText.readerHoldThreshold")
            defaults.set(" Line\n", forKey: "LargeText.followingUnit")
            defaults.set("SENTENCE", forKey: "LargeText.pinnedUnit")
            defaults.set(["keyCode": 0x0F, "modifiers": 3], forKey: "LargeText.readerHotkey")
            #expect(store.readerHoldThreshold == .milliseconds(250))
            #expect(store.followingUnit == .line)
            #expect(store.pinnedUnit == .sentence)
            #expect(store.readerHotkey == KeyCombo(keyCode: 0x0F, modifiers: [.command, .option]))
        }
    }

    @Test func malformedReaderValuesFallBackToDefaults() throws {
        try withDefaults { defaults, store in
            defaults.set(0, forKey: "LargeText.readerHoldThreshold")
            defaults.set("word", forKey: "LargeText.followingUnit")
            defaults.set(2, forKey: "LargeText.pinnedUnit")
            defaults.set("⌘R", forKey: "LargeText.readerHotkey")
            #expect(store.readerHoldThreshold == .milliseconds(300))
            #expect(store.followingUnit == .sentence)
            #expect(store.pinnedUnit == .paragraph)
            #expect(store.readerHotkey == .readerDefault)

            defaults.set("fast", forKey: "LargeText.readerHoldThreshold")
            #expect(store.readerHoldThreshold == .milliseconds(300))
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

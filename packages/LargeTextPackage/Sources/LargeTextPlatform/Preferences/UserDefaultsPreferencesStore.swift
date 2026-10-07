import Foundation
import LargeTextCore
import os

/// Live `PreferencesStore`. Every read goes to `UserDefaults`, so `defaults write` changes are picked up.
///
/// Stored formats (all keys prefixed `LargeText.`):
/// - `LargeText.fontSize`: number (points), e.g. `defaults write <id> LargeText.fontSize -float 96`.
/// - `LargeText.hotkey`: dictionary `{ keyCode: Int (Carbon kVK_*), modifiers: Int (Modifiers.rawValue:
///   1 = ⌘, 2 = ⌥, 4 = ⌃, 8 = ⇧) }`.
/// - `LargeText.clipboardRestore`: string `none` | `restore` | `restore:<bytes>`
///   (see `ClipboardRestorePolicy.init?(defaultsString:)`).
/// - `LargeText.readerHotkey`: dictionary, same format as `LargeText.hotkey`.
/// - `LargeText.readerHoldThreshold`: number (milliseconds), e.g. `defaults write <id> LargeText.readerHoldThreshold -int 250`.
/// - `LargeText.followingUnit`, `LargeText.pinnedUnit`: string `sentence` | `line` | `paragraph`.
///
/// Missing or malformed values fall back to the defaults (and are logged).
@MainActor
package final class UserDefaultsPreferencesStore: PreferencesStore {
    enum Key {
        static let fontSize = "LargeText.fontSize"
        static let hotkey = "LargeText.hotkey"
        static let clipboardRestore = "LargeText.clipboardRestore"
        static let readerHotkey = "LargeText.readerHotkey"
        static let readerHoldThreshold = "LargeText.readerHoldThreshold"
        static let followingUnit = "LargeText.followingUnit"
        static let pinnedUnit = "LargeText.pinnedUnit"
    }

    enum HotkeyField {
        static let keyCode = "keyCode"
        static let modifiers = "modifiers"
    }

    static let defaultFontSize = FontSizePolicy.default

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package var fontSize: FontSize {
        get {
            guard let number = defaults.object(forKey: Key.fontSize) as? NSNumber else { return Self.defaultFontSize }
            let points = number.doubleValue
            guard points.isFinite, points > 0 else {
                Logger.platform.notice("Ignoring invalid \(Key.fontSize, privacy: .public): \(points)")
                return Self.defaultFontSize
            }
            return FontSize(points: points)
        }
        set {
            defaults.set(newValue.points, forKey: Key.fontSize)
        }
    }

    package var hotkey: KeyCombo {
        get { keyCombo(forKey: Key.hotkey, default: .default) }
        set { setKeyCombo(newValue, forKey: Key.hotkey) }
    }

    package var clipboardRestore: ClipboardRestorePolicy {
        get {
            guard let object = defaults.object(forKey: Key.clipboardRestore) else { return .default }
            guard let string = object as? String, let policy = ClipboardRestorePolicy(defaultsString: string) else {
                Logger.platform.notice("Ignoring malformed \(Key.clipboardRestore, privacy: .public)")
                return .default
            }
            return policy
        }
        set {
            defaults.set(newValue.defaultsString, forKey: Key.clipboardRestore)
        }
    }

    package var readerHotkey: KeyCombo {
        get { keyCombo(forKey: Key.readerHotkey, default: .readerDefault) }
        set { setKeyCombo(newValue, forKey: Key.readerHotkey) }
    }

    package var readerHoldThreshold: Duration {
        get {
            guard let object = defaults.object(forKey: Key.readerHoldThreshold) else { return ReaderDefaults.holdThreshold }
            guard let milliseconds = (object as? NSNumber)?.doubleValue, milliseconds.isFinite, milliseconds > 0 else {
                Logger.platform.notice("Ignoring invalid \(Key.readerHoldThreshold, privacy: .public)")
                return ReaderDefaults.holdThreshold
            }
            return .milliseconds(milliseconds)
        }
        set {
            let components = newValue.components
            let milliseconds = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
            defaults.set(milliseconds, forKey: Key.readerHoldThreshold)
        }
    }

    package var followingUnit: ReadGranularity {
        get { granularity(forKey: Key.followingUnit, default: ReaderDefaults.followingUnit) }
        set { defaults.set(newValue.rawValue, forKey: Key.followingUnit) }
    }

    package var pinnedUnit: ReadGranularity {
        get { granularity(forKey: Key.pinnedUnit, default: ReaderDefaults.pinnedUnit) }
        set { defaults.set(newValue.rawValue, forKey: Key.pinnedUnit) }
    }

    // MARK: - Stored formats

    private func keyCombo(forKey key: String, default defaultCombo: KeyCombo) -> KeyCombo {
        guard let object = defaults.object(forKey: key) else { return defaultCombo }
        guard let dictionary = object as? [String: Any],
              let keyCode = (dictionary[HotkeyField.keyCode] as? NSNumber)?.uint32Value,
              let rawModifiers = (dictionary[HotkeyField.modifiers] as? NSNumber)?.uint8Value else {
            Logger.platform.notice("Ignoring malformed \(key, privacy: .public)")
            return defaultCombo
        }
        return KeyCombo(keyCode: keyCode, modifiers: Modifiers(rawValue: rawModifiers))
    }

    private func setKeyCombo(_ combo: KeyCombo, forKey key: String) {
        defaults.set(
            [
                HotkeyField.keyCode: Int(combo.keyCode),
                HotkeyField.modifiers: Int(combo.modifiers.rawValue),
            ],
            forKey: key
        )
    }

    /// Case-insensitive, ignoring surrounding whitespace, like `LargeText.clipboardRestore`.
    private func granularity(forKey key: String, default defaultUnit: ReadGranularity) -> ReadGranularity {
        guard let object = defaults.object(forKey: key) else { return defaultUnit }
        guard let string = object as? String,
              let unit = ReadGranularity(rawValue: string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            Logger.platform.notice("Ignoring malformed \(key, privacy: .public)")
            return defaultUnit
        }
        return unit
    }
}

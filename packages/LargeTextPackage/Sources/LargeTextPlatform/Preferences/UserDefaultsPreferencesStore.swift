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
/// - `LargeText.readerHotkey`: dictionary, same format as `LargeText.hotkey`, or the string `off` (reader
///   turned off). Missing means the default ⌃⌥⌘R, so turning it off writes `off` instead of removing the key.
/// - `LargeText.readerFontSize`: number (points), like `LargeText.fontSize`. Missing means "same as
///   `LargeText.fontSize`"; it is written on the first reader zoom.
/// - `LargeText.readerHoldThreshold`: number (milliseconds), e.g. `defaults write <id> LargeText.readerHoldThreshold -int 250`.
/// - `LargeText.followingUnit`, `LargeText.pinnedUnit`: string `sentence` | `line` | `paragraph`.
/// - `LargeText.hasCompletedFirstLaunch`: bool; missing means `false`.
///
/// Missing or malformed values fall back to the defaults (and are logged).
@MainActor
package final class UserDefaultsPreferencesStore: PreferencesStore {
    enum Key {
        static let fontSize = "LargeText.fontSize"
        static let hotkey = "LargeText.hotkey"
        static let clipboardRestore = "LargeText.clipboardRestore"
        static let readerHotkey = "LargeText.readerHotkey"
        static let readerFontSize = "LargeText.readerFontSize"
        static let readerHoldThreshold = "LargeText.readerHoldThreshold"
        static let followingUnit = "LargeText.followingUnit"
        static let pinnedUnit = "LargeText.pinnedUnit"
        static let hasCompletedFirstLaunch = "LargeText.hasCompletedFirstLaunch"
    }

    /// The `LargeText.readerHotkey` string that turns the reader off.
    static let readerHotkeyOff = "off"

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
        get { fontSize(forKey: Key.fontSize) ?? Self.defaultFontSize }
        set { defaults.set(newValue.points, forKey: Key.fontSize) }
    }

    /// Missing or invalid → the current `fontSize`.
    package var readerFontSize: FontSize {
        get { fontSize(forKey: Key.readerFontSize) ?? fontSize }
        set { defaults.set(newValue.points, forKey: Key.readerFontSize) }
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

    /// Case-insensitive `off`, ignoring surrounding whitespace, is `nil`; any other string is malformed.
    package var readerHotkey: KeyCombo? {
        get {
            if let string = defaults.object(forKey: Key.readerHotkey) as? String,
               string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.readerHotkeyOff {
                return nil
            }
            return keyCombo(forKey: Key.readerHotkey, default: .readerDefault)
        }
        set {
            if let newValue {
                setKeyCombo(newValue, forKey: Key.readerHotkey)
            } else {
                defaults.set(Self.readerHotkeyOff, forKey: Key.readerHotkey)
            }
        }
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

    package var hasCompletedFirstLaunch: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstLaunch) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstLaunch) }
    }

    // MARK: - Stored formats

    /// `nil` when missing; also `nil`, and logged, when not a positive finite number.
    private func fontSize(forKey key: String) -> FontSize? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let points = (object as? NSNumber)?.doubleValue, points.isFinite, points > 0 else {
            Logger.platform.notice("Ignoring invalid \(key, privacy: .public)")
            return nil
        }
        return FontSize(points: points)
    }

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

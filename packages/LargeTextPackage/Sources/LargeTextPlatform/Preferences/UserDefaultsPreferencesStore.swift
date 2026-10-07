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
///
/// Missing or malformed values fall back to the defaults (and are logged).
@MainActor
package final class UserDefaultsPreferencesStore: PreferencesStore {
    enum Key {
        static let fontSize = "LargeText.fontSize"
        static let hotkey = "LargeText.hotkey"
        static let clipboardRestore = "LargeText.clipboardRestore"
    }

    enum HotkeyField {
        static let keyCode = "keyCode"
        static let modifiers = "modifiers"
    }

    // TODO(kit-merge): use FontSizePolicy.default
    static let defaultFontSize = FontSize(points: 64)

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
        get {
            guard let object = defaults.object(forKey: Key.hotkey) else { return .default }
            guard let dictionary = object as? [String: Any],
                  let keyCode = (dictionary[HotkeyField.keyCode] as? NSNumber)?.uint32Value,
                  let rawModifiers = (dictionary[HotkeyField.modifiers] as? NSNumber)?.uint8Value else {
                Logger.platform.notice("Ignoring malformed \(Key.hotkey, privacy: .public)")
                return .default
            }
            return KeyCombo(keyCode: keyCode, modifiers: Modifiers(rawValue: rawModifiers))
        }
        set {
            defaults.set(
                [
                    HotkeyField.keyCode: Int(newValue.keyCode),
                    HotkeyField.modifiers: Int(newValue.modifiers.rawValue),
                ],
                forKey: Key.hotkey
            )
        }
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
}

import Foundation

/// A global shortcut. `keyCode` is a Carbon virtual key code (`kVK_*`).
package struct KeyCombo: Hashable, Codable, Sendable {
    package var keyCode: UInt32
    package var modifiers: Modifiers

    package init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘T (`kVK_ANSI_T` = 0x11).
    package static let `default` = KeyCombo(keyCode: 0x11, modifiers: [.control, .option, .command])
}

package enum HotkeyError: Error, Equatable, Sendable {
    case unavailable(KeyCombo)
}

package enum Keystroke: Equatable, Sendable {
    case paste
    case returnKey
}

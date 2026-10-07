import Foundation

/// Read limits, snapshotted once per reading session and passed to every `TextReading.read` (§3.3).
/// In v1 the values are constants; the snapshot is where preferences will feed in later.
package struct ReadPolicy: Equatable, Sendable {
    /// Bundle identifiers whose text is always `.hidden`, checked before any string is fetched.
    package var denylist: Set<String>
    /// Whole element text is used only up to this many characters.
    package var elementTextLimit: Int
    /// Shown text is capped at this many characters (ending in an ellipsis).
    package var maxCharacters: Int

    package init(denylist: Set<String>, elementTextLimit: Int, maxCharacters: Int) {
        self.denylist = denylist
        self.elementTextLimit = elementTextLimit
        self.maxCharacters = maxCharacters
    }

    package static let standard = ReadPolicy(
        denylist: passwordManagers,
        elementTextLimit: 500,
        maxCharacters: 4_000
    )

    /// Password managers and keychains show revealed passwords and 2FA codes as plain `AXStaticText` (§4.10).
    /// Hard-coded in v1; a user-editable list is deferred.
    package static let passwordManagers: Set<String> = [
        "com.1password.1password",          // 1Password 8
        "com.agilebits.onepassword7",       // 1Password 7
        "com.agilebits.onepassword-osx",    // 1Password 6 and older Mac App Store builds (not verified locally)
        "com.bitwarden.desktop",            // Bitwarden
        "com.apple.keychainaccess",         // Keychain Access
        "com.apple.Passwords",              // Passwords (macOS 15+)
        "com.apple.Passwords.MenuBarExtra", // Passwords menu bar extra
    ]
}

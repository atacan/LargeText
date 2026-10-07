import Foundation

/// Adjusts committed text for the target. Pasting multi-line text into a shell can execute commands,
/// and single-line fields drop or mangle newlines, so both get newlines replaced with spaces.
package enum InsertionTextPolicy {
    /// Known terminal emulators.
    package static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "org.tabby",
    ]

    /// True for single-line elements (AXTextField, AXSearchField, AXComboBox map to `.singleLineText`)
    /// and for known terminal bundle ids.
    package static func flattensNewlines(for target: FocusTarget) -> Bool {
        if target.elementKind == .singleLineText { return true }
        guard let bundleIdentifier = target.application?.bundleIdentifier else { return false }
        return terminalBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Replaces every newline sequence (`\r\n`, `\n`, `\r`, and other Unicode line breaks) with one space
    /// when `flattensNewlines(for:)` is true; otherwise returns `text` unchanged.
    package static func prepare(_ text: String, for target: FocusTarget) -> String {
        guard flattensNewlines(for: target) else { return text }
        // `\r\n` is a single `Character`, so each sequence becomes exactly one space.
        return String(text.map { $0.isNewline ? " " : $0 })
    }
}

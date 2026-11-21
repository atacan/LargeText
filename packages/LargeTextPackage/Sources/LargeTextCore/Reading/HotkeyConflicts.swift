import Foundation

/// Checks the two global shortcuts against each other (§4.10). A preference setter can't refuse a value,
/// and `defaults write` bypasses it anyway, so Kit's `HotkeyBindings` asks here before registering.
package enum HotkeyConflicts {
    /// The reader combo to register, or `.unavailable(reader)` when it equals the editor's. The editor keeps
    /// its shortcut; the reader is then not registered and `Notice.hotkeyUnavailable` is reported.
    package static func validate(editor: KeyCombo, reader: KeyCombo) -> Result<KeyCombo, HotkeyError> {
        reader == editor ? .failure(.unavailable(reader)) : .success(reader)
    }
}

import Foundation

/// Class-bound: one shared instance.
@MainActor
package protocol PreferencesStore: AnyObject {
    /// The editor's text size; ⌘± in the editor writes it.
    var fontSize: FontSize { get set }
    var hotkey: KeyCombo { get set }
    var clipboardRestore: ClipboardRestorePolicy { get set }
    /// `nil` turns the reader off: it isn't registered and the status menu leaves it out. May equal
    /// `hotkey`; Kit checks for the conflict, since a setter can't refuse a value (§4.10).
    var readerHotkey: KeyCombo? { get set }
    /// The reader card's text size; ⌘± on the pinned card writes it. Until it is first written it follows
    /// `fontSize`, so an existing user's reader keeps the size it had.
    var readerFontSize: FontSize { get set }
    var readerHoldThreshold: Duration { get set }
    var followingUnit: ReadGranularity { get set }
    var pinnedUnit: ReadGranularity { get set }
    /// Set once the first launch has run its one-time setup (Settings plan §3.6).
    var hasCompletedFirstLaunch: Bool { get set }
}

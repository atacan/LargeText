import Foundation

/// Class-bound: one shared instance.
@MainActor
package protocol PreferencesStore: AnyObject {
    var fontSize: FontSize { get set }
    var hotkey: KeyCombo { get set }
    var clipboardRestore: ClipboardRestorePolicy { get set }
    /// May equal `hotkey`; Kit checks for the conflict, since a setter can't refuse a value (§4.10).
    var readerHotkey: KeyCombo { get set }
    var readerHoldThreshold: Duration { get set }
    var followingUnit: ReadGranularity { get set }
    var pinnedUnit: ReadGranularity { get set }
}

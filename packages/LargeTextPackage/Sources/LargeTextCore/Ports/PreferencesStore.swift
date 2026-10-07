import Foundation

/// Class-bound: one shared instance.
@MainActor
package protocol PreferencesStore: AnyObject {
    var fontSize: FontSize { get set }
    var hotkey: KeyCombo { get set }
    var clipboardRestore: ClipboardRestorePolicy { get set }
}

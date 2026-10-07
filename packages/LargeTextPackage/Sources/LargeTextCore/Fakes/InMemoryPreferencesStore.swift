import Foundation

@MainActor
package final class InMemoryPreferencesStore: PreferencesStore {
    package var fontSize: FontSize
    package var hotkey: KeyCombo
    package var clipboardRestore: ClipboardRestorePolicy

    package init(
        fontSize: FontSize = FontSizePolicy.default,
        hotkey: KeyCombo = .default,
        clipboardRestore: ClipboardRestorePolicy = .default
    ) {
        self.fontSize = fontSize
        self.hotkey = hotkey
        self.clipboardRestore = clipboardRestore
    }
}

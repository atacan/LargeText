import Foundation

@MainActor
package final class InMemoryPreferencesStore: PreferencesStore {
    package var fontSize: FontSize
    package var hotkey: KeyCombo
    package var clipboardRestore: ClipboardRestorePolicy
    package var readerHotkey: KeyCombo
    package var readerHoldThreshold: Duration
    package var followingUnit: ReadGranularity
    package var pinnedUnit: ReadGranularity

    package init(
        fontSize: FontSize = FontSizePolicy.default,
        hotkey: KeyCombo = .default,
        clipboardRestore: ClipboardRestorePolicy = .default,
        readerHotkey: KeyCombo = .readerDefault,
        readerHoldThreshold: Duration = ReaderDefaults.holdThreshold,
        followingUnit: ReadGranularity = ReaderDefaults.followingUnit,
        pinnedUnit: ReadGranularity = ReaderDefaults.pinnedUnit
    ) {
        self.fontSize = fontSize
        self.hotkey = hotkey
        self.clipboardRestore = clipboardRestore
        self.readerHotkey = readerHotkey
        self.readerHoldThreshold = readerHoldThreshold
        self.followingUnit = followingUnit
        self.pinnedUnit = pinnedUnit
    }
}

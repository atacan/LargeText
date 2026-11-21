import Foundation

@MainActor
package final class InMemoryPreferencesStore: PreferencesStore {
    package var fontSize: FontSize
    package var hotkey: KeyCombo
    package var clipboardRestore: ClipboardRestorePolicy
    package var readerHotkey: KeyCombo?
    package var readerHoldThreshold: Duration
    package var followingUnit: ReadGranularity
    package var pinnedUnit: ReadGranularity
    package var hasCompletedFirstLaunch: Bool
    /// `nil` until written, like the live store's missing key.
    private var storedReaderFontSize: FontSize?

    /// Follows `fontSize` until it is written, like `UserDefaultsPreferencesStore`.
    package var readerFontSize: FontSize {
        get { storedReaderFontSize ?? fontSize }
        set { storedReaderFontSize = newValue }
    }

    /// - Parameter readerFontSize: `nil` follows `fontSize`.
    package init(
        fontSize: FontSize = FontSizePolicy.default,
        hotkey: KeyCombo = .default,
        clipboardRestore: ClipboardRestorePolicy = .default,
        readerHotkey: KeyCombo? = .readerDefault,
        readerFontSize: FontSize? = nil,
        readerHoldThreshold: Duration = ReaderDefaults.holdThreshold,
        followingUnit: ReadGranularity = ReaderDefaults.followingUnit,
        pinnedUnit: ReadGranularity = ReaderDefaults.pinnedUnit,
        hasCompletedFirstLaunch: Bool = false
    ) {
        self.fontSize = fontSize
        self.hotkey = hotkey
        self.clipboardRestore = clipboardRestore
        self.readerHotkey = readerHotkey
        storedReaderFontSize = readerFontSize
        self.readerHoldThreshold = readerHoldThreshold
        self.followingUnit = followingUnit
        self.pinnedUnit = pinnedUnit
        self.hasCompletedFirstLaunch = hasCompletedFirstLaunch
    }
}

import Foundation

/// Everything the Settings window can ask `SettingsCoordinator` to do.
package enum SettingsIntent: Equatable, Sendable {
    /// Suspends both global shortcuts, so the combo being recorded doesn't trigger them.
    case beginRecording(ShortcutSlot)
    /// ⎋ in the recorder: registers the saved combos again.
    case cancelRecording
    /// A combo from the recorder: checked, tried, then saved or rolled back.
    case record(ShortcutSlot, KeyCombo)
    /// Back to `slot.defaultCombo`; for the reader this also turns it back on.
    case resetShortcut(ShortcutSlot)
    /// Saves `readerHotkey = nil` and unregisters it (D1).
    case turnOffReader
    case setEditorFontSize(FontSize)
    case setReaderFontSize(FontSize)
    case setHoldThreshold(Duration)
    case setFollowingUnit(ReadGranularity)
    case setPinnedUnit(ReadGranularity)
    case setRestoresClipboard(Bool)
    case setLaunchAtLogin(Bool)
    /// "Grant Access…": adds the app to the Accessibility list, then opens System Settings (D6).
    case grantAccess
    /// "Relaunch to finish setup".
    case relaunch
    /// The "requires approval" link: System Settings › Login Items.
    case openLoginItemsSettings
    /// Writes every default and registers the default shortcuts once. Launch at login is system state and
    /// is left alone.
    case resetAll
    /// The window became key: re-reads the store (⌘± may have changed a size) and the permissions.
    case becameKey
    /// The window resigned key: ends any recording, like `cancelRecording`, so the shortcuts never stay
    /// suspended while the user is in another app.
    case resignedKey
    /// The window closed: ends any recording and stops the permission refresh.
    case closed
}

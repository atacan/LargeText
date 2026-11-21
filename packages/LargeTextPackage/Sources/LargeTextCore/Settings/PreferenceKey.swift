import Foundation

/// A preference the Settings window shows, so a launch-argument override can be named per row
/// (`SettingsContext.launchOverrides`).
package enum PreferenceKey: CaseIterable, Hashable, Sendable {
    case hotkey
    case readerHotkey
    case fontSize
    case readerFontSize
    case readerHoldThreshold
    case followingUnit
    case pinnedUnit
    case clipboardRestore
}

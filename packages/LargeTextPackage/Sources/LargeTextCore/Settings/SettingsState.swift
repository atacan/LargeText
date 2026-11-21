import Foundation

/// What the Settings window shows; `SettingsCoordinator` builds it and sends every change as a whole value.
package struct SettingsState: Equatable, Sendable {
    package struct Shortcut: Equatable, Sendable {
        /// The saved combo; `nil` when the reader is off. The editor's is never `nil`.
        package var combo: KeyCombo?
        package var isRecording: Bool
        /// Why the last recorded or reset combo wasn't used. Cleared by the next recording or a success.
        package var problem: ShortcutProblem?
        /// Whether the last registration of `combo` succeeded. Not cleared while recording suspends it.
        package var isRegistered: Bool

        package init(combo: KeyCombo?, isRecording: Bool = false, problem: ShortcutProblem? = nil, isRegistered: Bool) {
            self.combo = combo
            self.isRecording = isRecording
            self.problem = problem
            self.isRegistered = isRegistered
        }
    }

    package var editorShortcut: Shortcut
    package var readerShortcut: Shortcut
    /// Clamped to `FontSizePolicy.range`, as the editor uses it.
    package var editorFontSize: FontSize
    /// Clamped to `FontSizePolicy.range`, as the reader uses it.
    package var readerFontSize: FontSize
    /// As stored, which `defaults write` may have put outside `ReaderDefaults.holdThresholdRange`.
    package var holdThreshold: Duration
    package var followingUnit: ReadGranularity
    package var pinnedUnit: ReadGranularity
    /// Off = `ClipboardRestorePolicy.none`.
    package var restoresClipboard: Bool
    package var permission: PermissionSetup
    /// `nil` when launch at login isn't offered (no `LoginItemControlling`).
    package var loginItem: LoginItemStatus?
    /// The last enable or disable that failed; cleared by the next attempt.
    package var loginItemError: LoginItemError?
    /// Daily update checks; `nil` when this build can't update itself (no available `UpdateChecking`).
    package var automaticallyChecksForUpdates: Bool?
    /// Whether "Check Now" is enabled; false while a check or an update is in progress.
    package var canCheckForUpdates: Bool
    package var context: SettingsContext

    package init(
        editorShortcut: Shortcut,
        readerShortcut: Shortcut,
        editorFontSize: FontSize,
        readerFontSize: FontSize,
        holdThreshold: Duration,
        followingUnit: ReadGranularity,
        pinnedUnit: ReadGranularity,
        restoresClipboard: Bool,
        permission: PermissionSetup,
        loginItem: LoginItemStatus?,
        loginItemError: LoginItemError? = nil,
        automaticallyChecksForUpdates: Bool? = nil,
        canCheckForUpdates: Bool = false,
        context: SettingsContext
    ) {
        self.editorShortcut = editorShortcut
        self.readerShortcut = readerShortcut
        self.editorFontSize = editorFontSize
        self.readerFontSize = readerFontSize
        self.holdThreshold = holdThreshold
        self.followingUnit = followingUnit
        self.pinnedUnit = pinnedUnit
        self.restoresClipboard = restoresClipboard
        self.permission = permission
        self.loginItem = loginItem
        self.loginItemError = loginItemError
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        self.context = context
    }

    package subscript(slot: ShortcutSlot) -> Shortcut {
        get {
            switch slot {
            case .editor: editorShortcut
            case .reader: readerShortcut
            }
        }
        set {
            switch slot {
            case .editor: editorShortcut = newValue
            case .reader: readerShortcut = newValue
            }
        }
    }

    /// The hold threshold and unit controls are disabled while this is false.
    package var isReaderOn: Bool { readerShortcut.combo != nil }
}

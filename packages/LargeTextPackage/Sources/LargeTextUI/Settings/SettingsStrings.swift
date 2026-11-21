import LargeTextCore

/// The Settings window's user-visible strings. Pure.
package enum SettingsStrings {
    package static let windowTitle = "LargeText Settings"

    // MARK: - Sections

    package static let shortcutsSection = "Shortcuts"
    package static let textSizeSection = "Text Size"
    package static let readerSection = "Reader"
    package static let clipboardSection = "Clipboard"
    package static let accessibilitySection = "Accessibility"
    package static let startupSection = "Startup"
    package static let updatesSection = "Updates"

    // MARK: - Shortcuts

    package static let reset = "Reset"
    package static let turnOff = "Turn Off"
    package static let off = "Off"
    package static let shortcutsFootnote = "If a shortcut doesn't respond, another app may be using it."

    package static func shortcutTitle(_ slot: ShortcutSlot) -> String {
        switch slot {
        case .editor: "Open Large Editor"
        case .reader: "Read Text Under Pointer"
        }
    }

    /// "⌃⌥⌘T", or "Off" for a reader that is turned off.
    package static func combo(_ combo: KeyCombo?) -> String {
        combo.map(KeyComboFormatter.string(for:)) ?? off
    }

    /// Why a recorded or reset combo wasn't used.
    package static func problem(_ problem: ShortcutProblem) -> String {
        switch problem {
        case .needsModifier:
            "Use at least one of ⌃, ⌥ or ⌘. Function keys work on their own."
        case .optionOnlyRefused:
            "macOS doesn't allow ⌥ on its own in a shortcut. Add ⌃ or ⌘."
        case .reservedBySystem:
            "macOS or every app already uses this shortcut."
        case .sameAsOther(let slot):
            "Already used for \(shortcutTitle(slot))."
        case .unavailable:
            "This shortcut couldn't be registered. Another app may be using it."
        }
    }

    // MARK: - Recorder

    package static let recordingPrompt = "Type Shortcut"
    package static let recordingHint = "Press the new shortcut, or ⎋ to cancel. Both shortcuts are paused meanwhile."
    package static let recorderHelp = "Click to record a new shortcut."
    package static let recorderRoleDescription = "shortcut recorder"

    /// What a recording recorder shows: the prompt, then the modifiers held so far ("⌃⌥…").
    package static func recording(_ modifiers: Modifiers) -> String {
        modifiers.isEmpty ? recordingPrompt : KeyComboFormatter.modifierSymbols(modifiers) + "…"
    }

    /// The saved combo couldn't be registered, at launch or after a change.
    package static let notRegistered = "Not working: another app may be using this shortcut."

    // MARK: - Text size

    package static let editorFontSize = "Editor"
    package static let readerFontSize = "Reader"
    package static let fontSizeFootnote = "⌘+ and ⌘− in the editor or on the pinned card change these too."

    package static func fontSize(_ size: FontSize) -> String {
        "\(Int(size.points.rounded())) pt"
    }

    // MARK: - Reader

    package static let holdThreshold = "Hold to follow after"
    package static let followingUnit = "While following, show"
    package static let pinnedUnit = "When pinned, show"
    package static let readerOffFootnote = "The reader is off. Reset its shortcut to turn it on."

    package static func milliseconds(_ milliseconds: Int) -> String {
        "\(milliseconds) ms"
    }

    package static func unit(_ unit: ReadGranularity) -> String {
        switch unit {
        case .sentence: "Sentence"
        case .line: "Line"
        case .paragraph: "Paragraph"
        }
    }

    // MARK: - Clipboard

    package static let restoresClipboard = "Restore clipboard after pasting"
    package static let clipboardFootnote = "LargeText pastes through the clipboard and then puts back what was there. "
        + "On macOS 15.4 and later, apps may ask whether LargeText can read the clipboard."

    // MARK: - Accessibility

    package static let accessibilityTitle = "Accessibility access"
    package static let grantAccess = "Grant Access…"
    package static let relaunch = "Relaunch"

    package static func permissionStatus(_ setup: PermissionSetup) -> String {
        switch setup {
        case .granted: "Granted ✓"
        case .needsRelaunch: "Relaunch to finish setup"
        case .needsGrant: "Not granted"
        }
    }

    package static func permissionFootnote(_ setup: PermissionSetup) -> String? {
        switch setup {
        case .granted: nil
        case .needsRelaunch: "Access is granted, but pasting only starts working after LargeText starts again."
        case .needsGrant: "LargeText needs Accessibility access to read text and to paste into other apps. "
            + "Without it, the editor copies to the clipboard instead."
        }
    }

    // MARK: - Updates

    package static let automaticallyChecksForUpdates = "Check for updates automatically"
    package static let checkForUpdatesNow = "Check Now"
    package static let updatesFootnote = "LargeText checks once a day and asks before installing an update."

    // MARK: - Launch at login

    package static let launchAtLogin = "Launch at login"
    package static let openLoginItems = "Open Login Items…"

    /// Below the toggle: what the system still needs, if anything.
    package static func loginItemNote(_ status: LoginItemStatus) -> String? {
        switch status {
        case .enabled, .notRegistered: nil
        case .requiresApproval: "Allow LargeText in System Settings › General › Login Items to finish turning this on."
        case .notFound: "macOS can't find LargeText's login item. Move LargeText to the Applications folder and try again."
        }
    }

    /// Why the last change didn't happen.
    package static func loginItemError(_ error: LoginItemError) -> String {
        switch error {
        case .notPermitted: "macOS didn't allow this change. You can allow it in System Settings › General › Login Items."
        case .failed(let code): "Launch at login couldn't be changed (error \(code))."
        }
    }

    /// The Login Items button shows when the user has something to do there.
    package static func showsOpenLoginItems(status: LoginItemStatus, error: LoginItemError?) -> Bool {
        status == .requiresApproval || error == .notPermitted
    }

    // MARK: - Reset all

    package static let resetAll = "Reset All Settings…"
    package static let resetAllConfirmTitle = "Reset all settings?"
    package static let resetAllConfirmButton = "Reset All"
    package static let resetAllConfirmMessage = "Shortcuts, text sizes, reader and clipboard settings go back to "
        + "their defaults."
    package static let cancel = "Cancel"

    // MARK: - This run only

    /// A per-row note for a preference set on the command line.
    package static func overrideNote(_ key: PreferenceKey) -> String {
        if let argument = launchArgument(for: key) {
            "Set by \(argument) for this run; not saved."
        } else {
            "Set on the command line for this run; not saved."
        }
    }

    /// The banner while a `--scenario` is active.
    package static func scenarioBanner(_ name: String) -> String {
        "Scenario '\(name)': changes are kept in memory only."
    }

    private static func launchArgument(for key: PreferenceKey) -> String? {
        switch key {
        case .readerHoldThreshold: "--reader-hold-threshold"
        case .followingUnit: "--following-unit"
        case .hotkey, .readerHotkey, .fontSize, .readerFontSize, .pinnedUnit, .clipboardRestore: nil
        }
    }
}

import CoreGraphics
import Foundation
import LargeTextCore
import LargeTextUI

/// Launch-time states for hands-on testing (`--scenario <rawValue>`), compiled unconditionally (§3.2).
///
/// A scenario only mutates the `AppEnvironment` before assembly; `AppController` additionally starts the
/// `ReaderProbe` for `reader-probe`. Every scenario swaps in an `InMemoryPreferencesStore`, so zooming or
/// other preference writes never touch the real defaults, and an `InMemoryLoginItem`, so the Settings toggle
/// never registers the app for launch at login. Its first launch is already done, so Settings only
/// opens by itself in `first-launch`. Kit-owned responsibilities (activation policy,
/// status item, hotkeys (except in `settings-hotkey-taken`), permission request) stay live.
///
/// Note: with `inserterOverride` set, the overlay's header hints still reflect the real `InsertionRoute`.
package enum Scenario: String, CaseIterable, Sendable {
    /// Focus: stub Safari URL bar with the selection "https://www.apple.com". Inserter: `LoggingTextInserter`.
    /// Live: hotkey, permissions, overlay, HUD. Nothing is pasted. Use with `--present-on-launch`.
    case overlayPrefilled = "overlay-prefilled"
    /// Focus: stub Safari target whose element is `.notEditable`. Live: permissions, real pasteboard,
    /// real `PasteboardTextInserter`, overlay, HUD → commit copies to the clipboard and shows the HUD.
    case noEditableTarget = "no-editable-target"
    /// Permissions: `FixedPermissions(.allDenied)` (and no system prompt). Live: focus capture, real pasteboard,
    /// real `PasteboardTextInserter`, overlay, HUD → commit is copy-only with the "permission missing" HUD.
    case permissionMissing = "permission-missing"
    /// Inserter: `LoggingTextInserter`. Everything else is live, including focus capture and permissions.
    case loggingInsertion = "logging-insertion"
    /// Reader: `StubTextReader` answering by the pointer's global x in 400 pt bands: a short label, a long
    /// paragraph, nothing, then hidden from 1 200 pt on (`--reader-stub-delay <ms>` slows it down).
    /// Permissions: `FixedPermissions(.allGranted)`, since the stub needs no Accessibility; the editor therefore
    /// uses `LoggingTextInserter`. Live: hotkeys, pointer, key state, reader panel, HUD.
    case readerStub = "reader-stub"
    /// Permissions: `FixedPermissions(.allDenied)` (and no system prompt). The reader shortcut shows the
    /// "Allow Accessibility to read text" HUD instead of a card; the status menu offers "Grant Access…".
    case readerNoAccessibility = "reader-no-accessibility"
    /// Everything live. `AppController` runs `ReaderProbe`, which logs what the element under the pointer
    /// exposes once per second: the harness for spikes R2–R6 and R8. The reader shortcut works as usual.
    case readerProbe = "reader-probe"
    /// Permissions: Accessibility granted, event posting denied (spike 0i), so the status menu and Settings
    /// offer "Relaunch to finish setup". Use with `--present-settings-on-launch`.
    case settingsNeedsRelaunch = "settings-needs-relaunch"
    /// Preferences: a first launch (`hasCompletedFirstLaunch == false`). Permissions:
    /// `FixedPermissions(.allDenied)`, so Settings opens at launch (Settings plan §3.6); the system prompt is
    /// skipped because the permissions are fixed.
    case firstLaunch = "first-launch"
    /// Hotkeys: `RefusingHotkeyRegistrar` around the live registrar, refusing ⌃⌥⌘E and ⌃⌥⌘Y
    /// (`takenCombos`) as if another app held them. Recording either in Settings shows "couldn't be registered"
    /// and keeps the saved shortcut working. Everything else is live. Use with `--present-settings-on-launch`.
    case settingsHotkeyTaken = "settings-hotkey-taken"

    @MainActor
    package func apply(to environment: inout AppEnvironment) {
        environment.preferences = InMemoryPreferencesStore(hasCompletedFirstLaunch: self != .firstLaunch)
        environment.loginItem = InMemoryLoginItem()
        if environment.settingsPresenter is SettingsWindowController {
            // Not even the window frame is saved.
            environment.settingsPresenter = SettingsWindowController(frameAutosaveName: nil)
        }
        switch self {
        case .overlayPrefilled:
            environment.focus = StubFocusCapturer(target: Self.safariTarget(kind: .singleLineText, selection: "https://www.apple.com"))
            environment.inserterOverride = LoggingTextInserter()
        case .noEditableTarget:
            environment.focus = StubFocusCapturer(target: Self.safariTarget(kind: .notEditable, selection: nil))
        case .permissionMissing:
            environment.permissions = FixedPermissions(.allDenied)
        case .loggingInsertion:
            environment.inserterOverride = LoggingTextInserter()
        case .readerStub:
            environment.textReader = Self.stubTextReader()
            environment.permissions = FixedPermissions(.allGranted)
            environment.inserterOverride = LoggingTextInserter()
        case .readerNoAccessibility:
            environment.permissions = FixedPermissions(.allDenied)
        case .readerProbe:
            break
        case .settingsNeedsRelaunch:
            environment.permissions = FixedPermissions(Permissions(accessibility: .granted, eventPosting: .denied))
        case .firstLaunch:
            environment.permissions = FixedPermissions(.allDenied)
        case .settingsHotkeyTaken:
            environment.hotkeys = RefusingHotkeyRegistrar(wrapping: environment.hotkeys, refusing: Self.takenCombos)
        }
    }

    /// ⌃⌥⌘E and ⌃⌥⌘Y: refused by `settings-hotkey-taken`.
    static let takenCombos: Set<KeyCombo> = [
        KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command]),
        KeyCombo(keyCode: 0x10, modifiers: [.control, .option, .command]),
    ]

    // MARK: - Reader stub

    /// Width of each `reader-stub` band, in points of global x.
    static let stubBandWidth: CGFloat = 400

    /// Label, paragraph and nothing bands from x = 0; hidden beyond them.
    static func stubTextReader() -> StubTextReader {
        let results: [ReadResult] = [stubLabel, stubParagraph, .nothing]
        return StubTextReader(
            answers: results.enumerated().map { index, result in
                let lower = CGFloat(index) * stubBandWidth
                return StubTextReader.Answer(xRange: lower..<(lower + stubBandWidth), result: result)
            },
            fallback: .hidden
        )
    }

    static let stubLabel = ReadResult.text(ReadText(
        text: "Open Large Editor",
        granularity: .sentence,
        source: .label,
        appName: "Safari",
        bundleIdentifier: "com.apple.Safari"
    ))

    static let stubParagraph = ReadResult.text(ReadText(
        text: Array(
            repeating: "The reader shows the text under the pointer in a large card, so it can be read from across the room. "
                + "Hold the shortcut to follow the pointer; tap it to pin the card and scroll. "
                + "This paragraph repeats so that the card overflows.",
            count: 12
        ).joined(separator: " "),
        granularity: .paragraph,
        source: .element,
        appName: "Notes",
        bundleIdentifier: "com.apple.Notes"
    ))

    @MainActor
    private static func safariTarget(kind: ElementKind, selection: String?) -> FocusTarget {
        FocusTarget(
            application: TargetApplication(
                processIdentifier: 0,
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari"
            ),
            elementKind: kind,
            selectedText: selection
        )
    }
}

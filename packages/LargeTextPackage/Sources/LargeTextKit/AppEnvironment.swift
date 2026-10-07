import AppKit
import LargeTextCore
import LargeTextPlatform
import LargeTextUI

/// Every side-effecting service the app uses, as plain instances (§3.9).
///
/// Constructing one has no side effects: adapters defer observers, prompts, Carbon handlers and windows
/// until first use. A `Scenario` mutates this value before `coreDependencies()` assembles it.
package struct AppEnvironment {
    package var hotkeys: any HotkeyRegistering
    package var focus: any FocusCapturing
    package var permissions: any PermissionsProviding
    package var pasteboard: any PasteboardClient
    package var keystrokes: any KeystrokeSending
    package var preferences: any PreferencesStore
    package var sleeper: any Sleeper
    package var overlay: any OverlayPresenting
    package var notices: any NoticePresenting
    /// `nil` → a `PasteboardTextInserter` built from the services above.
    package var inserterOverride: (any TextInserting)?

    package init(
        hotkeys: any HotkeyRegistering,
        focus: any FocusCapturing,
        permissions: any PermissionsProviding,
        pasteboard: any PasteboardClient,
        keystrokes: any KeystrokeSending,
        preferences: any PreferencesStore,
        sleeper: any Sleeper,
        overlay: any OverlayPresenting,
        notices: any NoticePresenting,
        inserterOverride: (any TextInserting)? = nil
    ) {
        self.hotkeys = hotkeys
        self.focus = focus
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.preferences = preferences
        self.sleeper = sleeper
        self.overlay = overlay
        self.notices = notices
        self.inserterOverride = inserterOverride
    }

    /// The production environment. Side-effect free.
    @MainActor
    package static func live() -> AppEnvironment {
        AppEnvironment(
            hotkeys: CarbonHotkeyRegistrar(),
            focus: AccessibilityFocusCapturer(),
            permissions: SystemPermissionsProvider(),
            pasteboard: SystemPasteboardClient(pasteboard: .general),
            keystrokes: CGEventKeystrokeSender(),
            preferences: UserDefaultsPreferencesStore(defaults: .standard),
            sleeper: TaskSleeper(),
            overlay: OverlayWindowController(),
            notices: HUDNoticePresenter()
        )
    }

    /// Assembles the coordinator's dependencies. Runs AFTER scenario mutation, so overrides are respected.
    @MainActor
    package func coreDependencies() -> CoreDependencies {
        let inserter = inserterOverride ?? PasteboardTextInserter(
            permissions: permissions,
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            focus: focus,
            preferences: preferences,
            sleeper: sleeper
        )
        return CoreDependencies(
            focus: focus,
            permissions: permissions,
            inserter: inserter,
            overlay: overlay,
            notices: notices,
            preferences: preferences
        )
    }
}

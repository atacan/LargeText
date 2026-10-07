import AppKit
import LargeTextCore
import LargeTextPlatform
import LargeTextUI

/// Every side-effecting service the app uses, as plain instances (§3.9).
///
/// Constructing one has no side effects: adapters defer observers, prompts, Carbon handlers and windows
/// until first use. A `Scenario` (via `LaunchConfiguration.apply(to:)`) mutates this value before
/// `coreDependencies()` and `readerDependencies(timing:)` assemble it.
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
    package var textReader: any TextReading
    package var pointer: any PointerTracking
    package var keyState: any KeyStateReading
    package var readerPresenter: any ReaderPresenting

    /// The reader services default to Core fakes, so call sites that predate the reader keep compiling.
    @MainActor
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
        inserterOverride: (any TextInserting)? = nil,
        textReader: any TextReading = StubTextReader(),
        pointer: any PointerTracking = ScriptedPointer(),
        keyState: any KeyStateReading = FixedKeyState(),
        readerPresenter: any ReaderPresenting = LoggingReaderPresenter()
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
        self.textReader = textReader
        self.pointer = pointer
        self.keyState = keyState
        self.readerPresenter = readerPresenter
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
            notices: HUDNoticePresenter(),
            textReader: AccessibilityTextReader(),
            pointer: SystemPointerTracker(),
            // Spike R1 decides between `.keyState` and the modifier fallback.
            keyState: SystemKeyStateReader(mode: .keyState),
            readerPresenter: ReaderWindowController()
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

    /// Assembles the reading coordinator's dependencies, after any scenario mutation like `coreDependencies()`.
    /// - Parameter timing: `.standard`, or no cap for the `following` launch state.
    @MainActor
    package func readerDependencies(timing: ReaderTiming = .standard) -> ReaderDependencies {
        ReaderDependencies(
            textReader: textReader,
            pointer: pointer,
            keyState: keyState,
            presenter: readerPresenter,
            notices: notices,
            preferences: preferences,
            permissions: permissions,
            sleeper: sleeper,
            timing: timing
        )
    }
}

import LargeTextCore
import LargeTextPlatform
import LargeTextTestSupport
import LargeTextUI
import Testing
@testable import LargeTextKit

@MainActor
@Suite struct AppEnvironmentTests {
    /// Constructing the live environment must not prompt, register or open anything (§3.1).
    @Test func liveEnvironmentIsConstructibleWithoutSideEffects() {
        let environment = AppEnvironment.live()
        #expect(environment.hotkeys is CarbonHotkeyRegistrar)
        #expect(environment.focus is AccessibilityFocusCapturer)
        #expect(environment.permissions is SystemPermissionsProvider)
        #expect(environment.overlay is OverlayWindowController)
        #expect(environment.notices is HUDNoticePresenter)
        #expect(environment.inserterOverride == nil)
        #expect(environment.coreDependencies().inserter is PasteboardTextInserter)
        #expect(environment.textReader is AccessibilityTextReader)
        #expect(environment.pointer is SystemPointerTracker)
        #expect(environment.keyState is SystemKeyStateReader)
        #expect(environment.readerPresenter is ReaderWindowController)
        #expect(environment.settingsPresenter is SettingsWindowController)
        #expect(environment.settingsPresenter.isVisible == false)
        // `SMAppService.mainApp` is only touched by `status` / `setEnabled`, never here.
        #expect(environment.loginItem is SMAppServiceLoginItem)
    }

    @Test func readerDependenciesAreAssembledFromTheEnvironment() {
        let preferences = InMemoryPreferencesStore()
        let notices = SpyNotices()
        let presenter = SpyReaderPresenter()
        let pointer = ScriptedPointer()
        let environment = AppEnvironment(
            hotkeys: SpyHotkeys(),
            focus: StubFocusCapturer(target: FocusTarget(application: nil)),
            permissions: FixedPermissions(.allGranted),
            pasteboard: FakePasteboard(),
            keystrokes: RecordingKeystrokes(),
            preferences: preferences,
            sleeper: InstantSleeper(),
            overlay: SpyOverlay(),
            notices: notices,
            pointer: pointer,
            readerPresenter: presenter
        )
        let timing = ReaderTiming(maxFollowDuration: nil)

        let dependencies = environment.readerDependencies(timing: timing)

        #expect(dependencies.presenter === presenter)
        #expect(dependencies.pointer === pointer)
        #expect(dependencies.notices === notices)
        #expect(dependencies.preferences === preferences)
        #expect(dependencies.textReader is StubTextReader)
        #expect(dependencies.timing == timing)
        #expect(environment.readerDependencies().timing == .standard)
    }

    @Test func readerServicesDefaultToCoreFakes() {
        let environment = AppEnvironment(
            hotkeys: SpyHotkeys(),
            focus: StubFocusCapturer(target: FocusTarget(application: nil)),
            permissions: FixedPermissions(.allGranted),
            pasteboard: FakePasteboard(),
            keystrokes: RecordingKeystrokes(),
            preferences: InMemoryPreferencesStore(),
            sleeper: InstantSleeper(),
            overlay: SpyOverlay(),
            notices: SpyNotices()
        )
        #expect(environment.textReader is StubTextReader)
        #expect(environment.pointer is ScriptedPointer)
        #expect(environment.keyState is FixedKeyState)
        #expect(environment.readerPresenter is LoggingReaderPresenter)
    }

    @Test func settingsDependenciesAreAssembledFromTheEnvironment() {
        let preferences = InMemoryPreferencesStore()
        let presenter = SpySettingsPresenter()
        let shortcuts = SpyShortcutBinding()
        let loginItem = SpyLoginItem()
        let environment = AppEnvironment(
            hotkeys: SpyHotkeys(),
            focus: StubFocusCapturer(target: FocusTarget(application: nil)),
            permissions: FixedPermissions(.allGranted),
            pasteboard: FakePasteboard(),
            keystrokes: RecordingKeystrokes(),
            preferences: preferences,
            sleeper: InstantSleeper(),
            overlay: SpyOverlay(),
            notices: SpyNotices(),
            settingsPresenter: presenter,
            loginItem: loginItem
        )
        let context = SettingsContext(scenarioName: "first-launch")

        let dependencies = environment.settingsDependencies(shortcuts: shortcuts, context: context, relaunch: {})

        #expect(dependencies.preferences === preferences)
        #expect(dependencies.presenter === presenter)
        #expect(dependencies.shortcuts === shortcuts)
        #expect(dependencies.context == context)
        #expect(dependencies.loginItem === loginItem)
    }

    @Test func settingsPresenterDefaultsToTheLoggingOne() {
        let environment = AppEnvironment(
            hotkeys: SpyHotkeys(),
            focus: StubFocusCapturer(target: FocusTarget(application: nil)),
            permissions: FixedPermissions(.allGranted),
            pasteboard: FakePasteboard(),
            keystrokes: RecordingKeystrokes(),
            preferences: InMemoryPreferencesStore(),
            sleeper: InstantSleeper(),
            overlay: SpyOverlay(),
            notices: SpyNotices()
        )
        #expect(environment.settingsPresenter is LoggingSettingsPresenter)
        #expect(environment.loginItem is InMemoryLoginItem)
    }
}

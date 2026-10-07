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
}

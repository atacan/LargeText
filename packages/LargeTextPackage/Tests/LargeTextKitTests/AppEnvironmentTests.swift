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

import LargeTextCore
import LargeTextPlatform
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
}

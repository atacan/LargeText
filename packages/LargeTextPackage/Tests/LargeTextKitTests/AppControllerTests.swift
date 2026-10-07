import Foundation
import LargeTextCore
import LargeTextTestSupport
import Testing
@testable import LargeTextKit

/// The editor/reader interplay (§4.8) and the shortcut registration (§4.10), through `startSessions()` with
/// spies: no status item, no real delays.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppControllerTests {
    let hotkeys = SpyHotkeys()
    let preferences = InMemoryPreferencesStore()
    let overlay = SpyOverlay()
    let notices = SpyNotices()
    let textReader = ControllableTextReader()
    let readerPresenter = SpyReaderPresenter()
    let sleeper = RecordingSleeper()

    init() {
        // Park the reader's key-state check and cap, so a following session stays open.
        sleeper.heldDurations = [ReaderDefaults.holdThreshold + .milliseconds(100), .seconds(30)]
    }

    func makeController() -> AppController {
        let environment = AppEnvironment(
            hotkeys: hotkeys,
            focus: StubFocusCapturer(target: FocusTarget(
                application: TargetApplication(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit"),
                elementKind: .multiLineText
            )),
            permissions: FixedPermissions(.allGranted),
            pasteboard: FakePasteboard(),
            keystrokes: RecordingKeystrokes(),
            preferences: preferences,
            sleeper: sleeper,
            overlay: overlay,
            notices: notices,
            inserterOverride: SpyInserter(),
            textReader: textReader,
            pointer: ScriptedPointer(),
            keyState: FixedKeyState(),
            readerPresenter: readerPresenter
        )
        let controller = AppController(environment: environment, launch: LaunchConfiguration())
        controller.startSessions()
        return controller
    }

    func pressEditor() {
        hotkeys.simulate(.pressed, at: 1, for: preferences.hotkey)
    }

    func pressReader(at time: TimeInterval = 10) {
        hotkeys.simulate(.pressed, at: time, for: preferences.readerHotkey)
    }

    /// Lets queued main-actor work run before asserting that something did *not* happen.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func until(_ condition: () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    // MARK: - Registration

    @Test func bothShortcutsAreRegistered() {
        let controller = makeController()

        #expect(hotkeys.registrations.map(\.combo) == [preferences.hotkey, preferences.readerHotkey])
        #expect(controller.hotkeyUnavailable.isEmpty)
        #expect(notices.shown.isEmpty)
    }

    @Test func conflictingReaderComboIsNotRegisteredAndIsListedAsUnavailable() {
        preferences.readerHotkey = preferences.hotkey

        let controller = makeController()

        #expect(hotkeys.registrations.map(\.combo) == [preferences.hotkey])
        #expect(controller.hotkeyUnavailable == [preferences.hotkey])
        #expect(notices.shown == [.hotkeyUnavailable(preferences.hotkey)])
    }

    @Test func failedRegistrationsAreAllListed() {
        hotkeys.failsRegistration = true

        let controller = makeController()

        #expect(controller.hotkeyUnavailable == [preferences.hotkey, preferences.readerHotkey])
        #expect(notices.shown == [.hotkeyUnavailable(preferences.hotkey), .hotkeyUnavailable(preferences.readerHotkey)])
    }

    // MARK: - Reader shortcut

    @Test func readerShortcutStartsTheReaderWhileTheEditorIsIdle() async {
        let controller = makeController()

        pressReader()
        await textReader.waitForCalls(1)

        #expect(controller.reader?.phase == .following)
    }

    @Test func readerShortcutIsIgnoredWhileTheEditorIsOpen() async {
        let controller = makeController()
        pressEditor()
        await until { overlay.presentCount == 1 }
        #expect(controller.coordinator?.isIdle == false)

        pressReader()
        hotkeys.simulate(.released, at: 10.1, for: preferences.readerHotkey)
        await settle()

        #expect(controller.reader?.isIdle == true)
        #expect(textReader.calls.isEmpty)
        #expect(readerPresenter.presented.isEmpty)
    }

    // MARK: - Editor shortcut

    @Test func editorShortcutClosesTheReaderBeforeOpening() async {
        let controller = makeController()
        pressReader()
        await textReader.waitForCalls(1)
        textReader.complete(readIndex: 0, with: .text(ReadText(text: "A", granularity: .sentence, source: .label)))
        await until { readerPresenter.presented.count == 1 }

        pressEditor()
        await until { overlay.presentCount == 1 }

        #expect(readerPresenter.dismissCount == 1)
        #expect(controller.reader?.isIdle == true)
    }

    @Test func twoEditorPressesDuringTheReaderFadeOpenTheEditorExactlyOnce() async {
        let controller = makeController()
        pressReader()
        await textReader.waitForCalls(1)
        textReader.complete(readIndex: 0, with: .text(ReadText(text: "A", granularity: .sentence, source: .label)))
        await until { readerPresenter.presented.count == 1 }
        readerPresenter.holdDismiss = true

        pressEditor()
        await readerPresenter.waitUntilDismissIsHeld()
        pressEditor()
        readerPresenter.completeDismiss()
        await until { overlay.presentCount == 1 }
        await settle()

        #expect(overlay.presentCount == 1)
        // A second toggle would have committed the editor straight away.
        #expect(overlay.dismissCount == 0)
        #expect(controller.coordinator?.isIdle == false)
        #expect(readerPresenter.dismissCount == 1)
    }

    @Test func secondPressBeforeTheFirstTaskStartsIsIgnored() async {
        let controller = makeController()

        // Back to back: the first press's task hasn't run yet, so the reader can't be closing yet either.
        pressEditor()
        pressEditor()
        await until { overlay.presentCount == 1 }
        await settle()

        #expect(overlay.presentCount == 1)
        #expect(overlay.dismissCount == 0)
        #expect(controller.coordinator?.isIdle == false)
    }

    @Test func editorShortcutStillTogglesOnceTheFirstOpenHasFinished() async {
        let controller = makeController()
        pressEditor()
        await until { overlay.presentCount == 1 }
        await settle()

        pressEditor()
        await until { controller.coordinator?.isIdle == true }

        #expect(overlay.dismissCount == 1)
    }
}

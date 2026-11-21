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
    let permissions = SpyPermissions(.allGranted)
    let pasteboard = FakePasteboard()
    let settingsPresenter = SpySettingsPresenter()
    let loginItem = SpyLoginItem()
    let updater = InMemoryUpdater(isAvailable: true)

    init() {
        // Park the reader's key-state check and cap, so a following session stays open, and the Settings
        // permission refresh, which would otherwise spin on this sleeper while the spy window is visible.
        sleeper.heldDurations = [ReaderDefaults.holdThreshold + .milliseconds(100), .seconds(30), .seconds(1)]
    }

    func makeController(launch: LaunchConfiguration = LaunchConfiguration()) -> AppController {
        let environment = AppEnvironment(
            hotkeys: hotkeys,
            focus: StubFocusCapturer(target: FocusTarget(
                application: TargetApplication(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit"),
                elementKind: .multiLineText
            )),
            permissions: permissions,
            pasteboard: pasteboard,
            keystrokes: RecordingKeystrokes(),
            preferences: preferences,
            sleeper: sleeper,
            overlay: overlay,
            notices: notices,
            inserterOverride: SpyInserter(),
            textReader: textReader,
            pointer: ScriptedPointer(),
            keyState: FixedKeyState(),
            readerPresenter: readerPresenter,
            settingsPresenter: settingsPresenter,
            loginItem: loginItem,
            updater: updater
        )
        let controller = AppController(environment: environment, launch: launch)
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

    /// A tap on the reader shortcut, answered with "A": the pinned card.
    func pinReader() async {
        pressReader()
        hotkeys.simulate(.released, at: 10.1, for: preferences.readerHotkey)
        await textReader.waitForCalls(1)
        textReader.complete(readIndex: 0, with: .text(ReadText(text: "A", granularity: .sentence, source: .label)))
        await until { readerPresenter.presented.count == 1 }
    }

    // MARK: - Registration

    @Test func bothShortcutsAreRegistered() {
        let controller = makeController()

        #expect(hotkeys.registrations.map(\.combo) == [.default, .readerDefault])
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

        #expect(controller.hotkeyUnavailable == [.default, .readerDefault])
        #expect(notices.shown == [.hotkeyUnavailable(.default), .hotkeyUnavailable(.readerDefault)])
    }

    @Test func refusedReaderComboIsListedAndTheEditorStillWorks() async {
        hotkeys.refusing = [.readerDefault]

        let controller = makeController()
        pressEditor()
        await until { overlay.presentCount == 1 }

        #expect(hotkeys.live.map(\.combo) == [.default])
        #expect(controller.hotkeyUnavailable == [.readerDefault])
        #expect(notices.shown == [.hotkeyUnavailable(.readerDefault)])
    }

    @Test func readerTurnedOffIsNotRegisteredAndNothingIsReported() {
        preferences.readerHotkey = nil

        let controller = makeController()

        #expect(hotkeys.registrations.map(\.combo) == [.default])
        #expect(controller.hotkeyUnavailable.isEmpty)
        #expect(notices.shown.isEmpty)
    }

    @Test func rebindingMovesTheEditorToTheNewCombo() async throws {
        let controller = makeController()
        let newCombo = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])
        let shortcuts = try #require(controller.shortcuts)

        shortcuts.apply(editor: newCombo, reader: .readerDefault)
        hotkeys.simulate(.pressed, at: 1, for: .default)
        await settle()
        #expect(overlay.presentCount == 0)

        hotkeys.simulate(.pressed, at: 2, for: newCombo)
        await until { overlay.presentCount == 1 }
        #expect(hotkeys.live.map(\.combo) == [newCombo, .readerDefault])
    }

    @Test func stopUnregistersBothShortcuts() {
        let controller = makeController()

        controller.stop()

        #expect(hotkeys.live.isEmpty)
        #expect(controller.shortcuts == nil)
        #expect(controller.hotkeyUnavailable.isEmpty)
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

    // MARK: - Settings (Settings plan §3.2, §3.5)

    @Test func openSettingsShowsAtOnceWhenNothingIsOpen() {
        let controller = makeController()

        controller.openSettings()

        #expect(settingsPresenter.shown.count == 1)
        #expect(controller.settings?.isOpen == true)
        #expect(settingsPresenter.lastState?.context == .standard)
    }

    @Test func openSettingsClosesThePinnedReaderFirst() async {
        let controller = makeController()
        await pinReader()
        readerPresenter.holdDismiss = true

        controller.openSettings()
        await readerPresenter.waitUntilDismissIsHeld()
        controller.openSettings()
        await settle()
        #expect(settingsPresenter.shown.isEmpty)

        readerPresenter.completeDismiss()
        await until { settingsPresenter.shown.count == 1 }
        await settle()

        #expect(settingsPresenter.shown.count == 1)
        #expect(readerPresenter.dismissCount == 1)
        #expect(controller.reader?.isIdle == true)
    }

    @Test func openSettingsClosesTheEditorAndKeepsItsTextOnTheClipboard() async {
        let controller = makeController()
        pressEditor()
        await until { overlay.presentCount == 1 }
        overlay.textToReturn = "half-typed"

        controller.openSettings()
        await until { settingsPresenter.shown.count == 1 }

        #expect(overlay.dismissCount == 1)
        #expect(controller.coordinator?.isIdle == true)
        #expect(pasteboard.string == "half-typed")
        #expect(notices.shown == [.copiedToClipboard(.settingsOpened)])
    }

    @Test func commandCommaInTheEditorOpensSettings() async throws {
        let controller = makeController()
        pressEditor()
        await until { overlay.presentCount == 1 }
        let id = try #require(overlay.lastSessionID)

        overlay.lastIntents?(OverlayIntent(sessionID: id, kind: .openSettings))
        await until { settingsPresenter.shown.count == 1 }

        #expect(overlay.dismissCount == 1)
        #expect(controller.coordinator?.isIdle == true)
        #expect(pasteboard.writes.isEmpty)
    }

    @Test func commandCommaOnThePinnedReaderOpensSettings() async throws {
        let controller = makeController()
        await pinReader()
        let id = try #require(readerPresenter.lastSessionID)

        readerPresenter.lastIntents?(ReaderIntent(sessionID: id, kind: .openSettings))
        await until { settingsPresenter.shown.count == 1 }

        #expect(readerPresenter.dismissCount == 1)
        #expect(controller.reader?.isIdle == true)
    }

    @Test func settingsRebindsThroughTheAppsShortcuts() throws {
        let controller = makeController()
        controller.openSettings()
        let newCombo = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])

        settingsPresenter.send(.record(.editor, newCombo))

        #expect(preferences.hotkey == newCombo)
        #expect(hotkeys.live.map(\.combo) == [newCombo, .readerDefault])
        #expect(try #require(controller.shortcuts).editorCombo == newCombo)
    }

    /// Settings plan §3.7: the window's toggle reaches the environment's login item, and its status comes back.
    @Test func launchAtLoginTogglesTheEnvironmentsLoginItem() {
        loginItem.statusWhenEnabled = .requiresApproval
        let controller = makeController()
        controller.openSettings()
        #expect(settingsPresenter.lastState?.loginItem == .notRegistered)

        settingsPresenter.send(.setLaunchAtLogin(true))
        #expect(loginItem.setEnabledCalls == [true])
        #expect(settingsPresenter.lastState?.loginItem == .requiresApproval)

        settingsPresenter.send(.openLoginItemsSettings)
        #expect(loginItem.openSystemSettingsCount == 1)

        settingsPresenter.send(.setLaunchAtLogin(false))
        #expect(loginItem.setEnabledCalls == [true, false])
        #expect(settingsPresenter.lastState?.loginItem == .notRegistered)
        settingsPresenter.close()
    }

    /// The Updates section reaches the environment's updater.
    @Test func updatesInSettingsReachTheEnvironmentsUpdater() {
        let controller = makeController()
        controller.openSettings()
        #expect(settingsPresenter.lastState?.automaticallyChecksForUpdates == true)

        settingsPresenter.send(.setAutomaticallyChecksForUpdates(false))
        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(settingsPresenter.lastState?.automaticallyChecksForUpdates == false)

        settingsPresenter.send(.checkForUpdates)
        #expect(updater.checkCount == 1)
        settingsPresenter.close()
    }

    /// The recorder's whole path (Settings plan §3.8): recording suspends both shortcuts, so pressing the old
    /// combo opens nothing; the recorded combo is applied, saved and shown; then it opens the editor and the
    /// old one doesn't.
    @Test func recordingAComboSuspendsThenRebindsTheEditor() async throws {
        let controller = makeController()
        controller.openSettings()
        let newCombo = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])

        settingsPresenter.send(.beginRecording(.editor))
        #expect(hotkeys.live.isEmpty)
        #expect(settingsPresenter.lastState?.editorShortcut.isRecording == true)
        hotkeys.simulate(.pressed, at: 1, for: .default)
        await settle()
        #expect(overlay.presentCount == 0)

        settingsPresenter.send(.record(.editor, newCombo))
        #expect(preferences.hotkey == newCombo)
        #expect(hotkeys.live.map(\.combo) == [newCombo, .readerDefault])
        #expect(settingsPresenter.lastState?.editorShortcut == SettingsState.Shortcut(combo: newCombo, isRegistered: true))
        #expect(controller.hotkeyUnavailable.isEmpty)

        hotkeys.simulate(.pressed, at: 2, for: .default)
        await settle()
        #expect(overlay.presentCount == 0)
        hotkeys.simulate(.pressed, at: 3, for: newCombo)
        await until { overlay.presentCount == 1 }
        settingsPresenter.close()
    }

    /// A combo another app holds: the saved shortcuts come back, nothing is saved, the row says why.
    @Test func recordingATakenComboRestoresTheSavedShortcuts() async throws {
        let taken = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])
        hotkeys.refusing = [taken]
        let controller = makeController()
        controller.openSettings()

        settingsPresenter.send(.beginRecording(.editor))
        settingsPresenter.send(.record(.editor, taken))

        #expect(preferences.hotkey == .default)
        #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])
        #expect(settingsPresenter.lastState?.editorShortcut.problem == .unavailable)
        #expect(controller.hotkeyUnavailable.isEmpty)
        pressEditor()
        await until { overlay.presentCount == 1 }
        settingsPresenter.close()
    }

    /// ⎋ in the recorder and closing the window while recording both bring the saved shortcuts back.
    @Test func cancellingOrClosingWhileRecordingRestoresBothShortcuts() {
        let controller = makeController()
        controller.openSettings()

        settingsPresenter.send(.beginRecording(.reader))
        #expect(hotkeys.live.isEmpty)
        settingsPresenter.send(.cancelRecording)
        #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])

        settingsPresenter.send(.beginRecording(.editor))
        settingsPresenter.close()
        #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])
        #expect(preferences.hotkey == .default)
    }

    // MARK: - First launch (Settings plan §3.6)

    @Test func firstLaunchWithAccessMissingOpensSettingsOnceThenPrompts() {
        permissions.current = .allDenied
        #expect(!preferences.hasCompletedFirstLaunch)

        makeController().requestAccessIfNeeded()

        #expect(settingsPresenter.shown.count == 1)
        #expect(permissions.calls == [.requestAccessibility])
        #expect(preferences.hasCompletedFirstLaunch)

        // The second launch only asks.
        makeController().requestAccessIfNeeded()

        #expect(settingsPresenter.shown.count == 1)
        #expect(permissions.calls == [.requestAccessibility, .requestAccessibility])
    }

    @Test func firstLaunchWithAccessGrantedOnlyMarksItDone() {
        makeController().requestAccessIfNeeded()

        #expect(settingsPresenter.shown.isEmpty)
        #expect(permissions.calls.isEmpty)
        #expect(preferences.hasCompletedFirstLaunch)
    }

    @Test func presentOnLaunchDefersSettingsAndThePrompt() {
        permissions.current = .allDenied

        makeController(launch: LaunchConfiguration(presentOnLaunch: true)).requestAccessIfNeeded()

        #expect(settingsPresenter.shown.isEmpty)
        #expect(permissions.calls.isEmpty)
    }
}

import Foundation
import LargeTextCore
import LargeTextPlatform
import LargeTextTestSupport
import Testing
import LargeTextUI
@testable import LargeTextKit

/// Behavioural assembly tests: scenario mutation → `coreDependencies()` → a real coordinator (§4).
@MainActor
@Suite struct ScenarioTests {
    let log = EventLog()
    let hotkeys = SpyHotkeys()
    let focus = StubFocusCapturer(target: FocusTarget(
        application: TargetApplication(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit"),
        elementKind: .multiLineText
    ))
    let permissions = FixedPermissions(.allGranted)
    let pasteboard: FakePasteboard
    let keystrokes: RecordingKeystrokes
    let preferences = InMemoryPreferencesStore()
    let overlay: SpyOverlay
    let notices: SpyNotices

    init() {
        pasteboard = FakePasteboard(items: [.text("previous")], log: log)
        keystrokes = RecordingKeystrokes(log: log)
        overlay = SpyOverlay(log: log)
        notices = SpyNotices(log: log)
    }

    func environment() -> AppEnvironment {
        AppEnvironment(
            hotkeys: hotkeys,
            focus: focus,
            permissions: permissions,
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            preferences: preferences,
            sleeper: InstantSleeper(),
            overlay: overlay,
            notices: notices
        )
    }

    /// Opens a session, then commits `text` with the presented session id.
    func openAndCommit(_ environment: AppEnvironment, text: String, mode: CommitMode = .insert) async throws -> EditingSessionCoordinator {
        let coordinator = EditingSessionCoordinator(dependencies: environment.coreDependencies())
        await coordinator.toggle()
        let id = try #require(overlay.lastSessionID)
        overlay.textToReturn = text
        await coordinator.handle(OverlayIntent(sessionID: id, kind: .commit(mode)))
        return coordinator
    }

    @Test func rawValuesRoundTrip() {
        #expect(Scenario.allCases.map(\.rawValue) == [
            "overlay-prefilled", "no-editable-target", "permission-missing", "logging-insertion",
            "reader-stub", "reader-no-accessibility", "reader-probe", "settings-needs-relaunch", "first-launch",
            "settings-hotkey-taken",
        ])
        for scenario in Scenario.allCases {
            #expect(Scenario(rawValue: scenario.rawValue) == scenario)
        }
    }

    @Test(arguments: Scenario.allCases)
    func everyScenarioSwapsInMemoryPreferences(_ scenario: Scenario) {
        var environment = environment()
        scenario.apply(to: &environment)
        #expect(environment.preferences is InMemoryPreferencesStore)
        #expect(environment.preferences !== preferences)
        // settings-hotkey-taken wraps the live registrar instead of replacing it.
        let registrar = (environment.hotkeys as? RefusingHotkeyRegistrar)?.wrapped ?? environment.hotkeys
        #expect(registrar === hotkeys)
        #expect((environment.hotkeys is RefusingHotkeyRegistrar) == (scenario == .settingsHotkeyTaken))
        #expect(environment.overlay === overlay)
        #expect(environment.notices === notices)
        #expect(environment.pasteboard === pasteboard)
    }

    @Test func permissionMissingCopiesNonTransientlyAndShowsNotice() async throws {
        var environment = environment()
        Scenario.permissionMissing.apply(to: &environment)
        #expect(environment.inserterOverride == nil)
        #expect(environment.focus === focus)

        let coordinator = try await openAndCommit(environment, text: "hello world")

        #expect(overlay.lastChrome?.hints.willCopyToClipboard == true)
        #expect(notices.shown == [.copiedToClipboard(.permissionMissing)])
        #expect(pasteboard.writes.map(\.string) == ["hello world"])
        #expect(pasteboard.writes.map(\.transient) == [false])
        #expect(pasteboard.string == "hello world")
        #expect(pasteboard.isTransient == false)
        #expect(keystrokes.sent.isEmpty)
        #expect(log.events == [
            .present(initialText: ""),
            .dismiss,
            .write("hello world", transient: false),
            .notice(.copiedToClipboard(.permissionMissing)),
        ])
        #expect(coordinator.phase == .idle)
    }

    @Test func noEditableTargetCopiesAndShowsNotice() async throws {
        var environment = environment()
        Scenario.noEditableTarget.apply(to: &environment)
        #expect(environment.inserterOverride == nil)
        #expect(environment.permissions === permissions)

        _ = try await openAndCommit(environment, text: "copied")

        #expect(overlay.lastChrome?.targetName == "Safari")
        #expect(overlay.lastChrome?.hints.willCopyToClipboard == true)
        #expect(notices.shown == [.copiedToClipboard(.noEditableTarget)])
        #expect(pasteboard.writes.map(\.transient) == [false])
        #expect(pasteboard.string == "copied")
        #expect(keystrokes.sent.isEmpty)
    }

    @Test func overlayPrefilledUsesStubTargetAndLoggingInserter() async throws {
        var environment = environment()
        Scenario.overlayPrefilled.apply(to: &environment)
        #expect(environment.inserterOverride is LoggingTextInserter)
        #expect(environment.coreDependencies().inserter is LoggingTextInserter)

        _ = try await openAndCommit(environment, text: "https://www.apple.com/mac", mode: .insertAndSubmit)

        #expect(overlay.lastInitialText == "https://www.apple.com")
        #expect(overlay.lastChrome?.targetName == "Safari")
        #expect(overlay.lastChrome?.targetBundleIdentifier == "com.apple.Safari")
        #expect(overlay.lastChrome?.hints == TargetHints(willCopyToClipboard: false))
        // The override is respected: nothing reaches the pasteboard or the keyboard.
        #expect(pasteboard.writes.isEmpty)
        #expect(pasteboard.snapshotCount == 0)
        #expect(keystrokes.sent.isEmpty)
        #expect(notices.shown.isEmpty)
    }

    @Test func loggingInsertionKeepsEverythingElseLive() async throws {
        var environment = environment()
        Scenario.loggingInsertion.apply(to: &environment)
        #expect(environment.inserterOverride is LoggingTextInserter)
        #expect(environment.focus === focus)
        #expect(environment.permissions === permissions)

        _ = try await openAndCommit(environment, text: "typed")

        #expect(overlay.lastChrome?.targetName == "TextEdit")
        #expect(pasteboard.writes.isEmpty)
        #expect(keystrokes.sent.isEmpty)
    }

    @Test func withoutOverrideTheRealInserterPastes() async throws {
        let environment = environment()
        #expect(environment.coreDependencies().inserter is PasteboardTextInserter)

        _ = try await openAndCommit(environment, text: "pasted")

        #expect(pasteboard.writes.map(\.string) == ["pasted"])
        #expect(pasteboard.writes.map(\.transient) == [true])
        #expect(keystrokes.sent == [.paste])
        #expect(notices.shown.isEmpty)
    }

    // MARK: - Reader

    func sample(x: CGFloat) -> PointerSample {
        PointerSample(appKit: CGPoint(x: x, y: 500), global: CGPoint(x: x, y: 400))
    }

    @Test func readerStubAnswersByPointerX() async throws {
        var environment = environment()
        Scenario.readerStub.apply(to: &environment)
        let reader = try #require(environment.textReader as? StubTextReader)

        var results: [ReadResult] = []
        for x in [10, 450, 900, 1_300, 5_000] as [CGFloat] {
            results.append(await reader.read(at: sample(x: x), granularity: .sentence, policy: .standard))
        }

        #expect(results == [Scenario.stubLabel, Scenario.stubParagraph, .nothing, .hidden, .hidden])
    }

    @Test func readerStubNeedsNoAccessibilityAndNeverPastes() {
        var environment = environment()
        Scenario.readerStub.apply(to: &environment)

        #expect(environment.permissions.current == .allGranted)
        #expect(environment.permissions !== permissions)
        #expect(environment.inserterOverride is LoggingTextInserter)
        #expect(environment.readerDependencies().textReader is StubTextReader)
    }

    @Test func readerStubShowsACardThroughTheCoordinator() async {
        var environment = environment()
        let presenter = SpyReaderPresenter()
        environment.readerPresenter = presenter
        environment.pointer = ScriptedPointer(current: sample(x: 10))
        Scenario.readerStub.apply(to: &environment)
        let reader = ReadingSessionCoordinator(dependencies: environment.readerDependencies())

        reader.hotkey(HotkeyEvent(phase: .pressed, at: 10))
        reader.hotkey(HotkeyEvent(phase: .released, at: 10))
        while presenter.presented.isEmpty { await Task.yield() }

        #expect(presenter.presented.map(\.content) == [.text("Open Large Editor", scrollToUTF16: nil)])
        #expect(presenter.presented.map(\.chrome.mode) == [.pinned])
    }

    @Test func readerNoAccessibilityShowsTheNoticeInsteadOfACard() {
        var environment = environment()
        let presenter = SpyReaderPresenter()
        environment.readerPresenter = presenter
        Scenario.readerNoAccessibility.apply(to: &environment)
        let reader = ReadingSessionCoordinator(dependencies: environment.readerDependencies())

        reader.hotkey(HotkeyEvent(phase: .pressed, at: 10))

        #expect(environment.permissions.current == .allDenied)
        #expect(reader.isIdle)
        #expect(notices.shown == [.readerNeedsAccessibility])
        #expect(presenter.presented.isEmpty)
    }

    @Test func readerProbeKeepsTheReaderServices() {
        var environment = environment()
        let reader = environment.textReader
        Scenario.readerProbe.apply(to: &environment)

        #expect(environment.permissions === permissions)
        #expect(environment.inserterOverride == nil)
        #expect(type(of: environment.textReader) == type(of: reader))
    }

    // MARK: - Settings

    /// The live login item would register the real bundle; every scenario swaps in one kept in memory.
    @Test(arguments: Scenario.allCases)
    func everyScenarioSwapsInAnInMemoryLoginItem(_ scenario: Scenario) throws {
        var environment = environment()
        environment.loginItem = SMAppServiceLoginItem()
        scenario.apply(to: &environment)
        let loginItem = try #require(environment.loginItem as? InMemoryLoginItem)
        #expect(loginItem.status == .notRegistered)

        let settings = SettingsCoordinator(dependencies: environment.settingsDependencies(
            shortcuts: SpyShortcutBinding(),
            context: SettingsContext(scenarioName: scenario.rawValue),
            relaunch: {}
        ))
        settings.handle(.setLaunchAtLogin(true))
        #expect(loginItem.status == .enabled)
    }

    /// The live updater would check the real feed and could replace the app; every scenario swaps in one that
    /// does nothing, which also hides updates in the menus and Settings.
    @Test(arguments: Scenario.allCases)
    func everyScenarioSwapsInAnInMemoryUpdater(_ scenario: Scenario) throws {
        var environment = environment()
        environment.updater = InMemoryUpdater(isAvailable: true)
        scenario.apply(to: &environment)
        let updater = try #require(environment.updater as? InMemoryUpdater)
        #expect(updater.isAvailable == false)
    }

    /// Only `first-launch` opens Settings by itself (Settings plan §3.6).
    @Test(arguments: Scenario.allCases)
    func onlyFirstLaunchIsAFirstLaunch(_ scenario: Scenario) {
        var environment = environment()
        scenario.apply(to: &environment)
        #expect(environment.preferences.hasCompletedFirstLaunch == (scenario != .firstLaunch))
    }

    @Test func settingsNeedsRelaunchGrantsAccessibilityButNotEventPosting() {
        var environment = environment()
        Scenario.settingsNeedsRelaunch.apply(to: &environment)
        #expect(environment.permissions.current.setup == .needsRelaunch)
        #expect(environment.focus === focus)
        #expect(environment.inserterOverride == nil)
    }

    @Test func firstLaunchDeniesAccess() {
        var environment = environment()
        Scenario.firstLaunch.apply(to: &environment)
        #expect(environment.permissions.current == .allDenied)
        #expect(environment.permissions is FixedPermissions)
    }

    @Test func settingsHotkeyTakenRefusesItsCombosWhenRecordedAndKeepsTheSavedOnes() throws {
        var environment = environment()
        Scenario.settingsHotkeyTaken.apply(to: &environment)
        let registrar = try #require(environment.hotkeys as? RefusingHotkeyRegistrar)
        #expect(registrar.wrapped === hotkeys)
        let e = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])    // ⌃⌥⌘E
        let y = KeyCombo(keyCode: 0x10, modifiers: [.control, .option, .command])    // ⌃⌥⌘Y
        #expect(registrar.refusing == [e, y])
        #expect(environment.permissions === permissions)
        #expect(environment.focus === focus)
        #expect(environment.inserterOverride == nil)

        let preferences = environment.preferences
        let bindings = HotkeyBindings(hotkeys: environment.hotkeys, onEditor: {}, onReader: { _ in })
        // The defaults aren't taken, so the launch-time registration succeeds.
        #expect(bindings.apply(editor: preferences.hotkey, reader: preferences.readerHotkey).isEmpty)
        // The default presenter is never visible, so the permission refresh ends after one wait.
        let settings = SettingsCoordinator(dependencies: environment.settingsDependencies(
            shortcuts: bindings,
            context: SettingsContext(scenarioName: Scenario.settingsHotkeyTaken.rawValue),
            relaunch: {}
        ))
        settings.show()

        for (slot, taken) in [(ShortcutSlot.editor, e), (.reader, y), (.editor, y)] {
            settings.handle(.beginRecording(slot))
            #expect(hotkeys.live.isEmpty)
            settings.handle(.record(slot, taken))

            #expect(settings.state[slot].problem == .unavailable)
            #expect(!settings.state[slot].isRecording)
            #expect(preferences.hotkey == .default)
            #expect(preferences.readerHotkey == .readerDefault)
            #expect(hotkeys.live.map(\.combo) == [.default, .readerDefault])
        }
        settings.handle(.closed)
    }

    /// The live window would save its frame in the real defaults; a scenario swaps in one that doesn't.
    @Test func scenariosReplaceTheLiveSettingsWindowAndKeepASpy() {
        var live = environment()
        live.settingsPresenter = SettingsWindowController()
        let original = live.settingsPresenter
        Scenario.firstLaunch.apply(to: &live)
        #expect(live.settingsPresenter is SettingsWindowController)
        #expect(live.settingsPresenter !== original)

        let spy = SpySettingsPresenter()
        var spied = environment()
        spied.settingsPresenter = spy
        Scenario.firstLaunch.apply(to: &spied)
        #expect(spied.settingsPresenter === spy)
    }
}

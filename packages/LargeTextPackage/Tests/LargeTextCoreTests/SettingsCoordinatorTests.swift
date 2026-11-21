import Foundation
import Testing
import LargeTextCore
import LargeTextTestSupport

/// Settings plan §3.8 and §5. The permission refresh is driven by `RecordingSleeper`: no real delays.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SettingsCoordinatorTests {
    static let interval = Duration.seconds(1)
    /// ⌃⌥⌘E and ⌃⌥⌘Y: valid, unused combos.
    static let comboE = KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])
    static let comboY = KeyCombo(keyCode: 0x10, modifiers: [.control, .option, .command])

    let preferences = InMemoryPreferencesStore()
    let permissions = SpyPermissions(.allGranted)
    let shortcuts = SpyShortcutBinding()
    let presenter = SpySettingsPresenter()
    let loginItem = SpyLoginItem()
    let sleeper: RecordingSleeper
    let relaunches = Counter()
    /// Keeps every coordinator alive for the whole test, as `AppController` does: the presenter's intents and
    /// the refresh only hold it weakly.
    let held = Held()

    final class Counter {
        var count = 0
    }

    final class Held {
        var coordinators: [SettingsCoordinator] = []
    }

    init() {
        sleeper = RecordingSleeper()
        sleeper.heldDurations = [Self.interval]
    }

    func makeCoordinator(
        context: SettingsContext = .standard,
        loginItem: (any LoginItemControlling)? = nil,
        updater: (any UpdateChecking)? = nil
    ) -> SettingsCoordinator {
        let relaunches = relaunches
        return keep(SettingsCoordinator(dependencies: SettingsDependencies(
            preferences: preferences,
            permissions: permissions,
            shortcuts: shortcuts,
            presenter: presenter,
            sleeper: sleeper,
            loginItem: loginItem,
            updater: updater,
            context: context,
            relaunch: { relaunches.count += 1 }
        )))
    }

    func keep(_ coordinator: SettingsCoordinator) -> SettingsCoordinator {
        held.coordinators.append(coordinator)
        return coordinator
    }

    /// A shown coordinator, as after "Settings…".
    func shown(
        context: SettingsContext = .standard,
        loginItem: (any LoginItemControlling)? = nil,
        updater: (any UpdateChecking)? = nil
    ) -> SettingsCoordinator {
        let coordinator = makeCoordinator(context: context, loginItem: loginItem, updater: updater)
        coordinator.show()
        return coordinator
    }

    func until(_ condition: () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    /// Lets one parked refresh sleep return and holds the next one. Returns once that next sleep has started,
    /// so the refresh in between has run.
    func tick() async {
        await until { sleeper.isParked(Self.interval) }
        let before = sleeper.durations.count
        release()
        await until { sleeper.durations.count > before }
    }

    /// Lets the parked refresh sleep return; later sleeps park again.
    func release() {
        sleeper.release(Self.interval)
        sleeper.heldDurations.insert(Self.interval)
    }

    // MARK: - Showing

    @Test func showingRendersTheStore() {
        preferences.hotkey = Self.comboE
        preferences.readerHotkey = nil
        preferences.fontSize = FontSize(points: 96)
        preferences.readerFontSize = FontSize(points: 48)
        preferences.readerHoldThreshold = .milliseconds(450)
        preferences.followingUnit = .line
        preferences.pinnedUnit = .sentence
        preferences.clipboardRestore = .none
        permissions.current = Permissions(accessibility: .granted, eventPosting: .denied)

        _ = shown()

        #expect(presenter.shown == [SettingsState(
            editorShortcut: .init(combo: Self.comboE, isRegistered: true),
            readerShortcut: .init(combo: nil, isRegistered: false),
            editorFontSize: FontSize(points: 96),
            readerFontSize: FontSize(points: 48),
            holdThreshold: .milliseconds(450),
            followingUnit: .line,
            pinnedUnit: .sentence,
            restoresClipboard: false,
            permission: .needsRelaunch,
            loginItem: nil,
            context: .standard
        )])
        #expect(presenter.lastState?.isReaderOn == false)
        #expect(presenter.isVisible)
        #expect(shortcuts.calls.isEmpty)
    }

    @Test func sizesAreShownClampedAndTheThresholdAsStored() {
        preferences.fontSize = FontSize(points: 500)
        preferences.readerFontSize = FontSize(points: 2)
        preferences.readerHoldThreshold = .seconds(2)

        let state = shown().state

        #expect(state.editorFontSize == FontSize(points: FontSizePolicy.range.upperBound))
        #expect(state.readerFontSize == FontSize(points: FontSizePolicy.range.lowerBound))
        #expect(state.holdThreshold == .seconds(2))
    }

    @Test func aShortcutTheLaunchCouldNotRegisterIsShownUnregistered() {
        shortcuts.refusing = [.readerDefault]
        shortcuts.apply(editor: .default, reader: .readerDefault)

        let state = shown().state

        #expect(state.editorShortcut.isRegistered)
        #expect(state.readerShortcut.isRegistered == false)
    }

    @Test func equalCombosShowOnlyTheReaderUnregistered() {
        preferences.readerHotkey = .default
        shortcuts.apply(editor: .default, reader: .default)

        let state = shown().state

        #expect(state.editorShortcut.isRegistered)
        #expect(state.readerShortcut.isRegistered == false)
    }

    @Test func showingAgainBringsTheWindowBackWithoutASecondRefresh() async {
        let coordinator = shown()
        coordinator.show()

        #expect(presenter.shown.count == 2)
        await until { sleeper.isParked(Self.interval) }
        #expect(sleeper.durations == [Self.interval])
    }

    @Test func becomingKeyReReadsTheStore() {
        let coordinator = shown()
        preferences.fontSize = FontSize(points: 120)    // ⌘± in the editor

        presenter.send(.becameKey)

        #expect(presenter.lastState?.editorFontSize == FontSize(points: 120))
        #expect(coordinator.state.editorFontSize == FontSize(points: 120))
    }

    // MARK: - Recording

    @Test func beginRecordingSuspendsBothShortcuts() {
        _ = shown()

        presenter.send(.beginRecording(.editor))

        #expect(shortcuts.calls == [.suspend])
        #expect(presenter.lastState?.editorShortcut.isRecording == true)
        #expect(presenter.lastState?.readerShortcut.isRecording == false)
        // Suspension isn't a registration failure.
        #expect(presenter.lastState?.editorShortcut.isRegistered == true)
    }

    @Test func switchingRecordersSuspendsOnce() {
        _ = shown()

        presenter.send(.beginRecording(.editor))
        presenter.send(.beginRecording(.reader))

        #expect(shortcuts.calls == [.suspend])
        #expect(presenter.lastState?.editorShortcut.isRecording == false)
        #expect(presenter.lastState?.readerShortcut.isRecording == true)
    }

    @Test(arguments: [SettingsIntent.cancelRecording, .resignedKey, .closed])
    func endingARecordingAppliesTheSavedCombos(_ intent: SettingsIntent) {
        preferences.hotkey = Self.comboE
        let coordinator = shown()
        presenter.send(.beginRecording(.reader))

        presenter.send(intent)

        #expect(shortcuts.calls == [.suspend, .apply(editor: Self.comboE, reader: .readerDefault)])
        #expect(coordinator.state.readerShortcut.isRecording == false)
    }

    @Test(arguments: [SettingsIntent.cancelRecording, .resignedKey, .closed])
    func endingWithoutARecordingAppliesNothing(_ intent: SettingsIntent) {
        _ = shown()

        presenter.send(intent)

        #expect(shortcuts.calls.isEmpty)
    }

    @Test func aValidRecordIsAppliedThenSaved() {
        _ = shown()
        presenter.send(.beginRecording(.editor))

        presenter.send(.record(.editor, Self.comboE))

        #expect(shortcuts.calls == [.suspend, .apply(editor: Self.comboE, reader: .readerDefault)])
        #expect(preferences.hotkey == Self.comboE)
        #expect(presenter.lastState?.editorShortcut == .init(combo: Self.comboE, isRegistered: true))
    }

    @Test func aRecordForTheReaderKeepsTheEditor() {
        _ = shown()
        presenter.send(.beginRecording(.reader))

        presenter.send(.record(.reader, Self.comboY))

        #expect(shortcuts.applied == [.apply(editor: .default, reader: Self.comboY)])
        #expect(preferences.readerHotkey == Self.comboY)
        #expect(preferences.hotkey == .default)
    }

    @Test func swappingTheTwoCombosIsAConflictUntilTheOtherMoves() {
        _ = shown()

        presenter.send(.record(.editor, .readerDefault))

        #expect(presenter.lastState?.editorShortcut.problem == .sameAsOther(.reader))
        #expect(preferences.hotkey == .default)
    }

    @Test func aFailedApplyRollsBackAndIsNotSaved() {
        shortcuts.refusing = [Self.comboE]
        _ = shown()
        presenter.send(.beginRecording(.editor))

        presenter.send(.record(.editor, Self.comboE))

        #expect(shortcuts.calls == [
            .suspend,
            .apply(editor: Self.comboE, reader: .readerDefault),
            .apply(editor: .default, reader: .readerDefault),
        ])
        #expect(preferences.hotkey == .default)
        #expect(presenter.lastState?.editorShortcut == .init(combo: .default, problem: .unavailable, isRegistered: true))
    }

    @Test func aFailureOfTheOtherSlotDoesNotRefuseTheRecord() {
        shortcuts.refusing = [.readerDefault]    // taken by another app since launch
        _ = shown()

        presenter.send(.record(.editor, Self.comboE))

        #expect(preferences.hotkey == Self.comboE)
        #expect(presenter.lastState?.editorShortcut.problem == nil)
        #expect(presenter.lastState?.readerShortcut.isRegistered == false)
    }

    @Test func sameAsOtherIsRefusedWithoutTryingIt() {
        _ = shown()
        presenter.send(.beginRecording(.reader))

        presenter.send(.record(.reader, .default))

        // The only apply restores the saved combos after the suspension.
        #expect(shortcuts.calls == [.suspend, .apply(editor: .default, reader: .readerDefault)])
        #expect(preferences.readerHotkey == .readerDefault)
        #expect(presenter.lastState?.readerShortcut.problem == .sameAsOther(.editor))
        #expect(presenter.lastState?.readerShortcut.isRecording == false)
    }

    @Test func aRuleProblemWithoutARecordingAppliesNothing() {
        _ = shown()

        presenter.send(.record(.editor, KeyCombo(keyCode: 0x11, modifiers: .option)))

        #expect(shortcuts.calls.isEmpty)
        #expect(presenter.lastState?.editorShortcut.problem == .optionOnlyRefused)
    }

    @Test func theNextRecordingClearsTheProblem() {
        _ = shown()
        presenter.send(.record(.editor, KeyCombo(keyCode: 0x11, modifiers: [])))
        #expect(presenter.lastState?.editorShortcut.problem == .needsModifier)

        presenter.send(.beginRecording(.editor))

        #expect(presenter.lastState?.editorShortcut.problem == nil)
    }

    @Test func reopeningClearsProblems() {
        let coordinator = shown()
        presenter.send(.record(.editor, KeyCombo(keyCode: 0x11, modifiers: [])))
        presenter.close()

        coordinator.show()

        #expect(presenter.shown.last?.editorShortcut.problem == nil)
    }

    // MARK: - Reader off and reset

    @Test func turningOffTheReaderSavesNilThenAppliesTheEditorAlone() {
        _ = shown()

        presenter.send(.turnOffReader)

        #expect(preferences.readerHotkey == nil)
        #expect(shortcuts.calls == [.apply(editor: .default, reader: nil)])
        #expect(presenter.lastState?.readerShortcut == .init(combo: nil, isRegistered: false))
        #expect(presenter.lastState?.isReaderOn == false)
    }

    @Test func turningOffWhileRecordingEndsTheRecording() {
        _ = shown()
        presenter.send(.beginRecording(.reader))

        presenter.send(.turnOffReader)

        #expect(shortcuts.calls == [.suspend, .apply(editor: .default, reader: nil)])
        #expect(presenter.lastState?.readerShortcut.isRecording == false)
    }

    @Test func resettingTheReaderTurnsItBackOn() {
        preferences.readerHotkey = nil
        _ = shown()

        presenter.send(.resetShortcut(.reader))

        #expect(preferences.readerHotkey == .readerDefault)
        #expect(shortcuts.calls == [.apply(editor: .default, reader: .readerDefault)])
        #expect(presenter.lastState?.isReaderOn == true)
    }

    @Test func resettingTheEditorRestoresItsDefault() {
        preferences.hotkey = Self.comboE
        _ = shown()

        presenter.send(.resetShortcut(.editor))

        #expect(preferences.hotkey == .default)
        #expect(shortcuts.applied == [.apply(editor: .default, reader: .readerDefault)])
    }

    @Test func resettingToAComboTheOtherSlotHoldsIsAConflict() {
        preferences.hotkey = Self.comboE
        preferences.readerHotkey = .default
        _ = shown()

        presenter.send(.resetShortcut(.editor))

        #expect(preferences.hotkey == Self.comboE)
        #expect(shortcuts.calls.isEmpty)
        #expect(presenter.lastState?.editorShortcut.problem == .sameAsOther(.reader))
    }

    @Test func resetAllWritesEveryDefaultAndAppliesOnce() {
        let custom = InMemoryPreferencesStore(
            fontSize: FontSize(points: 120),
            hotkey: Self.comboE,
            clipboardRestore: .none,
            readerHotkey: nil,
            readerFontSize: FontSize(points: 32),
            readerHoldThreshold: .milliseconds(700),
            followingUnit: .paragraph,
            pinnedUnit: .line,
            hasCompletedFirstLaunch: true
        )
        let coordinator = keep(SettingsCoordinator(dependencies: SettingsDependencies(
            preferences: custom,
            permissions: permissions,
            shortcuts: shortcuts,
            presenter: presenter,
            sleeper: sleeper,
            relaunch: {}
        )))
        coordinator.show()
        presenter.send(.beginRecording(.editor))

        presenter.send(.resetAll)

        #expect(shortcuts.calls == [.suspend, .apply(editor: .default, reader: .readerDefault)])
        #expect(custom.hotkey == .default)
        #expect(custom.readerHotkey == .readerDefault)
        #expect(custom.fontSize == FontSizePolicy.default)
        #expect(custom.readerFontSize == FontSizePolicy.default)
        #expect(custom.readerHoldThreshold == ReaderDefaults.holdThreshold)
        #expect(custom.followingUnit == ReaderDefaults.followingUnit)
        #expect(custom.pinnedUnit == ReaderDefaults.pinnedUnit)
        #expect(custom.clipboardRestore == .default)
        #expect(custom.hasCompletedFirstLaunch == true)
        #expect(presenter.lastState?.editorShortcut.isRecording == false)
    }

    // MARK: - Setters

    @Test func fontSizeSettersWriteTheClampedValueToTheirOwnKey() {
        preferences.fontSize = FontSize(points: 64)
        preferences.readerFontSize = FontSize(points: 64)
        _ = shown()

        presenter.send(.setEditorFontSize(FontSize(points: 999)))
        #expect(preferences.fontSize == FontSize(points: FontSizePolicy.range.upperBound))
        #expect(preferences.readerFontSize == FontSize(points: 64))

        presenter.send(.setReaderFontSize(FontSize(points: 1)))
        #expect(preferences.readerFontSize == FontSize(points: FontSizePolicy.range.lowerBound))
        #expect(preferences.fontSize == FontSize(points: FontSizePolicy.range.upperBound))

        presenter.send(.setReaderFontSize(FontSize(points: 80)))
        #expect(preferences.readerFontSize == FontSize(points: 80))
        #expect(presenter.lastState?.readerFontSize == FontSize(points: 80))
    }

    @Test func holdThresholdIsWrittenClamped() {
        _ = shown()

        presenter.send(.setHoldThreshold(.milliseconds(50)))
        #expect(preferences.readerHoldThreshold == .milliseconds(150))

        presenter.send(.setHoldThreshold(.milliseconds(5000)))
        #expect(preferences.readerHoldThreshold == .milliseconds(800))

        presenter.send(.setHoldThreshold(.milliseconds(425)))
        #expect(preferences.readerHoldThreshold == .milliseconds(425))
        #expect(presenter.lastState?.holdThreshold == .milliseconds(425))
    }

    @Test func unitsAreWritten() {
        _ = shown()

        presenter.send(.setFollowingUnit(.line))
        presenter.send(.setPinnedUnit(.sentence))

        #expect(preferences.followingUnit == .line)
        #expect(preferences.pinnedUnit == .sentence)
        #expect(presenter.lastState?.followingUnit == .line)
        #expect(presenter.lastState?.pinnedUnit == .sentence)
    }

    @Test func clipboardToggleMapsToTheDefaultAndNone() {
        _ = shown()

        presenter.send(.setRestoresClipboard(false))
        #expect(preferences.clipboardRestore == ClipboardRestorePolicy.none)
        #expect(presenter.lastState?.restoresClipboard == false)

        presenter.send(.setRestoresClipboard(true))
        #expect(preferences.clipboardRestore == .default)
        #expect(presenter.lastState?.restoresClipboard == true)
    }

    @Test func aCustomRestoreLimitIsKeptUntilTheToggleIsTurnedOff() {
        preferences.clipboardRestore = .restore(maxBytes: 1024)
        let coordinator = shown()
        #expect(coordinator.state.restoresClipboard)

        presenter.send(.setRestoresClipboard(true))
        #expect(preferences.clipboardRestore == .restore(maxBytes: 1024))

        presenter.send(.setRestoresClipboard(false))
        presenter.send(.setRestoresClipboard(true))
        #expect(preferences.clipboardRestore == .default)
    }

    // MARK: - Accessibility

    @Test func grantAccessRequestsAccessibilityThenOpensSystemSettings() {
        _ = shown()

        presenter.send(.grantAccess)

        #expect(permissions.calls == [.requestAccessibility, .openSystemSettings])
    }

    @Test func relaunchCallsTheClosure() {
        _ = shown()

        presenter.send(.relaunch)

        #expect(relaunches.count == 1)
    }

    @Test func thePermissionIsReReadEverySecondWhileVisible() async {
        permissions.current = .allDenied
        _ = shown()
        #expect(presenter.shown.last?.permission == .needsGrant)

        await tick()
        #expect(presenter.updates.isEmpty)    // unchanged: nothing sent

        permissions.current = Permissions(accessibility: .granted, eventPosting: .denied)
        await tick()
        #expect(presenter.updates.count == 1)
        #expect(presenter.lastState?.permission == .needsRelaunch)
        #expect(sleeper.durations.allSatisfy { $0 == Self.interval })
    }

    @Test func theRefreshStopsWhenTheWindowCloses() async {
        let coordinator = shown()
        await until { sleeper.isParked(Self.interval) }

        presenter.close()
        await until { !sleeper.isParked(Self.interval) }
        #expect(coordinator.isRefreshing == false)
        #expect(coordinator.isOpen == false)

        permissions.current = .allDenied
        for _ in 0..<20 { await Task.yield() }
        #expect(sleeper.durations.count == 1)
        #expect(presenter.updates.isEmpty)
    }

    @Test func theRefreshStopsWhenThePresenterIsNoLongerVisible() async {
        let coordinator = shown()
        await until { sleeper.isParked(Self.interval) }
        presenter.isVisible = false    // closed without `.closed`

        release()
        await until { !coordinator.isRefreshing }
        for _ in 0..<20 { await Task.yield() }
        #expect(sleeper.durations.count == 1)
    }

    @Test func reopeningStartsANewRefresh() async {
        let coordinator = shown()
        await until { sleeper.isParked(Self.interval) }
        presenter.close()
        await until { !sleeper.isParked(Self.interval) }

        coordinator.show()

        await until { sleeper.isParked(Self.interval) }
        #expect(coordinator.isRefreshing)
        #expect(sleeper.durations.count == 2)
    }

    // MARK: - Context

    @Test func theContextIsShownForOverrideAndScenarioNotes() {
        let context = SettingsContext(scenarioName: "settings-hotkey-taken", launchOverrides: [.readerHoldThreshold])

        let state = shown(context: context).state

        #expect(state.context == context)
        #expect(state.context.isOverridden(.readerHoldThreshold))
        #expect(state.context.isOverridden(.followingUnit) == false)
        #expect(state.context.scenarioName == "settings-hotkey-taken")
        #expect(SettingsContext.standard.scenarioName == nil)
        #expect(SettingsContext.standard.launchOverrides.isEmpty)
    }

    // MARK: - Launch at login

    @Test func withoutALoginItemTheRowIsHiddenAndTheIntentsDoNothing() {
        let coordinator = shown()

        presenter.send(.setLaunchAtLogin(true))
        presenter.send(.openLoginItemsSettings)

        #expect(coordinator.state.loginItem == nil)
        #expect(coordinator.state.loginItemError == nil)
    }

    @Test func enablingLaunchAtLoginShowsTheNewStatus() {
        _ = shown(loginItem: loginItem)
        #expect(presenter.shown.last?.loginItem == .notRegistered)

        presenter.send(.setLaunchAtLogin(true))

        #expect(loginItem.setEnabledCalls == [true])
        #expect(presenter.lastState?.loginItem == .enabled)
        #expect(presenter.lastState?.loginItem?.isOn == true)
    }

    @Test func requiresApprovalIsShownAndLinksToLoginItems() {
        loginItem.statusWhenEnabled = .requiresApproval
        _ = shown(loginItem: loginItem)

        presenter.send(.setLaunchAtLogin(true))
        presenter.send(.openLoginItemsSettings)

        #expect(presenter.lastState?.loginItem == .requiresApproval)
        #expect(presenter.lastState?.loginItem?.isOn == true)
        #expect(loginItem.openSystemSettingsCount == 1)
    }

    @Test func approvalInSystemSettingsShowsUpOnTheNextRefresh() async {
        loginItem.status = .requiresApproval
        _ = shown(loginItem: loginItem)

        loginItem.status = .enabled
        await tick()

        #expect(presenter.updates.count == 1)
        #expect(presenter.lastState?.loginItem == .enabled)
    }

    @Test func aFailedLoginItemChangeShowsTheErrorUntilTheNextAttempt() {
        loginItem.failure = .notPermitted
        _ = shown(loginItem: loginItem)

        presenter.send(.setLaunchAtLogin(true))
        #expect(presenter.lastState?.loginItemError == .notPermitted)
        #expect(presenter.lastState?.loginItem == .notRegistered)

        loginItem.failure = nil
        presenter.send(.setLaunchAtLogin(true))
        #expect(presenter.lastState?.loginItemError == nil)
        #expect(presenter.lastState?.loginItem == .enabled)
    }

    // MARK: - Updates

    @Test func withoutAnAvailableUpdaterTheSectionIsHiddenAndTheIntentsDoNothing() {
        let updater = InMemoryUpdater(isAvailable: false, automaticallyChecksForUpdates: true)
        let coordinator = shown(updater: updater)

        presenter.send(.setAutomaticallyChecksForUpdates(false))
        presenter.send(.checkForUpdates)

        #expect(coordinator.state.automaticallyChecksForUpdates == nil)
        #expect(coordinator.state.canCheckForUpdates == false)
        #expect(updater.automaticallyChecksForUpdates == true)
        #expect(updater.checkCount == 0)
    }

    @Test func turningOffAutomaticChecksIsShownAtOnce() {
        let updater = InMemoryUpdater(isAvailable: true, automaticallyChecksForUpdates: true)
        _ = shown(updater: updater)
        #expect(presenter.shown.last?.automaticallyChecksForUpdates == true)

        presenter.send(.setAutomaticallyChecksForUpdates(false))

        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(presenter.lastState?.automaticallyChecksForUpdates == false)
    }

    @Test func checkNowChecksOnceAndIsDisabledWhileACheckRuns() async {
        let updater = InMemoryUpdater(isAvailable: true)
        _ = shown(updater: updater)
        #expect(presenter.shown.last?.canCheckForUpdates == true)

        presenter.send(.checkForUpdates)
        #expect(updater.checkCount == 1)

        updater.canCheckForUpdates = false
        await tick()
        #expect(presenter.lastState?.canCheckForUpdates == false)
    }

    // MARK: - Fakes

    @Test func theLoggingPresenterIsNeverVisibleSoTheRefreshStops() async {
        let coordinator = SettingsCoordinator(dependencies: SettingsDependencies(
            preferences: preferences,
            permissions: permissions,
            shortcuts: shortcuts,
            presenter: LoggingSettingsPresenter(),
            sleeper: InstantSleeper(),
            relaunch: {}
        ))

        coordinator.show()

        await until { !coordinator.isRefreshing }
        #expect(coordinator.isOpen)
    }

    @Test func theInMemoryLoginItemTogglesInMemory() throws {
        let item = InMemoryLoginItem()

        try item.setEnabled(true)
        #expect(item.status == .enabled)
        try item.setEnabled(false)
        #expect(item.status == .notRegistered)
    }
}

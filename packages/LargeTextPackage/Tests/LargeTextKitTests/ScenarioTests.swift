import Foundation
import LargeTextCore
import LargeTextTestSupport
import Testing
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
        #expect(environment.hotkeys === hotkeys)
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
}

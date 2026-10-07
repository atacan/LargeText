import Foundation
import Testing
import LargeTextCore
import LargeTextTestSupport

@MainActor
struct PasteboardTextInserterTests {
    static let timing = InsertionTiming(
        focusReturnDelay: .milliseconds(50),
        pollInterval: .milliseconds(20),
        maxModifierPolls: 3,
        restoreDelay: .milliseconds(600)
    )

    let log = EventLog()
    let permissions = FixedPermissions(.allGranted)
    let pasteboard: FakePasteboard
    let keystrokes: RecordingKeystrokes
    let focus = StubFocusCapturer(target: Fixtures.target())
    let preferences = InMemoryPreferencesStore()
    let sleeper: RecordingSleeper
    let inserter: PasteboardTextInserter

    init() {
        pasteboard = FakePasteboard(items: [.text("original")], changeCount: 10, log: log)
        keystrokes = RecordingKeystrokes(log: log)
        sleeper = RecordingSleeper(log: log)
        inserter = PasteboardTextInserter(
            permissions: permissions,
            pasteboard: pasteboard,
            keystrokes: keystrokes,
            focus: focus,
            preferences: preferences,
            sleeper: sleeper,
            timing: Self.timing
        )
    }

    // MARK: - Paste path

    @Test func fullStepOrderForInsertAndSubmit() async {
        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insertAndSubmit)
        await inserter.pendingRestore?.value

        #expect(outcome == .inserted(clipboardOverwritten: false))
        #expect(log.events == [
            .sleep(.milliseconds(50)),
            .snapshot,
            .write("hello", transient: true),
            .key(.paste),
            .key(.returnKey),
            .sleep(.milliseconds(600)),
            .restore,
        ])
        #expect(pasteboard.string == "original")
    }

    @Test func insertWithoutSubmitSendsNoReturn() async {
        _ = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)
        await inserter.pendingRestore?.value

        #expect(keystrokes.sent == [.paste])
    }

    @Test func outcomeIsReturnedBeforeTheRestoreRuns() async {
        _ = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)

        #expect(inserter.pendingRestore != nil)
        #expect(pasteboard.restoredSnapshots.isEmpty)
        await inserter.pendingRestore?.value
        #expect(pasteboard.restoredSnapshots.count == 1)
    }

    @Test func modifierWaitHappensBeforeSnapshot() async {
        keystrokes.scriptedModifiers = [.command, .command]

        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)
        await inserter.pendingRestore?.value

        #expect(outcome == .inserted(clipboardOverwritten: false))
        #expect(keystrokes.modifierReads == 3)
        #expect(log.events == [
            .sleep(.milliseconds(50)),
            .sleep(.milliseconds(20)),
            .sleep(.milliseconds(20)),
            .snapshot,
            .write("hello", transient: true),
            .key(.paste),
            .sleep(.milliseconds(600)),
            .restore,
        ])
    }

    @Test(arguments: [ElementKind.singleLineText, .multiLineText, nil])
    func textIsPastedVerbatim(kind: ElementKind?) async {
        let text = "  leading\n\ttabbed\r\ntrailing  "

        _ = await inserter.insert(text, into: Fixtures.target(kind: kind), mode: .insert)

        #expect(pasteboard.writes.map(\.string) == [text])
    }

    @Test func terminalsGetLineBreaksToo() async {
        focus.keyboardFocusProcessIdentifier = Fixtures.terminal.processIdentifier

        _ = await inserter.insert(" ls\npwd", into: Fixtures.target(Fixtures.terminal, kind: nil), mode: .insert)

        #expect(pasteboard.writes.map(\.string) == [" ls\npwd"])
    }

    // MARK: - Focus guard and modifiers

    @Test(arguments: [Int32(999), nil])
    func focusPidMismatchCopiesWithoutSnapshot(focusedPID: Int32?) async {
        focus.keyboardFocusProcessIdentifier = focusedPID

        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insertAndSubmit)

        #expect(outcome == .copiedToClipboard(.targetChanged))
        #expect(log.events == [.sleep(.milliseconds(50)), .write("hello", transient: false)])
        #expect(pasteboard.snapshotCount == 0)
        #expect(keystrokes.modifierReads == 0)
        #expect(inserter.pendingRestore == nil)
    }

    @Test func modifiersHeldAfterMaxPollsCopiesWithoutSnapshot() async {
        keystrokes.restingModifiers = .command

        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insertAndSubmit)

        #expect(outcome == .copiedToClipboard(.modifiersHeld))
        #expect(keystrokes.modifierReads == Self.timing.maxModifierPolls + 1)
        #expect(sleeper.durations == [.milliseconds(50)] + Array(repeating: .milliseconds(20), count: 3))
        #expect(pasteboard.snapshotCount == 0)
        #expect(keystrokes.sent.isEmpty)
        #expect(pasteboard.writes.map(\.transient) == [false])
        #expect(pasteboard.string == "hello")
    }

    // MARK: - Restore

    @Test func restoreIsSkippedWhenThePasteboardChangedMeanwhile() async {
        sleeper.onSleep = { [pasteboard] duration in
            if duration == Self.timing.restoreDelay { pasteboard.simulateExternalCopy("someone else") }
        }

        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)
        await inserter.pendingRestore?.value

        #expect(outcome == .inserted(clipboardOverwritten: false))
        #expect(pasteboard.restoredSnapshots.isEmpty)
        #expect(pasteboard.string == "someone else")
    }

    @Test func backToBackPastesRestoreTheOriginalClipboard() async {
        sleeper.heldDuration = Self.timing.restoreDelay

        _ = await inserter.insert("first", into: Fixtures.target(), mode: .insert)
        _ = await inserter.insert("second", into: Fixtures.target(), mode: .insert)
        sleeper.releaseHeld()
        await inserter.pendingRestore?.value

        #expect(pasteboard.snapshotCount == 1)
        #expect(pasteboard.restoredSnapshots.count == 1)
        #expect(pasteboard.string == "original")
    }

    @Test func flushRestoresImmediately() async {
        sleeper.heldDuration = Self.timing.restoreDelay

        _ = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)
        inserter.flushPendingRestore()
        #expect(pasteboard.string == "original")

        sleeper.releaseHeld()
        await inserter.pendingRestore?.value
        #expect(pasteboard.restoredSnapshots.count == 1)
    }

    @Test func noRestorePolicyOverwritesClipboard() async {
        preferences.clipboardRestore = .none

        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)

        #expect(outcome == .inserted(clipboardOverwritten: true))
        #expect(inserter.pendingRestore == nil)
        #expect(log.events == [.sleep(.milliseconds(50)), .write("hello", transient: true), .key(.paste)])
        #expect(pasteboard.string == "hello")
    }

    @Test func incompleteSnapshotIsStillRestored() async {
        let small = PasteboardSnapshot.Item.text("abc")
        let large = PasteboardSnapshot.Item(dataByType: ["public.tiff": Data(count: 100)])
        let pasteboard = FakePasteboard(items: [small, large])
        let inserter = PasteboardTextInserter(
            permissions: permissions, pasteboard: pasteboard, keystrokes: keystrokes, focus: focus,
            preferences: InMemoryPreferencesStore(clipboardRestore: .restore(maxBytes: 10)),
            sleeper: sleeper, timing: Self.timing
        )

        let outcome = await inserter.insert("hello", into: Fixtures.target(), mode: .insert)
        await inserter.pendingRestore?.value

        #expect(outcome == .inserted(clipboardOverwritten: false))
        #expect(pasteboard.restoredSnapshots == [PasteboardSnapshot(items: [small], isComplete: false)])
        #expect(pasteboard.items == [small])
    }

    // MARK: - Copy-only routes

    @Test func missingEventPostingPermissionCopiesImmediately() async {
        permissions.current = Permissions(accessibility: .granted, eventPosting: .denied)

        let outcome = await inserter.insert("a\nb", into: Fixtures.target(), mode: .insertAndSubmit)

        #expect(outcome == .copiedToClipboard(.permissionMissing))
        #expect(log.events == [.write("a\nb", transient: false)])
        #expect(!pasteboard.isTransient)
    }

    @Test func notEditableTargetCopiesImmediately() async {
        let outcome = await inserter.insert("hello", into: Fixtures.target(kind: .notEditable), mode: .insert)

        #expect(outcome == .copiedToClipboard(.noEditableTarget))
        #expect(log.events == [.write("hello", transient: false)])
    }

    @Test func missingApplicationCopiesImmediately() async {
        let outcome = await inserter.insert("hello", into: Fixtures.target(nil), mode: .insert)

        #expect(outcome == .copiedToClipboard(.noEditableTarget))
        #expect(log.events == [.write("hello", transient: false)])
    }

    @Test func clipboardWriterWritesNonTransient() {
        let pasteboard = FakePasteboard()

        let outcome = ClipboardWriter(pasteboard: pasteboard).copy("hi", reason: .targetChanged)

        #expect(outcome == .copiedToClipboard(.targetChanged))
        #expect(pasteboard.writes.count == 1)
        #expect(pasteboard.writes.first?.transient == false)
        #expect(pasteboard.string == "hi")
    }
}

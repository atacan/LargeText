import Foundation
import Testing
import LargeTextCore
import LargeTextTestSupport

/// One test (or more) per row of the §3.5 transition table.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct EditingSessionCoordinatorTests {
    // MARK: - idle → toggle()

    @Test func secureTargetIsRefusedWithoutShowingTheOverlay() async {
        let harness = CoordinatorHarness(target: Fixtures.target(kind: .secureText, selection: "hunter2"))

        await harness.coordinator.toggle()

        #expect(harness.log.events == [.notice(.secureFieldUnsupported)])
        #expect(harness.overlay.presentCount == 0)
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func toggleFromIdlePresentsWithFullChrome() async throws {
        let harness = CoordinatorHarness(target: Fixtures.target(selection: "apple.com"))
        harness.preferences.fontSize = FontSize(points: 80)

        let id = try #require(await harness.open())

        #expect(harness.coordinator.phase == .editing(sessionID: id))
        #expect(harness.log.events == [.present(initialText: "apple.com")])
        #expect(harness.overlay.lastChrome == OverlayChrome(
            fontSize: FontSize(points: 80),
            targetName: "Safari",
            targetBundleIdentifier: "com.apple.Safari",
            targetFrame: Fixtures.frame,
            hints: TargetHints(willCopyToClipboard: false)
        ))
    }

    @Test func outOfRangeFontPreferenceIsClampedOnOpen() async throws {
        let harness = CoordinatorHarness()
        harness.preferences.fontSize = FontSize(points: 1000)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastChrome?.fontSize == FontSize(points: 200))
    }

    @Test func emptyOpenWithoutSelectionOrDraft() async throws {
        let harness = CoordinatorHarness(target: Fixtures.target(selection: ""))

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "")
    }

    @Test func eachOpenStartsANewSession() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        await harness.send(.cancel(.userCancelled), to: first)

        let second = try #require(await harness.open())

        #expect(first != second)
    }

    // MARK: - Drafts

    @Test func cancelKeepsDraftAndNextOpenPrefillsIt() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "half-typed"
        await harness.send(.cancel(.lostFocus), to: first)
        #expect(harness.coordinator.phase == .idle)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "half-typed")
        #expect(harness.inserter.calls.isEmpty)
    }

    @Test func selectionWinsOverDraft() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "draft"
        await harness.send(.cancel(.userCancelled), to: first)
        harness.focus.target = Fixtures.target(selection: "selected")

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "selected")
    }

    @Test func emptyCancelClearsDraft() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "draft"
        await harness.send(.cancel(.userCancelled), to: first)
        let second = try #require(await harness.open())
        harness.overlay.textToReturn = ""
        await harness.send(.cancel(.userCancelled), to: second)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "")
    }

    @Test func whitespaceOnlyCancelIsKeptAsDraft() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "  \n"
        await harness.send(.cancel(.userCancelled), to: first)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "  \n")
    }

    @Test func nonEmptyCommitClearsDraft() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "draft"
        await harness.send(.cancel(.userCancelled), to: first)
        let second = try #require(await harness.open())
        harness.overlay.textToReturn = "final"
        await harness.send(.commit(.insert), to: second)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "")
    }

    @Test func whitespaceOnlyCommitIsInserted() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        harness.overlay.textToReturn = " \t\n "
        await harness.send(.commit(.insert), to: id)

        #expect(harness.inserter.calls.count == 1)
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func emptyCommitLeavesDraftUntouched() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "draft"
        await harness.send(.cancel(.userCancelled), to: first)
        let second = try #require(await harness.open())
        harness.overlay.textToReturn = ""
        await harness.send(.commit(.insertAndSubmit), to: second)

        #expect(harness.inserter.calls.isEmpty)
        #expect(harness.coordinator.phase == .idle)
        _ = try #require(await harness.open())
        #expect(harness.overlay.lastInitialText == "draft")
    }

    // MARK: - editing → commit / toggle / cancel

    @Test func commitDismissesThenInsertsThenIdles() async throws {
        let harness = CoordinatorHarness(target: Fixtures.target(selection: "x"))
        let id = try #require(await harness.open())
        harness.overlay.textToReturn = "hello"

        await harness.send(.commit(.insertAndSubmit), to: id)

        #expect(harness.log.events == [.present(initialText: "x"), .dismiss, .insert("hello", .insertAndSubmit)])
        #expect(harness.inserter.lastTarget?.application == Fixtures.safari)
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func toggleWhileEditingCommitsWithInsert() async throws {
        let harness = CoordinatorHarness()
        _ = try #require(await harness.open())
        harness.overlay.textToReturn = "hello"

        await harness.coordinator.toggle()

        #expect(harness.log.events == [.present(initialText: ""), .dismiss, .insert("hello", .insert)])
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func cancelDismissesWithoutInserting() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        harness.overlay.textToReturn = "hello"

        await harness.send(.cancel(.userCancelled), to: id)

        #expect(harness.log.events == [.present(initialText: ""), .dismiss])
        #expect(harness.coordinator.phase == .idle)
    }

    @Test(arguments: [
        (InsertionOutcome.copiedToClipboard(.permissionMissing), [Notice.copiedToClipboard(.permissionMissing)]),
        (.copiedToClipboard(.noEditableTarget), [.copiedToClipboard(.noEditableTarget)]),
        (.copiedToClipboard(.targetChanged), [.copiedToClipboard(.targetChanged)]),
        (.copiedToClipboard(.modifiersHeld), [.copiedToClipboard(.modifiersHeld)]),
        (.inserted(clipboardOverwritten: true), [.clipboardReplaced]),
        (.inserted(clipboardOverwritten: false), []),
    ])
    func commitShowsNoticeForOutcome(outcome: InsertionOutcome, notices: [Notice]) async throws {
        let harness = CoordinatorHarness()
        harness.inserter.outcome = outcome
        let id = try #require(await harness.open())
        harness.overlay.textToReturn = "hello"

        await harness.send(.commit(.insert), to: id)

        #expect(harness.notices.shown == notices)
        #expect(Array(harness.log.events.suffix(notices.count + 1)) == [.insert("hello", .insert)] + notices.map { .notice($0) })
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func copyOnlyCommitAlsoClearsDraft() async throws {
        let harness = CoordinatorHarness()
        harness.inserter.outcome = .copiedToClipboard(.targetChanged)
        let first = try #require(await harness.open())
        harness.overlay.textToReturn = "draft"
        await harness.send(.cancel(.userCancelled), to: first)
        let second = try #require(await harness.open())
        harness.overlay.textToReturn = "final"
        await harness.send(.commit(.insert), to: second)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastInitialText == "")
    }

    // MARK: - editing → zoom

    @Test func zoomPersistsAndResendsFullChrome() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        let opened = try #require(harness.overlay.lastChrome)

        await harness.send(.zoom(.bigger), to: id)
        await harness.send(.zoom(.bigger), to: id)
        await harness.send(.zoom(.smaller), to: id)

        var expected = opened
        expected.fontSize = FontSize(points: 72)
        #expect(harness.preferences.fontSize == FontSize(points: 72))
        #expect(harness.overlay.updates.map(\.fontSize.points) == [72, 80, 72])
        #expect(harness.overlay.updates.last == expected)
        #expect(harness.coordinator.phase == .editing(sessionID: id))

        await harness.send(.zoom(.reset), to: id)
        #expect(harness.preferences.fontSize == FontSizePolicy.default)
    }

    @Test func zoomedSizeIsUsedForTheNextSession() async throws {
        let harness = CoordinatorHarness()
        let first = try #require(await harness.open())
        await harness.send(.zoom(.bigger), to: first)
        await harness.send(.cancel(.userCancelled), to: first)

        _ = try #require(await harness.open())

        #expect(harness.overlay.lastChrome?.fontSize == FontSize(points: 72))
    }

    // MARK: - closing: everything ignored

    @Test func lateLostFocusAndToggleDuringCommitAreIgnored() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        harness.overlay.holdDismiss = true

        let commit = Task { await harness.send(.commit(.insertAndSubmit), to: id) }
        await harness.overlay.waitUntilDismissIsHeld()
        #expect(harness.coordinator.phase == .closing(sessionID: id))

        await harness.send(.cancel(.lostFocus), to: id)
        await harness.send(.commit(.insert), to: id)
        await harness.send(.zoom(.bigger), to: id)
        await harness.coordinator.toggle()
        #expect(harness.coordinator.phase == .closing(sessionID: id))

        harness.overlay.completeDismiss(returning: "hello")
        await commit.value

        #expect(harness.log.events == [.present(initialText: ""), .dismiss, .insert("hello", .insertAndSubmit)])
        #expect(harness.overlay.presentCount == 1)
        #expect(harness.overlay.updates.isEmpty)
        #expect(harness.preferences.fontSize == FontSizePolicy.default)
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func toggleDuringCancelIsIgnored() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        harness.overlay.holdDismiss = true

        let cancel = Task { await harness.send(.cancel(.userCancelled), to: id) }
        await harness.overlay.waitUntilDismissIsHeld()
        await harness.coordinator.toggle()
        await harness.send(.commit(.insert), to: id)
        harness.overlay.completeDismiss(returning: "draft")
        await cancel.value

        #expect(harness.log.events == [.present(initialText: ""), .dismiss])
        #expect(harness.coordinator.phase == .idle)
    }

    @Test func toggleCommitDuringClosingIsIgnored() async throws {
        let harness = CoordinatorHarness()
        _ = try #require(await harness.open())
        harness.overlay.holdDismiss = true

        let commit = Task { await harness.coordinator.toggle() }
        await harness.overlay.waitUntilDismissIsHeld()
        await harness.coordinator.toggle()
        harness.overlay.completeDismiss(returning: "hello")
        await commit.value

        #expect(harness.overlay.dismissCount == 1)
        #expect(harness.inserter.calls.map(\.text) == ["hello"])
        #expect(harness.coordinator.phase == .idle)
    }

    // MARK: - Stale session ids

    @Test func intentsWithUnknownSessionIDAreIgnoredWhileEditing() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())

        await harness.send(.commit(.insert), to: UUID())
        await harness.send(.cancel(.lostFocus), to: UUID())
        await harness.send(.zoom(.bigger), to: UUID())

        #expect(harness.log.events == [.present(initialText: "")])
        #expect(harness.coordinator.phase == .editing(sessionID: id))
    }

    @Test func intentsFromAPreviousSessionAreIgnored() async throws {
        let harness = CoordinatorHarness()
        let old = try #require(await harness.open())
        await harness.send(.cancel(.userCancelled), to: old)
        let current = try #require(await harness.open())

        await harness.send(.cancel(.lostFocus), to: old)
        await harness.send(.commit(.insert), to: old)

        #expect(harness.coordinator.phase == .editing(sessionID: current))
        #expect(harness.overlay.dismissCount == 1)
        #expect(harness.inserter.calls.isEmpty)
    }

    @Test func intentsWhileIdleAreIgnored() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        await harness.send(.cancel(.userCancelled), to: id)

        await harness.send(.commit(.insert), to: id)
        await harness.send(.zoom(.bigger), to: id)

        #expect(harness.coordinator.phase == .idle)
        #expect(harness.overlay.dismissCount == 1)
        #expect(harness.overlay.updates.isEmpty)
    }

    // MARK: - Live intents closure

    @Test func presentedIntentsClosureRoutesToHandle() async throws {
        let harness = CoordinatorHarness()
        let id = try #require(await harness.open())
        let intents = try #require(harness.overlay.lastIntents)
        harness.overlay.holdDismiss = true

        intents(OverlayIntent(sessionID: id, kind: .cancel(.userCancelled)))
        await harness.overlay.waitUntilDismissIsHeld()
        #expect(harness.coordinator.phase == .closing(sessionID: id))

        harness.overlay.completeDismiss(returning: "")
        for _ in 0..<100 where harness.coordinator.phase != .idle {
            await Task.yield()
        }
        #expect(harness.coordinator.phase == .idle)
    }
}

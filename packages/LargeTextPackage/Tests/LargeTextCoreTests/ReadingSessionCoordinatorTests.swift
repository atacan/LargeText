import Foundation
import Testing
import LargeTextCore
import LargeTextTestSupport

/// The §6 coordinator rows. Every race is driven by `ControllableTextReader` and `RecordingSleeper`: no real
/// delays.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReadingSessionCoordinatorTests {
    typealias Shown = SpyReaderPresenter.Shown
    static let paragraphText = "Intro.\nFirst one. Second one here.\nOutro."

    // MARK: - Hold

    @Test func holdFollowsThenReleaseDismisses() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        #expect(harness.coordinator.phase == .following)
        #expect(harness.pointer.isTicking)

        await harness.complete(0, with: ReaderFixtures.nativeSentence(in: "One. Two three.", pointerAt: "three"))
        #expect(harness.presenter.presented == [
            Shown(content: .text("Two three.", scrollToUTF16: 4), chrome: ReaderFixtures.chrome(.following)),
        ])

        harness.release(at: 12)
        await harness.until { harness.coordinator.isIdle }

        #expect(harness.presenter.dismissCount == 1)
        #expect(harness.pointer.isTicking == false)
        #expect(harness.notices.shown.isEmpty)
    }

    @Test func holdReleasedBeforeReadOnePresentsNothing() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()

        harness.release(at: 10.5)
        #expect(harness.coordinator.isIdle)
        await harness.complete(0, with: ReaderFixtures.text("late"))

        #expect(harness.presenter.presented.isEmpty)
        #expect(harness.notices.shown.isEmpty)
        #expect(harness.presenter.dismissCount == 0)
    }

    @Test func everyReadGetsTheSessionPolicyAndTheFollowingUnit() async {
        let harness = ReaderHarness()
        harness.preferences.followingUnit = .line
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.move(toX: 300)
        await harness.reader.waitForCalls(2)

        #expect(harness.reader.calls.map(\.policy) == [.standard, .standard])
        #expect(harness.reader.calls.map(\.granularity) == [.line, .line])
        #expect(harness.reader.calls.map(\.pid) == [nil, nil])
        #expect(harness.reader.calls.first?.pointer == ReaderFixtures.sample(x: 100))
    }

    @Test func everyTickIsForwardedToThePresenter() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()

        harness.pointer.move(to: ReaderFixtures.sample(x: 101))    // read in flight
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.pointer.move(to: ReaderFixtures.sample(x: 102))    // throttled
        harness.move(toX: 300)                                      // starts a read

        #expect(harness.presenter.pointerSamples.map(\.appKit.x) == [101, 102, 300])
    }

    // MARK: - One read in flight

    @Test func movesDuringAReadCauseOneFollowUpReadAtTheLatestPoint() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()

        harness.move(toX: 120)
        harness.move(toX: 140)
        harness.move(toX: 160)
        #expect(harness.reader.calls.count == 1)

        await harness.complete(0, with: ReaderFixtures.text("A"))
        await harness.reader.waitForCalls(2)
        await harness.settle()

        #expect(harness.reader.calls.count == 2)
        #expect(harness.reader.calls[1].pointer == ReaderFixtures.sample(x: 160))
    }

    @Test func throttleHoldsBackReadsUntilTheIntervalAndDistanceAllow() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A", frame: nil))

        harness.pointer.move(to: ReaderFixtures.sample(x: 300))          // far, but too soon
        harness.time.advance(by: .milliseconds(60))
        harness.pointer.move(to: ReaderFixtures.sample(x: 103))          // late enough, too close
        await harness.settle()
        #expect(harness.reader.calls.count == 1)

        harness.pointer.move(to: ReaderFixtures.sample(x: 300))
        await harness.reader.waitForCalls(2)
    }

    @Test func identicalResultsAreNotRedrawn() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))

        harness.move(toX: 300)
        await harness.reader.waitForCalls(2)
        await harness.complete(1, with: ReaderFixtures.text("A"))
        harness.move(toX: 500)
        await harness.reader.waitForCalls(3)
        await harness.complete(2, with: ReaderFixtures.text("B"))

        #expect(harness.presenter.presented.count == 1)
        #expect(harness.presenter.updates == [
            Shown(content: .text("B", scrollToUTF16: nil), chrome: ReaderFixtures.chrome(.following)),
        ])
    }

    @Test func nothingWhileFollowingShowsTheQuietCard() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()

        await harness.complete(0, with: .nothing)

        #expect(harness.presenter.presented.map(\.content) == [.nothing])
        #expect(harness.coordinator.phase == .following)
    }

    // MARK: - Own window under the pointer (§4.2)

    @Test func ownWindowWhileFollowingKeepsTheShownCardAndReadsOn() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.move(toX: 300)
        await harness.reader.waitForCalls(2)

        await harness.complete(1, with: .ownWindow)
        harness.move(toX: 500)
        await harness.reader.waitForCalls(3)

        #expect(harness.presenter.updates.isEmpty)
        #expect(harness.presenter.lastShown?.content == .text("A", scrollToUTF16: nil))
        #expect(harness.coordinator.phase == .following)
    }

    @Test func ownWindowOnTapCountsAsNothing() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        harness.release(at: 10.1)

        await harness.complete(0, with: .ownWindow)

        #expect(harness.coordinator.isIdle)
        #expect(harness.notices.shown == [.nothingToRead])
        #expect(harness.presenter.presented.isEmpty)
    }

    // MARK: - Stale results

    @Test func resultFromAnEndedSessionIsDroppedEvenWithTheSameSeq() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead(at: 10)
        harness.release(at: 11)
        await harness.pressAndWaitForRead(at: 20, totalReads: 2)

        await harness.complete(0, with: ReaderFixtures.text("old session"))
        #expect(harness.presenter.presented.isEmpty)

        await harness.complete(1, with: ReaderFixtures.text("new session"))
        #expect(harness.presenter.presented.map(\.content) == [.text("new session", scrollToUTF16: nil)])
    }

    @Test func resultAfterCloseIsDropped() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.move(toX: 300)
        await harness.reader.waitForCalls(2)

        harness.release(at: 12)
        await harness.until { harness.coordinator.isIdle }
        await harness.complete(1, with: ReaderFixtures.text("B"))

        #expect(harness.presenter.updates.isEmpty)
        #expect(harness.presenter.lastShown?.content == .text("A", scrollToUTF16: nil))
    }

    // MARK: - Tap

    @Test func tapPinsTheShownCardReSegmentedToTheParagraph() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.nativeSentence(in: Self.paragraphText, pointerAt: "Second"))
        #expect(harness.presenter.lastShown?.content == .text("Second one here.", scrollToUTF16: 0))

        harness.release(at: 10.2)

        #expect(harness.coordinator.phase == .pinned)
        #expect(harness.presenter.pins == [
            Shown(content: .text("First one. Second one here.", scrollToUTF16: nil), chrome: ReaderFixtures.chrome(.pinned)),
        ])
        #expect(harness.pointer.isTicking == false)
    }

    @Test func webTextHasNoWindowAndStaysAsItIsOnPin() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        let web = ReadText(text: "Click here to continue.", granularity: .sentence, source: .unit, sourceFrame: ReaderFixtures.frame)
        await harness.complete(0, with: .text(web))

        harness.release(at: 10.2)

        #expect(harness.presenter.pins.map(\.content) == [.text("Click here to continue.", scrollToUTF16: nil)])
    }

    @Test func tapBeforeReadOneIsPresentedPinnedOnArrival() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()

        harness.release(at: 10.1)
        #expect(harness.coordinator.phase == .pinnedAwaitingFirst)
        #expect(harness.pointer.isTicking == false)
        await harness.complete(0, with: ReaderFixtures.nativeSentence(in: Self.paragraphText, pointerAt: "Second"))

        #expect(harness.coordinator.phase == .pinned)
        #expect(harness.presenter.presented == [
            Shown(content: .text("First one. Second one here.", scrollToUTF16: nil), chrome: ReaderFixtures.chrome(.pinned)),
        ])
        #expect(harness.presenter.pins.isEmpty)
    }

    @Test func pinWhileAReadRunsFreezesOnTheLastDisplayedResult() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.move(toX: 300)
        await harness.reader.waitForCalls(2)

        harness.release(at: 10.2)
        await harness.complete(1, with: ReaderFixtures.text("B"))

        #expect(harness.presenter.pins.map(\.content) == [.text("A", scrollToUTF16: nil)])
        #expect(harness.presenter.updates.isEmpty)
        #expect(harness.presenter.lastShown?.content == .text("A", scrollToUTF16: nil))
    }

    @Test func nothingOnTapShowsTheNoticeAndDismisses() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: .nothing)

        harness.release(at: 10.2)
        await harness.until { harness.coordinator.isIdle }

        #expect(harness.notices.shown == [.nothingToRead])
        #expect(harness.presenter.dismissCount == 1)
        #expect(harness.presenter.pins.isEmpty)
    }

    @Test func nothingArrivingAfterATapShowsOnlyTheNotice() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        harness.release(at: 10.1)

        await harness.complete(0, with: .nothing)

        #expect(harness.coordinator.isIdle)
        #expect(harness.notices.shown == [.nothingToRead])
        #expect(harness.presenter.presented.isEmpty)
    }

    @Test func hiddenOnTapPinsTheHiddenCard() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: .hidden)

        harness.release(at: 10.2)

        #expect(harness.presenter.pins == [Shown(content: .hidden, chrome: ReaderChrome(fontSize: FontSizePolicy.default, mode: .pinned))])
        #expect(harness.notices.shown.isEmpty)
    }

    @Test func pressWhilePinnedClosesAndItsReleaseIsIgnored() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.release(at: 10.2)

        harness.press(at: 15)
        #expect(harness.coordinator.isClosing)
        await harness.until { harness.coordinator.isIdle }
        harness.release(at: 15.1)

        #expect(harness.coordinator.isIdle)
        #expect(harness.reader.calls.count == 1)
    }

    @Test func pressWhileFollowingClosesAsAMissedRelease() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))

        harness.press(at: 30)

        #expect(harness.coordinator.isClosing)
    }

    // MARK: - Permission

    @Test func permissionLostMidFollowClosesWithOneNotice() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.move(toX: 300)
        await harness.reader.waitForCalls(2)

        await harness.complete(1, with: .permissionMissing)
        await harness.until { harness.coordinator.isIdle }

        #expect(harness.notices.shown == [.readerNeedsAccessibility])
        #expect(harness.presenter.dismissCount == 1)
        #expect(harness.presenter.updates.isEmpty)
    }

    @Test func permissionMissingOnReadOneShowsNoCard() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()

        await harness.complete(0, with: .permissionMissing)

        #expect(harness.coordinator.isIdle)
        #expect(harness.notices.shown == [.readerNeedsAccessibility])
        #expect(harness.presenter.presented.isEmpty)
    }

    @Test func untrustedPressShowsTheNoticeWithoutReading() async {
        let harness = ReaderHarness()
        harness.permissions.current = .allDenied

        harness.press()
        harness.release(at: 10.1)
        await harness.settle()

        #expect(harness.notices.shown == [.readerNeedsAccessibility])
        #expect(harness.reader.calls.isEmpty)
        #expect(harness.coordinator.isIdle)
        #expect(harness.pointer.isTicking == false)
    }

    // MARK: - Stuck-key check and the cap

    @Test func keyStateCheckStartsOnlyAfterThresholdPlusMargin() async {
        let harness = ReaderHarness()
        harness.keyState.isDown = false
        await harness.pressAndWaitForRead()

        harness.pointer.tick()
        #expect(harness.coordinator.phase == .following)
        #expect(harness.sleeper.isParked(ReaderFixtures.keyStateCheckDelay))

        harness.sleeper.release(ReaderFixtures.keyStateCheckDelay)
        await harness.until { harness.coordinator.isCheckingKeyState }
        harness.pointer.tick()

        #expect(harness.coordinator.isIdle)
    }

    @Test func pollCantTurnATapIntoAHold() async {
        let harness = ReaderHarness()
        harness.keyState.isDown = false
        await harness.pressAndWaitForRead()

        harness.pointer.tick()
        harness.release(at: 10.28)

        #expect(harness.coordinator.phase == .pinnedAwaitingFirst)
    }

    @Test func unknownOrDownKeyStateKeepsFollowing() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        harness.sleeper.release(ReaderFixtures.keyStateCheckDelay)
        await harness.until { harness.coordinator.isCheckingKeyState }

        harness.keyState.isDown = nil
        harness.pointer.tick()
        harness.keyState.isDown = true
        harness.pointer.tick()

        #expect(harness.coordinator.phase == .following)
    }

    @Test func capClosesAForgottenHold() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))

        harness.sleeper.release(ReaderFixtures.cap)
        await harness.until { harness.coordinator.isIdle }

        #expect(harness.presenter.dismissCount == 1)
    }

    @Test func capCanBeDisabled() async {
        let harness = ReaderHarness(timing: ReaderTiming(maxFollowDuration: nil))
        await harness.pressAndWaitForRead()
        await harness.settle()

        #expect(harness.sleeper.durations == [ReaderFixtures.keyStateCheckDelay])
        #expect(harness.coordinator.phase == .following)
    }

    @Test func pinCancelsTheTimersAndTicking() async {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        #expect(harness.sleeper.isParked(ReaderFixtures.cap))

        harness.release(at: 10.2)
        await harness.until {
            !harness.sleeper.isParked(ReaderFixtures.cap) && !harness.sleeper.isParked(ReaderFixtures.keyStateCheckDelay)
        }

        #expect(harness.pointer.isTicking == false)
        #expect(harness.coordinator.phase == .pinned)
    }

    // MARK: - Intents

    @Test func zoomPersistsTheReaderFontSizeAndLeavesTheEditorsAlone() async throws {
        let harness = ReaderHarness()
        harness.preferences.readerFontSize = FontSize(points: 80)
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.release(at: 10.2)

        harness.send(.zoom(.bigger))

        #expect(harness.preferences.readerFontSize == FontSize(points: 88))
        #expect(harness.preferences.fontSize == FontSizePolicy.default)
        #expect(harness.presenter.updates == [
            Shown(content: .text("A", scrollToUTF16: nil), chrome: ReaderFixtures.chrome(.pinned, fontSize: 88)),
        ])
    }

    @Test func sessionStartsAtTheReaderFontSize() async {
        let harness = ReaderHarness()
        harness.preferences.fontSize = FontSize(points: 120)
        harness.preferences.readerFontSize = FontSize(points: 96)
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))

        #expect(harness.presenter.presented.map(\.chrome.fontSize) == [FontSize(points: 96)])
    }

    @Test func unsetReaderFontSizeFollowsTheEditorsAndIsClamped() async {
        let harness = ReaderHarness()
        harness.preferences.fontSize = FontSize(points: 1000)
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))

        #expect(harness.presenter.presented.map(\.chrome.fontSize) == [FontSize(points: 200)])
    }

    @Test func pressIsIgnoredWhileTheReaderShortcutIsOff() async {
        let harness = ReaderHarness()
        harness.preferences.readerHotkey = nil

        harness.press()
        harness.release(at: 10.1)
        await harness.settle()

        #expect(harness.coordinator.isIdle)
        #expect(harness.reader.calls.isEmpty)
        #expect(harness.presenter.presented.isEmpty)
        #expect(harness.notices.shown.isEmpty)
    }

    @Test func closeIntentClosesAndStaleSessionIntentsAreIgnored() async throws {
        let harness = ReaderHarness()
        await harness.pressAndWaitForRead(at: 10)
        await harness.complete(0, with: ReaderFixtures.text("A"))
        let first = try #require(harness.presenter.lastSessionID)
        harness.release(at: 10.2)
        harness.send(.close(.userCancelled))
        await harness.until { harness.coordinator.isIdle }

        await harness.pressAndWaitForRead(at: 20, totalReads: 2)
        await harness.complete(1, with: ReaderFixtures.text("B"))
        harness.send(.close(.userCancelled), to: first)
        harness.send(.zoom(.bigger), to: first)

        #expect(harness.coordinator.phase == .following)
        #expect(harness.preferences.readerFontSize == FontSizePolicy.default)
        #expect(harness.presenter.dismissCount == 1)
    }

    /// Settings plan §3.5: the card starts closing before Kit is asked to open Settings, and a stale ⌘, does
    /// nothing.
    @Test func openSettingsClosesThePinnedCardThenAsksForSettings() async throws {
        let harness = ReaderHarness()
        var phaseWhenAsked: ReaderGesture.Phase?
        var asked = 0
        harness.coordinator.onOpenSettings = {
            asked += 1
            phaseWhenAsked = harness.coordinator.phase
        }
        await harness.pressAndWaitForRead(at: 10)
        harness.release(at: 10.1)
        await harness.complete(0, with: ReaderFixtures.text("A"))
        let id = try #require(harness.presenter.lastSessionID)

        harness.send(.openSettings)
        #expect(phaseWhenAsked == .closing)
        await harness.coordinator.close()
        harness.send(.openSettings, to: id)

        #expect(asked == 1)
        #expect(harness.coordinator.isIdle)
        #expect(harness.presenter.dismissCount == 1)
    }

    // MARK: - Closing and phases

    @Test func phasesFollowTheGestureThroughAFullTap() async {
        let harness = ReaderHarness()
        harness.presenter.holdDismiss = true
        var phases: [ReaderGesture.Phase] = [harness.coordinator.phase]

        await harness.pressAndWaitForRead()
        phases.append(harness.coordinator.phase)
        harness.release(at: 10.1)
        phases.append(harness.coordinator.phase)
        await harness.complete(0, with: ReaderFixtures.text("A"))
        phases.append(harness.coordinator.phase)
        harness.send(.close(.lostFocus))
        phases.append(harness.coordinator.phase)
        #expect(harness.coordinator.isClosing)
        await harness.presenter.waitUntilDismissIsHeld()
        harness.presenter.completeDismiss()
        await harness.until { harness.coordinator.isIdle }
        phases.append(harness.coordinator.phase)

        #expect(phases == [.idle, .following, .pinnedAwaitingFirst, .pinned, .closing, .idle])
    }

    @Test func pressDuringClosingIsIgnoredAndSoIsItsRelease() async {
        let harness = ReaderHarness()
        harness.presenter.holdDismiss = true
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))
        harness.release(at: 12)

        harness.press(at: 12.1)
        await harness.presenter.waitUntilDismissIsHeld()
        harness.presenter.completeDismiss()
        await harness.until { harness.coordinator.isIdle }
        harness.release(at: 12.2)

        #expect(harness.coordinator.isIdle)
        #expect(harness.reader.calls.count == 1)
    }

    @Test func closeTwiceDuringTheFadeAwaitsTheSameDismissal() async {
        let harness = ReaderHarness()
        harness.presenter.holdDismiss = true
        await harness.pressAndWaitForRead()
        await harness.complete(0, with: ReaderFixtures.text("A"))

        let firstDone = Flag()
        let secondDone = Flag()
        let first = Task {
            await harness.coordinator.close()
            firstDone.isSet = true
        }
        await harness.presenter.waitUntilDismissIsHeld()
        let second = Task {
            await harness.coordinator.close()
            secondDone.isSet = true
        }
        await harness.settle()
        #expect(firstDone.isSet == false)
        #expect(secondDone.isSet == false)
        #expect(harness.coordinator.isClosing)

        harness.presenter.completeDismiss()
        await first.value
        await second.value

        #expect(harness.presenter.dismissCount == 1)
        #expect(harness.coordinator.isIdle)
    }

    @Test func closeWithoutACardReturnsIdleAtOnce() async {
        let harness = ReaderHarness()
        await harness.coordinator.close() // idle: nothing to do
        await harness.pressAndWaitForRead()

        await harness.coordinator.close()

        #expect(harness.coordinator.isIdle)
        #expect(harness.presenter.dismissCount == 0)
    }
}

import Testing
import LargeTextCore

/// One test (or more) per §3.1 transition. Tap vs. hold comes from the events' own timestamps only.
struct ReaderGestureTests {
    /// A gesture that has been pressed at `t = 10` s.
    static func following(_ policy: ReaderGesture.PressWhileFollowing = .standard) -> ReaderGesture {
        var gesture = ReaderGesture(holdThreshold: .milliseconds(300), pressWhileFollowing: policy)
        _ = gesture.handle(.pressed(at: 10))
        return gesture
    }

    static func pinned() -> ReaderGesture {
        var gesture = following()
        _ = gesture.handle(.firstResultArrived)
        _ = gesture.handle(.released(at: 10.1))
        return gesture
    }

    static func closing() -> ReaderGesture {
        var gesture = following()
        _ = gesture.handle(.released(at: 11))
        return gesture
    }

    // MARK: - idle

    @Test func pressStartsFollowingAndSchedulesTheKeyStateCheckAfterThresholdPlusMargin() {
        var gesture = ReaderGesture(holdThreshold: .milliseconds(300))

        #expect(gesture.handle(.pressed(at: 10)) == [.startFollowing, .startKeyStateCheck(after: .milliseconds(400))])
        #expect(gesture.phase == .following)
    }

    @Test func keyStateCheckDelayFollowsTheThreshold() {
        var gesture = ReaderGesture(holdThreshold: .milliseconds(500))

        #expect(gesture.handle(.pressed(at: 0)) == [.startFollowing, .startKeyStateCheck(after: .milliseconds(600))])
    }

    @Test(arguments: [
        ReaderGesture.Input.released(at: 10),
        .forceClose(.requested),
        .firstResultArrived,
        .dismissed,
    ])
    func everythingButAPressIsIgnoredWhenIdle(input: ReaderGesture.Input) {
        var gesture = ReaderGesture()

        #expect(gesture.handle(input) == [.ignore])
        #expect(gesture.phase == .idle)
    }

    // MARK: - Tap vs. hold

    @Test func tapAfterTheFirstResultPins() {
        var gesture = Self.following()
        #expect(gesture.handle(.firstResultArrived) == [])

        #expect(gesture.handle(.released(at: 10.28)) == [.pin])
        #expect(gesture.phase == .pinned)
    }

    @Test func tapBeforeTheFirstResultWaitsForItThenPins() {
        var gesture = Self.following()

        #expect(gesture.handle(.released(at: 10.1)) == [.presentPinnedOnArrival])
        #expect(gesture.phase == .pinnedAwaitingFirst)
        #expect(gesture.handle(.firstResultArrived) == [.pin])
        #expect(gesture.phase == .pinned)
    }

    @Test func holdReleaseCloses() {
        var gesture = Self.following()
        _ = gesture.handle(.firstResultArrived)

        #expect(gesture.handle(.released(at: 12)) == [.close(.holdReleased)])
        #expect(gesture.phase == .closing)
    }

    @Test func holdReleasedBeforeTheFirstResultCloses() {
        var gesture = Self.following()

        #expect(gesture.handle(.released(at: 10.5)) == [.close(.holdReleased)])
    }

    /// Binary-exact stamps, so the edge is tested without floating-point noise.
    @Test func releaseExactlyAtTheThresholdIsAHold() {
        var gesture = ReaderGesture(holdThreshold: .milliseconds(250))
        _ = gesture.handle(.pressed(at: 1))

        #expect(gesture.handle(.released(at: 1.25)) == [.close(.holdReleased)])
    }

    @Test func releaseJustUnderTheThresholdIsATap() {
        var gesture = ReaderGesture(holdThreshold: .milliseconds(250))
        _ = gesture.handle(.pressed(at: 1))

        #expect(gesture.handle(.released(at: 1.249)) == [.presentPinnedOnArrival])
    }

    /// The stamps decide, not when the events are handled: a release stamped 280 ms after the press is a tap
    /// however late it is delivered. The key-state check can't intervene either, as it starts at 400 ms.
    @Test func tapReleasedAt280msIsNeverAHold() {
        var gesture = Self.following()

        #expect(gesture.handle(.released(at: 10.28)) == [.presentPinnedOnArrival])
        #expect(gesture.keyStateCheckDelay > .milliseconds(280))
    }

    @Test func eachSessionClassifiesAgainstItsOwnPress() {
        var gesture = Self.closing()
        _ = gesture.handle(.dismissed)

        _ = gesture.handle(.pressed(at: 50))
        // Not a pin: the first session's result doesn't count for the second.
        #expect(gesture.handle(.released(at: 50.1)) == [.presentPinnedOnArrival])
    }

    // MARK: - Press while following (R1)

    @Test func pressWhileFollowingIsAMissedReleaseByDefault() {
        #expect(ReaderGesture.PressWhileFollowing.standard == .closeAsMissedRelease)
        var gesture = Self.following()

        #expect(gesture.handle(.pressed(at: 11)) == [.close(.pressedWhileFollowing)])
        // Its release arrives while closing, then the next one when idle: both ignored.
        #expect(gesture.handle(.released(at: 11.1)) == [.ignore])
        _ = gesture.handle(.dismissed)
        #expect(gesture.handle(.released(at: 11.2)) == [.ignore])
        #expect(gesture.phase == .idle)
    }

    @Test func autoRepeatPressesAreIgnoredWhenConfiguredAndDontResetThePressTime() {
        var gesture = Self.following(.ignoreAsAutoRepeat)

        #expect(gesture.handle(.pressed(at: 10.2)) == [.ignore])
        #expect(gesture.phase == .following)
        // 10.35 is 150 ms after the repeat, but 350 ms after the real press: a hold.
        #expect(gesture.handle(.released(at: 10.35)) == [.close(.holdReleased)])
    }

    // MARK: - Pinned

    @Test func pressWhilePinnedClosesOnKeyDownAndItsReleaseIsIgnored() {
        var gesture = Self.pinned()

        #expect(gesture.handle(.pressed(at: 20)) == [.close(.pressedWhilePinned)])
        #expect(gesture.handle(.released(at: 20.1)) == [.ignore])
        #expect(gesture.phase == .closing)
    }

    @Test func pressWhileAwaitingTheFirstResultCloses() {
        var gesture = Self.following()
        _ = gesture.handle(.released(at: 10.1))

        #expect(gesture.handle(.pressed(at: 10.2)) == [.close(.pressedWhilePinned)])
    }

    @Test func lateResultsAndReleasesAreIgnoredWhilePinned() {
        var gesture = Self.pinned()

        #expect(gesture.handle(.firstResultArrived) == [.ignore])
        #expect(gesture.handle(.released(at: 10.2)) == [.ignore])
        #expect(gesture.phase == .pinned)
    }

    // MARK: - forceClose

    @Test(arguments: [
        ReaderEndReason.keyReleased,
        .maxFollowDuration,
        .user(.userCancelled),
        .permissionMissing,
        .requested,
    ])
    func forceCloseClosesFromEveryNonIdlePhase(reason: ReaderEndReason) {
        var following = Self.following()
        var awaiting = Self.following()
        _ = awaiting.handle(.released(at: 10.1))
        var pinned = Self.pinned()

        #expect(following.handle(.forceClose(reason)) == [.close(reason)])
        #expect(awaiting.handle(.forceClose(reason)) == [.close(reason)])
        #expect(pinned.handle(.forceClose(reason)) == [.close(reason)])
        #expect([following.phase, awaiting.phase, pinned.phase] == [.closing, .closing, .closing])
    }

    @Test func maxFollowDurationClosesAHold() {
        var gesture = Self.following()

        #expect(gesture.handle(.forceClose(.maxFollowDuration)) == [.close(.maxFollowDuration)])
    }

    // MARK: - closing

    @Test func pressDuringClosingIsIgnoredAndSoIsItsRelease() {
        var gesture = Self.closing()

        #expect(gesture.handle(.pressed(at: 11.1)) == [.ignore])
        #expect(gesture.handle(.forceClose(.requested)) == [.ignore])
        _ = gesture.handle(.dismissed)
        #expect(gesture.handle(.released(at: 11.2)) == [.ignore])
        #expect(gesture.phase == .idle)
    }

    @Test func dismissedReturnsToIdle() {
        var gesture = Self.closing()

        #expect(gesture.handle(.dismissed) == [])
        #expect(gesture.phase == .idle)
    }
}

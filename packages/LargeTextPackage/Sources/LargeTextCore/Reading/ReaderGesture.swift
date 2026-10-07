import Foundation

/// Why a reading session ends. Carried by `ReaderGesture.Input.forceClose` and `ReaderEffect.close`.
package enum ReaderEndReason: Equatable, Sendable {
    /// The shortcut was released after `holdThreshold`: the end of a hold.
    case holdReleased
    /// A press arrived while following: its release was missed (R1 default, see `PressWhileFollowing`).
    case pressedWhileFollowing
    /// A press while pinned closes on key-down.
    case pressedWhilePinned
    /// The stuck-key check found the shortcut no longer held.
    case keyReleased
    /// `ReaderTiming.maxFollowDuration` elapsed while following.
    case maxFollowDuration
    /// ⎋, a backdrop click or resign key, from the card.
    case user(ReaderCloseReason)
    /// A tap found no readable text.
    case nothingToRead
    /// A read reported that Accessibility isn't trusted.
    case permissionMissing
    /// `close()` from outside, e.g. before the editor opens.
    case requested
}

/// What the coordinator must do after a `ReaderGesture` transition. The coordinator only executes these;
/// it never changes the phase itself.
package enum ReaderEffect: Equatable, Sendable {
    /// idle → following: start ticking, issue read #1, schedule the cap.
    case startFollowing
    /// Arm the stuck-key check once `after` has elapsed (see `ReaderGesture.keyStateCheckDelay`).
    case startKeyStateCheck(after: Duration)
    /// → pinned: freeze on the last displayed result and pin it.
    case pin
    /// A tap released before read #1 returned: stop following, keep read #1, pin it when it arrives.
    case presentPinnedOnArrival
    /// → closing: stop everything and dismiss.
    case close(ReaderEndReason)
    /// The input has no meaning in the current phase.
    case ignore
}

/// The tap-or-hold state machine (§3.1). Pure: it decides tap vs. hold only from the hotkey events' own
/// timestamps, so a busy main actor or a slow read can't turn a tap into a hold. It owns every phase change.
package struct ReaderGesture: Equatable, Sendable {
    package enum Phase: Equatable, Sendable {
        case idle
        /// Held: the card follows the pointer.
        case following
        /// Tapped before read #1 returned; the card is presented pinned when it arrives.
        case pinnedAwaitingFirst
        case pinned
        /// Waiting for the presenter's fade (`.dismissed`).
        case closing
    }

    package enum Input: Equatable, Sendable {
        case pressed(at: TimeInterval)
        case released(at: TimeInterval)
        /// A close without a timestamp (stuck key, cap, ⎋, permission, `close()`). Valid in any non-idle phase.
        case forceClose(ReaderEndReason)
        /// The first result of the session is in hand (displayed while following, or due to be pinned).
        case firstResultArrived
        /// The presenter finished fading out.
        case dismissed
    }

    /// What a press while following means. Spike R1 decides; flip `standard` once it has.
    package enum PressWhileFollowing: Equatable, Sendable {
        /// Carbon sends no auto-repeat presses, so the release was missed: close.
        case closeAsMissedRelease
        /// Carbon sends auto-repeat presses: ignore them, and rely on the key-state check and the cap.
        case ignoreAsAutoRepeat

        /// The plan's current default, until R1 is answered.
        package static let standard: PressWhileFollowing = .closeAsMissedRelease
    }

    /// The key-state check starts this long after `holdThreshold`, so its late synthetic release can only
    /// ever close a session that is already a hold (§3.1).
    package static let keyStateCheckMargin: Duration = .milliseconds(100)

    package private(set) var phase: Phase = .idle
    /// A release earlier than this after the press is a tap. Read at each press; change it only while idle.
    package var holdThreshold: Duration
    package let pressWhileFollowing: PressWhileFollowing

    /// When the session's press happened, in `HotkeyEvent.at` seconds.
    private var pressedAt: TimeInterval?
    /// Whether the session has a result to pin (see `Input.firstResultArrived`).
    private var hasFirstResult = false

    package init(
        holdThreshold: Duration = ReaderDefaults.holdThreshold,
        pressWhileFollowing: PressWhileFollowing = .standard
    ) {
        self.holdThreshold = holdThreshold
        self.pressWhileFollowing = pressWhileFollowing
    }

    /// When the stuck-key check may start after the press.
    package var keyStateCheckDelay: Duration { holdThreshold + Self.keyStateCheckMargin }

    package mutating func handle(_ input: Input) -> [ReaderEffect] {
        switch (phase, input) {
        case (.idle, .pressed(let time)):
            phase = .following
            pressedAt = time
            hasFirstResult = false
            return [.startFollowing, .startKeyStateCheck(after: keyStateCheckDelay)]

        case (.following, .released(let time)):
            guard isTap(releasedAt: time) else { return close(.holdReleased) }
            if hasFirstResult {
                phase = .pinned
                return [.pin]
            }
            phase = .pinnedAwaitingFirst
            return [.presentPinnedOnArrival]

        case (.following, .pressed):
            switch pressWhileFollowing {
            case .closeAsMissedRelease: return close(.pressedWhileFollowing)
            case .ignoreAsAutoRepeat: return [.ignore]
            }

        case (.following, .firstResultArrived):
            hasFirstResult = true
            return []

        case (.pinnedAwaitingFirst, .firstResultArrived):
            hasFirstResult = true
            phase = .pinned
            return [.pin]

        case (.pinnedAwaitingFirst, .pressed), (.pinned, .pressed):
            // Its release arrives in closing or idle, where it is ignored.
            return close(.pressedWhilePinned)

        case (.following, .forceClose(let reason)),
             (.pinnedAwaitingFirst, .forceClose(let reason)),
             (.pinned, .forceClose(let reason)):
            return close(reason)

        case (.closing, .dismissed):
            phase = .idle
            pressedAt = nil
            hasFirstResult = false
            return []

        default:
            // A lone release, a press or release during closing, a close while idle, a late result.
            return [.ignore]
        }
    }

    private mutating func close(_ reason: ReaderEndReason) -> [ReaderEffect] {
        phase = .closing
        return [.close(reason)]
    }

    private func isTap(releasedAt time: TimeInterval) -> Bool {
        guard let pressedAt else { return false }
        return time - pressedAt < holdThreshold.timeInterval
    }
}

extension Duration {
    /// The duration in (fractional) seconds, to compare with `HotkeyEvent.at` differences.
    fileprivate var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) * 1e-18
    }
}

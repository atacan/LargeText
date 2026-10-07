import CoreGraphics
import Foundation
import os

/// Owns the reader session (§3.1, §4.4, §5.5). `ReaderGesture` makes every phase change; this class only
/// executes the effects it returns: it starts and stops reads, timers and pointer ticking, and drives the
/// presenter.
///
/// While following, at most one read is in flight. Each read is tagged `(sessionID, seq)`; a result is
/// dropped when its session ended, the phase is no longer following, or a newer one was displayed.
@MainActor
package final class ReadingSessionCoordinator {
    package var phase: ReaderGesture.Phase { gesture.phase }
    package var isIdle: Bool { gesture.phase == .idle }
    package var isClosing: Bool { gesture.phase == .closing }
    /// Whether the stuck-key check is armed: it then runs on every pointer tick while following.
    package var isCheckingKeyState: Bool { session?.isCheckingKeyState ?? false }

    private let dependencies: ReaderDependencies
    private var gesture = ReaderGesture()
    private var session: ReadingSession?
    /// The fade in progress; a second `close()` awaits it too.
    private var dismissal: Task<Void, Never>?

    package init(dependencies: ReaderDependencies) {
        self.dependencies = dependencies
    }

    /// The reader shortcut, stamped by the Carbon callback. Synchronous, so the phase is decided before
    /// the next event is delivered.
    package func hotkey(_ event: HotkeyEvent) {
        switch event.phase {
        case .pressed:
            if gesture.phase == .idle {
                guard dependencies.permissions.current.accessibility == .granted else {
                    Logger.core.info("Reader: Accessibility not granted; session not started")
                    dependencies.notices.show(.readerNeedsAccessibility)
                    return
                }
                gesture.holdThreshold = dependencies.preferences.readerHoldThreshold
            }
            send(.pressed(at: event.at))
        case .released:
            send(.released(at: event.at))
        }
    }

    /// Intents from the card: ⎋, backdrop click, resign key, zoom. Ignored for a stale session.
    package func handle(_ intent: ReaderIntent) {
        guard let session, session.id == intent.sessionID, !isClosing else {
            Logger.core.debug("Reader intent \(String(describing: intent.kind)) for \(intent.sessionID) ignored in \(String(describing: self.phase))")
            return
        }
        switch intent.kind {
        case .close(let reason):
            send(.forceClose(.user(reason)))
        case .zoom(let step):
            zoom(step, in: session)
        }
    }

    /// Closes any session and returns once the card is gone. Idempotent: a call during the fade awaits
    /// the same dismissal. Returns without suspending when idle.
    package func close() async {
        if gesture.phase != .idle, gesture.phase != .closing {
            send(.forceClose(.requested))
        }
        if let dismissal {
            await dismissal.value
        }
    }

    // MARK: - Gesture

    private func send(_ input: ReaderGesture.Input) {
        let before = gesture.phase
        let effects = gesture.handle(input)
        if gesture.phase != before {
            Logger.core.info("Reader: \(String(describing: before)) → \(String(describing: self.gesture.phase))")
        }
        for effect in effects {
            perform(effect, for: input)
        }
    }

    private func perform(_ effect: ReaderEffect, for input: ReaderGesture.Input) {
        switch effect {
        case .startFollowing:
            startFollowing()
        case .startKeyStateCheck(let delay):
            guard let session else { return }
            schedule(after: delay, in: session) { _, session in session.isCheckingKeyState = true }
        case .pin:
            pin()
        case .presentPinnedOnArrival:
            // Read #1 stays in flight; its result is pinned on arrival.
            guard let session else { return }
            stopFollowing(session)
        case .close(let reason):
            close(reason)
        case .ignore:
            Logger.core.debug("Reader: \(String(describing: input)) ignored in \(String(describing: self.phase))")
        }
    }

    // MARK: - Effects

    private func startFollowing() {
        let preferences = dependencies.preferences
        let session = ReadingSession(
            policy: .standard,
            combo: preferences.readerHotkey,
            followingUnit: preferences.followingUnit,
            pinnedUnit: preferences.pinnedUnit,
            fontSize: FontSizePolicy.clamp(preferences.fontSize)
        )
        self.session = session
        Logger.core.info("Reader session \(session.id): following")

        startRead(at: dependencies.pointer.current, in: session)
        session.ticking = dependencies.pointer.startTicking { [weak self] sample in
            self?.pointerMoved(sample)
        }
        if let cap = dependencies.timing.maxFollowDuration {
            schedule(after: cap, in: session) { coordinator, _ in
                coordinator.send(.forceClose(.maxFollowDuration))
            }
        }
    }

    /// Freezes on the last displayed result: native unit text is re-segmented to the pinned unit, web text
    /// stays as it is. A read still in flight is cancelled and its result ignored.
    private func pin() {
        guard let session else { return }
        stopFollowing(session)
        cancelRead(session)

        let content: ReaderContent
        switch session.displayed {
        case .text(let text):
            content = .text(pinnedText(text, in: session), scrollToUTF16: nil)
        case .hidden:
            content = .hidden
        case .permissionMissing:
            send(.forceClose(.permissionMissing))
            return
        case .nothing, .ownWindow, nil:
            send(.forceClose(.nothingToRead))
            return
        }
        let chrome = chrome(for: session.displayed, mode: .pinned, in: session)
        Logger.core.info("Reader session \(session.id): pinned")
        if session.shown == nil {
            present(content, chrome: chrome, in: session)
        } else {
            dependencies.presenter.pin(content: content, chrome: chrome)
            session.shown = (content, chrome)
        }
    }

    private func close(_ reason: ReaderEndReason) {
        guard let session else {
            // Every non-idle phase has a session; never leave the gesture stuck in closing regardless.
            send(.dismissed)
            return
        }
        stopFollowing(session)
        cancelRead(session)
        Logger.core.info("Reader session \(session.id): closing (\(String(describing: reason)))")

        switch reason {
        case .nothingToRead: dependencies.notices.show(.nothingToRead)
        case .permissionMissing: dependencies.notices.show(.readerNeedsAccessibility)
        default: break
        }

        let id = session.id
        guard session.shown != nil else {
            // Nothing on screen (e.g. a hold released before read #1): no fade to wait for.
            finishClosing(id)
            return
        }
        let presenter = dependencies.presenter
        dismissal = Task { [weak self] in
            await presenter.dismiss()
            self?.finishClosing(id)
        }
    }

    private func finishClosing(_ id: UUID) {
        guard session?.id == id else { return }
        session = nil
        dismissal = nil
        send(.dismissed)
    }

    // MARK: - Following

    private func pointerMoved(_ sample: PointerSample) {
        dependencies.presenter.pointerMoved(sample)
        guard let session, gesture.phase == .following else { return }

        // `nil` (unknown) leaves the session to the hotkey release and the cap.
        if session.isCheckingKeyState, dependencies.keyState.isPhysicallyDown(session.combo) == false {
            send(.forceClose(.keyReleased))
            return
        }
        if session.read != nil {
            session.pendingPoint = sample
        } else if shouldRead(at: sample, in: session) {
            startRead(at: sample, in: session)
        }
    }

    private func shouldRead(at sample: PointerSample, in session: ReadingSession) -> Bool {
        guard let last = session.lastRead else { return true }
        return PointerThrottle.shouldRead(
            at: sample.appKit,
            lastReadAt: last.point,
            elapsed: last.startedAt.duration(to: dependencies.now()),
            lastFrame: session.displayedFrame
        )
    }

    private func startRead(at sample: PointerSample, in session: ReadingSession) {
        session.seq += 1
        session.pendingPoint = nil
        session.lastRead = (sample.appKit, dependencies.now())

        let (id, seq) = (session.id, session.seq)
        let reader = dependencies.textReader
        let granularity = session.followingUnit
        let policy = session.policy
        session.read = Task { [weak self] in
            let result = await reader.read(at: sample, granularity: granularity, policy: policy)
            self?.readFinished(result, sessionID: id, seq: seq)
        }
    }

    private func readFinished(_ result: ReadResult, sessionID: UUID, seq: Int) {
        guard let session, session.id == sessionID else {
            Logger.core.debug("Reader: result for ended session \(sessionID) dropped")
            return
        }
        if seq == session.seq {
            session.read = nil
        }
        guard seq > session.displayedSeq else {
            Logger.core.debug("Reader session \(sessionID): stale result \(seq) dropped")
            return
        }

        // Trust was revoked mid-session: close and say so once; no card.
        if result == .permissionMissing, gesture.phase == .following || gesture.phase == .pinnedAwaitingFirst {
            send(.forceClose(.permissionMissing))
            return
        }
        switch gesture.phase {
        case .following:
            if result == .ownWindow {
                // Our own card or highlight is under the pointer: keep what is shown (§4.2).
                Logger.core.debug("Reader session \(sessionID): result \(seq) over our own window; no update")
            } else {
                display(result, seq: seq, in: session)
            }
            if gesture.phase == .following, session.read == nil,
               let pending = session.pendingPoint, shouldRead(at: pending, in: session) {
                startRead(at: pending, in: session)
            }
        case .pinnedAwaitingFirst:
            session.displayed = result == .ownWindow ? .nothing : result
            session.displayedSeq = seq
            send(.firstResultArrived)
        case .idle, .pinned, .closing:
            Logger.core.debug("Reader session \(sessionID): result \(seq) dropped in \(String(describing: self.phase))")
        }
    }

    private func display(_ result: ReadResult, seq: Int, in session: ReadingSession) {
        let previous = session.displayed
        session.displayed = result
        session.displayedSeq = seq
        defer {
            if previous == nil { send(.firstResultArrived) }
        }
        // Same text and frame: nothing would change on screen, so don't redraw.
        if let previous, Self.looksSame(previous, result) { return }

        let content: ReaderContent = switch result {
        case .text(let text): .text(text.text, scrollToUTF16: Self.pointerOffset(in: text))
        case .hidden: .hidden
        case .nothing, .permissionMissing, .ownWindow: .nothing
        }
        let chrome = chrome(for: result, mode: .following, in: session)
        if session.shown == nil {
            present(content, chrome: chrome, in: session)
        } else {
            dependencies.presenter.update(content: content, chrome: chrome)
            session.shown = (content, chrome)
        }
    }

    private func stopFollowing(_ session: ReadingSession) {
        session.ticking?.cancel()
        session.ticking = nil
        session.timers.forEach { $0.cancel() }
        session.timers.removeAll()
        session.isCheckingKeyState = false
        session.pendingPoint = nil
    }

    private func cancelRead(_ session: ReadingSession) {
        session.read?.cancel()
        session.read = nil
    }

    /// Runs `action` after `delay` if the session is still the current one and still following.
    private func schedule(
        after delay: Duration,
        in session: ReadingSession,
        _ action: @escaping @MainActor (ReadingSessionCoordinator, ReadingSession) -> Void
    ) {
        let sleeper = dependencies.sleeper
        let id = session.id
        session.timers.append(Task { [weak self] in
            do { try await sleeper.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled, let session = self.session, session.id == id,
                  self.gesture.phase == .following
            else { return }
            action(self, session)
        })
    }

    // MARK: - Presentation

    private func present(_ content: ReaderContent, chrome: ReaderChrome, in session: ReadingSession) {
        session.shown = (content, chrome)
        dependencies.presenter.present(sessionID: session.id, content: content, chrome: chrome) { [weak self] intent in
            self?.handle(intent)
        }
    }

    private func zoom(_ step: ZoomStep, in session: ReadingSession) {
        session.fontSize = FontSizePolicy.apply(step, to: session.fontSize)
        dependencies.preferences.fontSize = session.fontSize
        guard var shown = session.shown else { return }
        shown.chrome.fontSize = session.fontSize
        session.shown = shown
        dependencies.presenter.update(content: shown.content, chrome: shown.chrome)
    }

    private func chrome(for result: ReadResult?, mode: ReaderChrome.Mode, in session: ReadingSession) -> ReaderChrome {
        guard case .text(let text) = result else {
            return ReaderChrome(fontSize: session.fontSize, mode: mode)
        }
        return ReaderChrome(
            fontSize: session.fontSize,
            mode: mode,
            appName: text.appName,
            bundleIdentifier: text.bundleIdentifier,
            sourceFrame: text.sourceFrame
        )
    }

    /// Native unit text is re-segmented to the pinned unit from its window, without a new read (§4.3).
    /// Web units, selections and labels have no window, or must not grow, and stay as they are.
    private func pinnedText(_ text: ReadText, in session: ReadingSession) -> String {
        guard text.source == .unit, text.granularity != session.pinnedUnit, let window = text.window,
              let unit = TextSegmenter.unit(session.pinnedUnit, in: window),
              let shown = TextSegmenter.displayText(unit.text, maxCharacters: session.policy.maxCharacters)
        else { return text.text }
        return shown
    }

    /// Where the pointer is in a native unit, so a card that overflows can scroll to the pointer's line.
    private static func pointerOffset(in text: ReadText) -> Int? {
        guard text.source == .unit, let window = text.window,
              let unit = TextSegmenter.unit(text.granularity, in: window)
        else { return nil }
        return min(max(window.indexAtPointer - unit.range.lowerBound, 0), text.text.utf16.count)
    }

    private static func looksSame(_ lhs: ReadResult, _ rhs: ReadResult) -> Bool {
        guard case .text(let old) = lhs, case .text(let new) = rhs else { return lhs == rhs }
        return old.text == new.text && old.sourceFrame == new.sourceFrame
    }
}

/// Mutable per-session state. Lives on the main actor with its coordinator.
@MainActor
private final class ReadingSession {
    let id = UUID()
    /// Snapshotted once and passed to every read (§3.3).
    let policy: ReadPolicy
    let combo: KeyCombo
    let followingUnit: ReadGranularity
    let pinnedUnit: ReadGranularity
    var fontSize: FontSize

    /// The newest read issued; results carry their own.
    var seq = 0
    /// The `seq` of `displayed`.
    var displayedSeq = 0
    /// The one read in flight.
    var read: Task<Void, Never>?
    var lastRead: (point: CGPoint, startedAt: ContinuousClock.Instant)?
    /// The newest tick while a read was in flight.
    var pendingPoint: PointerSample?
    /// The last displayed result (or, when tapped before read #1, the one to pin).
    var displayed: ReadResult?
    /// What the presenter shows; `nil` until the first `present`.
    var shown: (content: ReaderContent, chrome: ReaderChrome)?
    var ticking: (any PointerTickingToken)?
    /// The key-state check delay and the cap.
    var timers: [Task<Void, Never>] = []
    var isCheckingKeyState = false

    /// The frame of the last displayed text, for `PointerThrottle`.
    var displayedFrame: CGRect? {
        guard case .text(let text) = displayed else { return nil }
        return text.sourceFrame
    }

    init(policy: ReadPolicy, combo: KeyCombo, followingUnit: ReadGranularity, pinnedUnit: ReadGranularity, fontSize: FontSize) {
        self.policy = policy
        self.combo = combo
        self.followingUnit = followingUnit
        self.pinnedUnit = pinnedUnit
        self.fontSize = fontSize
    }
}

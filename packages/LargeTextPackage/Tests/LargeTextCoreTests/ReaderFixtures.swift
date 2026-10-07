import CoreGraphics
import Foundation
import LargeTextCore
import LargeTextTestSupport

enum ReaderFixtures {
    static let frame = CGRect(x: 100, y: 200, width: 400, height: 60)
    /// `ReaderDefaults.holdThreshold` + `ReaderGesture.keyStateCheckMargin`.
    static let keyStateCheckDelay: Duration = .milliseconds(400)
    static let cap: Duration = .seconds(30)

    static func sample(x: CGFloat, y: CGFloat = 230) -> PointerSample {
        PointerSample(appKit: CGPoint(x: x, y: y), global: CGPoint(x: x, y: 900 - y))
    }

    /// A label-like result: no window, so nothing to re-segment.
    static func text(_ text: String, frame: CGRect? = frame) -> ReadResult {
        .text(ReadText(
            text: text,
            granularity: .sentence,
            source: .label,
            appName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            sourceFrame: frame
        ))
    }

    /// A native sentence at `pointerAt` in `windowText`, as `ReadTextChooser` would produce it.
    static func nativeSentence(in windowText: String, pointerAt part: String) -> ReadResult {
        let window = TextWindow(
            text: windowText,
            start: 2_000,
            indexAtPointer: 2_000 + (windowText as NSString).range(of: part).location
        )
        return ReadTextChooser.choose(
            from: ReadCandidates(
                pid: 7,
                bundleIdentifier: "com.apple.TextEdit",
                role: "AXTextArea",
                elementFrame: frame,
                window: window
            ),
            granularity: .sentence,
            policy: .standard,
            appName: "TextEdit"
        )
    }

    static func chrome(_ mode: ReaderChrome.Mode, fontSize: Double = 64, frame: CGRect? = frame) -> ReaderChrome {
        ReaderChrome(
            fontSize: FontSize(points: fontSize),
            mode: mode,
            appName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            sourceFrame: frame
        )
    }
}

/// The throttle's clock, advanced by hand.
@MainActor
final class ManualTime {
    var now = ContinuousClock.now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}

@MainActor
final class Flag {
    var isSet = false
}

/// A reader coordinator wired to TestSupport doubles. The key-state check delay and the cap park until
/// released, so no session closes on its own.
@MainActor
final class ReaderHarness {
    let log = EventLog()
    let reader = ControllableTextReader()
    let pointer = ScriptedPointer(current: ReaderFixtures.sample(x: 100))
    let keyState = FixedKeyState()
    let presenter: SpyReaderPresenter
    let notices: SpyNotices
    let preferences = InMemoryPreferencesStore()
    let permissions = FixedPermissions(.allGranted)
    let sleeper: RecordingSleeper
    let time: ManualTime
    let coordinator: ReadingSessionCoordinator

    init(timing: ReaderTiming = .standard) {
        presenter = SpyReaderPresenter(log: log)
        notices = SpyNotices(log: log)
        sleeper = RecordingSleeper(log: log)
        sleeper.heldDurations = [ReaderFixtures.keyStateCheckDelay, ReaderFixtures.cap]
        let time = ManualTime()
        self.time = time
        coordinator = ReadingSessionCoordinator(dependencies: ReaderDependencies(
            textReader: reader,
            pointer: pointer,
            keyState: keyState,
            presenter: presenter,
            notices: notices,
            preferences: preferences,
            permissions: permissions,
            sleeper: sleeper,
            timing: timing,
            now: { time.now }
        ))
    }

    func press(at time: TimeInterval = 10) {
        coordinator.hotkey(HotkeyEvent(phase: .pressed, at: time))
    }

    func release(at time: TimeInterval) {
        coordinator.hotkey(HotkeyEvent(phase: .released, at: time))
    }

    /// Presses and waits for read #`count - 1` to be issued.
    func pressAndWaitForRead(at time: TimeInterval = 10, totalReads count: Int = 1) async {
        press(at: time)
        await reader.waitForCalls(count)
    }

    /// Completes a read and lets the coordinator handle the result.
    func complete(_ index: Int, with result: ReadResult) async {
        reader.complete(readIndex: index, with: result)
        await settle()
    }

    /// Lets main-actor work queued by the previous step run. Used before asserting that something did
    /// *not* happen; positive outcomes are awaited with `until`.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func until(_ condition: () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    /// Moves the pointer far enough, after long enough, to pass `PointerThrottle`.
    func move(toX x: CGFloat) {
        time.advance(by: .milliseconds(100))
        pointer.move(to: ReaderFixtures.sample(x: x))
    }

    func send(_ kind: ReaderIntent.Kind, to sessionID: UUID? = nil) {
        guard let id = sessionID ?? presenter.lastSessionID else { return }
        presenter.lastIntents?(ReaderIntent(sessionID: id, kind: kind))
    }
}

import CoreGraphics
import Foundation
import Testing
import LargeTextCore
import LargeTextTestSupport

/// The reader fakes and spies other suites build on: their parking and ticking must be exact.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReaderTestDoublesTests {
    static func sample(x: CGFloat) -> PointerSample {
        PointerSample(appKit: CGPoint(x: x, y: 100), global: CGPoint(x: x, y: 800))
    }

    static let label = ReadResult.text(ReadText(text: "Save", granularity: .sentence, source: .label))

    // MARK: - StubTextReader

    @Test func stubAnswersByPointerX() async {
        let reader = StubTextReader(
            answers: [
                .init(xRange: 0..<100, result: Self.label),
                .init(xRange: 100..<200, result: .hidden),
            ],
            fallback: .nothing
        )
        #expect(await reader.read(at: Self.sample(x: 50), granularity: .sentence, policy: .standard) == Self.label)
        #expect(await reader.read(at: Self.sample(x: 100), granularity: .sentence, policy: .standard) == .hidden)
        #expect(await reader.read(at: Self.sample(x: 500), granularity: .sentence, policy: .standard) == .nothing)
    }

    // MARK: - ScriptedPointer

    @Test func scriptedPointerTicksOnlyWhileActive() {
        let pointer = ScriptedPointer(current: Self.sample(x: 1))
        var ticks: [PointerSample] = []
        pointer.tick()
        let token = pointer.startTicking { ticks.append($0) }
        pointer.tick()
        pointer.move(to: Self.sample(x: 2))
        token.cancel()
        pointer.tick()

        #expect(ticks == [Self.sample(x: 1), Self.sample(x: 2)])
        #expect(pointer.isTicking == false)
    }

    @Test func cancellingAReplacedTokenKeepsTheNewOne() {
        let pointer = ScriptedPointer()
        var ticks = 0
        let old = pointer.startTicking { _ in Issue.record("replaced callback ticked") }
        _ = pointer.startTicking { _ in ticks += 1 }
        old.cancel()
        pointer.tick()

        #expect(ticks == 1)
    }

    // MARK: - RecordingSleeper

    @Test func heldDurationsParkUntilReleasedIndependently() async throws {
        let sleeper = RecordingSleeper()
        sleeper.heldDurations = [.milliseconds(400), .seconds(30)]
        let short = Task { try await sleeper.sleep(for: .milliseconds(400)) }
        let cap = Task { try await sleeper.sleep(for: .seconds(30)) }
        try await sleeper.sleep(for: .milliseconds(60)) // not held: returns at once
        while !(sleeper.isParked(.milliseconds(400)) && sleeper.isParked(.seconds(30))) { await Task.yield() }

        sleeper.release(.milliseconds(400))
        try await short.value
        #expect(sleeper.isParked(.seconds(30)))

        sleeper.release(.seconds(30))
        try await cap.value
        #expect(sleeper.durations.count == 3)
    }

    @Test func cancellingAHeldSleepThrows() async {
        let sleeper = RecordingSleeper()
        sleeper.heldDurations = [.seconds(30)]
        let cap = Task { try await sleeper.sleep(for: .seconds(30)) }
        while !sleeper.isParked(.seconds(30)) { await Task.yield() }

        cap.cancel()

        await #expect(throws: CancellationError.self) { try await cap.value }
        #expect(sleeper.isParked(.seconds(30)) == false)
    }

    // MARK: - ControllableTextReader

    @Test func controllableReaderCompletesReadsInAnyOrder() async {
        let reader = ControllableTextReader()
        let first = Task { await reader.read(at: Self.sample(x: 1), granularity: .sentence, policy: .standard) }
        await reader.waitForCalls(1)
        let second = Task { await reader.read(at: Self.sample(x: 2), granularity: .paragraph, pid: 42, policy: .standard) }
        await reader.waitForCalls(2)
        #expect(reader.pendingReadIndices == [0, 1])

        reader.complete(readIndex: 1, with: .hidden)
        #expect(await second.value == .hidden)
        reader.complete(readIndex: 0, with: Self.label)
        #expect(await first.value == Self.label)

        #expect(reader.calls.map(\.pid) == [nil, 42])
        #expect(reader.calls.map(\.granularity) == [.sentence, .paragraph])
        #expect(reader.pendingReadIndices.isEmpty)
    }

    // MARK: - SpyReaderPresenter

    @Test func spyPresenterHoldsDismissUntilCompleted() async {
        let log = EventLog()
        let presenter = SpyReaderPresenter(log: log)
        presenter.holdDismiss = true
        let chrome = ReaderChrome(fontSize: FontSizePolicy.default, mode: .following)
        presenter.present(sessionID: UUID(), content: .nothing, chrome: chrome) { _ in }
        presenter.pin(content: .hidden, chrome: chrome)

        let dismissal = Task { await presenter.dismiss() }
        await presenter.waitUntilDismissIsHeld()
        #expect(presenter.isDismissHeld)
        presenter.completeDismiss()
        await dismissal.value

        #expect(log.events == [.readerPresent(.nothing, .following), .readerPin(.hidden), .readerDismiss])
        #expect(presenter.lastShown?.content == .hidden)
    }

    // MARK: - SpyHotkeys

    @Test func spyHotkeysDeliversBothPhases() throws {
        let hotkeys = SpyHotkeys()
        var events: [HotkeyEvent] = []
        var presses = 0
        _ = try hotkeys.register(.readerDefault) { events.append($0) }
        _ = try hotkeys.registerPressOnly(.default) { presses += 1 }

        hotkeys.simulate(.pressed, at: 1, for: .readerDefault)
        hotkeys.simulate(.released, at: 1.2, for: .readerDefault)
        hotkeys.simulate(.pressed, at: 2, for: .default)
        hotkeys.simulate(.released, at: 2.1, for: .default)

        #expect(events == [HotkeyEvent(phase: .pressed, at: 1), HotkeyEvent(phase: .released, at: 1.2)])
        #expect(presses == 1)
    }
}

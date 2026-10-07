import LargeTextCore
import Testing
@testable import LargeTextPlatform

/// Reads only `NSEvent.mouseLocation`; needs no permission.
@Suite @MainActor struct SystemPointerTrackerTests {
    let tracker = SystemPointerTracker()

    @Test func ticksWhileTheTokenIsLive() async throws {
        var ticks = 0
        let token = tracker.startTicking { _ in ticks += 1 }
        defer { token.cancel() }

        for _ in 0..<100 where ticks == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(ticks > 0)
    }

    @Test func noTickAfterCancelReturnsAndCancelIsIdempotent() async throws {
        var ticks = 0
        let token = tracker.startTicking { _ in ticks += 1 }

        token.cancel()
        token.cancel()
        try await Task.sleep(for: .milliseconds(80))

        #expect(ticks == 0)
    }

    @Test func cancellingOneTokenLeavesAnotherTicking() async throws {
        var first = 0
        var second = 0
        let firstToken = tracker.startTicking { _ in first += 1 }
        let secondToken = tracker.startTicking { _ in second += 1 }
        defer { secondToken.cancel() }

        firstToken.cancel()
        for _ in 0..<100 where second == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(first == 0)
        #expect(second > 0)
    }
}

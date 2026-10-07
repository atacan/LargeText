import CoreGraphics
import Testing
import LargeTextCore

struct PointerThrottleTests {
    static let origin = CGPoint(x: 100, y: 100)
    static let frame = CGRect(x: 90, y: 90, width: 20, height: 20)

    static func shouldRead(_ point: CGPoint, after elapsed: Duration, frame: CGRect? = nil) -> Bool {
        PointerThrottle.shouldRead(at: point, lastReadAt: origin, elapsed: elapsed, lastFrame: frame)
    }

    @Test func farMoveWaitsForTheInterval() {
        let far = CGPoint(x: 200, y: 100)

        #expect(!Self.shouldRead(far, after: .milliseconds(59)))
        #expect(Self.shouldRead(far, after: .milliseconds(60)))
    }

    @Test func distanceMustExceedFourPoints() {
        #expect(!Self.shouldRead(CGPoint(x: 104, y: 100), after: .seconds(1)))
        #expect(!Self.shouldRead(CGPoint(x: 102, y: 102), after: .seconds(1)))
        #expect(Self.shouldRead(CGPoint(x: 103, y: 103), after: .seconds(1)))
    }

    @Test func leavingTheFrameCountsEvenForASmallMove() {
        let edge = CGRect(x: 90, y: 90, width: 12, height: 20)

        #expect(Self.shouldRead(CGPoint(x: 103, y: 100), after: .milliseconds(60), frame: edge))
        #expect(!Self.shouldRead(CGPoint(x: 101, y: 100), after: .milliseconds(60), frame: edge))
    }

    @Test func leavingTheFrameStillWaitsForTheInterval() {
        #expect(!Self.shouldRead(CGPoint(x: 300, y: 300), after: .milliseconds(10), frame: Self.frame))
    }

    @Test func stillPointerInsideTheFrameNeverRereads() {
        #expect(!Self.shouldRead(Self.origin, after: .seconds(10), frame: Self.frame))
    }
}

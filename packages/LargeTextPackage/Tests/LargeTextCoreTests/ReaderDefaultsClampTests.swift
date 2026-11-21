import Testing
import LargeTextCore

struct ReaderDefaultsClampTests {
    @Test func theDefaultIsInsideTheRangeAndOnAStep() {
        let range = ReaderDefaults.holdThresholdRange
        #expect(range.contains(ReaderDefaults.holdThreshold))
        #expect((ReaderDefaults.holdThreshold - range.lowerBound) / ReaderDefaults.holdThresholdStep == 6)
    }

    @Test func rangeAndStep() {
        #expect(ReaderDefaults.holdThresholdRange == .milliseconds(150) ... .milliseconds(800))
        #expect(ReaderDefaults.holdThresholdStep == .milliseconds(25))
    }

    @Test func valuesInsideTheRangeAreKept() {
        #expect(ReaderDefaults.clampHoldThreshold(.milliseconds(150)) == .milliseconds(150))
        #expect(ReaderDefaults.clampHoldThreshold(.milliseconds(437)) == .milliseconds(437))
        #expect(ReaderDefaults.clampHoldThreshold(.milliseconds(800)) == .milliseconds(800))
    }

    @Test func valuesOutsideTheRangeAreClamped() {
        #expect(ReaderDefaults.clampHoldThreshold(.milliseconds(100)) == .milliseconds(150))
        #expect(ReaderDefaults.clampHoldThreshold(.zero) == .milliseconds(150))
        #expect(ReaderDefaults.clampHoldThreshold(.milliseconds(-5)) == .milliseconds(150))
        #expect(ReaderDefaults.clampHoldThreshold(.seconds(2)) == .milliseconds(800))
    }
}

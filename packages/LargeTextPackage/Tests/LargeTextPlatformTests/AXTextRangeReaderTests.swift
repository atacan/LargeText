import Testing
@testable import LargeTextPlatform

@Suite struct AXTextRangeReaderTests {
    let radius = AXTextRangeReader.windowRadius

    @Test func windowIsCenteredInLongText() {
        let range = AXTextRangeReader.windowRange(around: 500_000, radius: radius, characterCount: 1_000_000)
        #expect(range == 498_000..<502_000)
    }

    @Test func windowIsClampedAtTheStart() {
        let range = AXTextRangeReader.windowRange(around: 150, radius: radius, characterCount: 1_000_000)
        #expect(range == 0..<2_150)
    }

    @Test func windowIsClampedAtTheEnd() {
        let range = AXTextRangeReader.windowRange(around: 9_900, radius: radius, characterCount: 10_000)
        #expect(range == 7_900..<10_000)
    }

    @Test func shortTextIsReadWhole() {
        let range = AXTextRangeReader.windowRange(around: 40, radius: radius, characterCount: 120)
        #expect(range == 0..<120)
    }

    @Test func indexPastTheEndIsClampedToTheCount() {
        #expect(AXTextRangeReader.clamp(index: 150, characterCount: 120) == 120)
        let range = AXTextRangeReader.windowRange(around: 5_000, radius: radius, characterCount: 3_000)
        #expect(range == 1_000..<3_000)
    }

    @Test func negativeIndexIsClampedToZero() {
        #expect(AXTextRangeReader.clamp(index: -3, characterCount: 10) == 0)
        #expect(AXTextRangeReader.windowRange(around: -3, radius: radius, characterCount: 10) == 0..<10)
    }

    @Test func unknownCountClampsOnlyTheLowerEnd() {
        #expect(AXTextRangeReader.clamp(index: 7_000, characterCount: nil) == 7_000)
        #expect(AXTextRangeReader.windowRange(around: 7_000, radius: radius, characterCount: nil) == 5_000..<9_000)
        #expect(AXTextRangeReader.windowRange(around: 10, radius: radius, characterCount: nil) == 0..<2_010)
    }

    @Test func emptyElementGivesAnEmptyWindow() {
        #expect(AXTextRangeReader.windowRange(around: 0, radius: radius, characterCount: 0).isEmpty)
    }
}

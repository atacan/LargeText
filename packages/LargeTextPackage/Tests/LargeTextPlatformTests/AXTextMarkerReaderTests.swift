import CoreGraphics
import LargeTextCore
import Testing
@testable import LargeTextPlatform

/// Pure parts of the web path: the attribute choice per unit, the Gecko fallback and the geometry rules.
@Suite struct AXTextMarkerReaderTests {
    typealias Attempt = AXTextMarkerReader.RangeAttempt

    static let sentenceRange = "AXSentenceTextMarkerRangeForTextMarker"
    static let paragraphRange = "AXParagraphTextMarkerRangeForTextMarker"
    static let lineRange = "AXLineTextMarkerRangeForTextMarker"
    static let allRanges: Set<String> = [sentenceRange, paragraphRange, lineRange]

    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: - Attribute per granularity

    @Test func eachUnitUsesItsOwnRangeAttribute() {
        #expect(AXTextMarkerReader.rangeAttempts(for: .sentence, supported: Self.allRanges).first
            == Attempt(attribute: Self.sentenceRange, segmentsLocally: false))
        #expect(AXTextMarkerReader.rangeAttempts(for: .paragraph, supported: Self.allRanges)
            == [Attempt(attribute: Self.paragraphRange, segmentsLocally: false)])
        #expect(AXTextMarkerReader.rangeAttempts(for: .line, supported: Self.allRanges)
            == [Attempt(attribute: Self.lineRange, segmentsLocally: false)])
    }

    /// An empty sentence falls through to the paragraph, then the line, both cut down locally.
    @Test func sentenceFallsBackToParagraphThenLine() {
        #expect(AXTextMarkerReader.rangeAttempts(for: .sentence, supported: Self.allRanges) == [
            Attempt(attribute: Self.sentenceRange, segmentsLocally: false),
            Attempt(attribute: Self.paragraphRange, segmentsLocally: true),
            Attempt(attribute: Self.lineRange, segmentsLocally: true),
        ])
    }

    /// Gecko lists no sentence ranges: the paragraph is the first attempt, with no call for the sentence.
    @Test func unsupportedRangesAreNeverTried() {
        #expect(AXTextMarkerReader.rangeAttempts(for: .sentence, supported: [Self.paragraphRange, Self.lineRange]) == [
            Attempt(attribute: Self.paragraphRange, segmentsLocally: true),
            Attempt(attribute: Self.lineRange, segmentsLocally: true),
        ])
        #expect(AXTextMarkerReader.rangeAttempts(for: .sentence, supported: [Self.lineRange])
            == [Attempt(attribute: Self.lineRange, segmentsLocally: true)])
        #expect(AXTextMarkerReader.rangeAttempts(for: .paragraph, supported: [Self.sentenceRange, Self.lineRange]).isEmpty)
        #expect(AXTextMarkerReader.rangeAttempts(for: .sentence, supported: []).isEmpty)
    }

    /// Stage 0 copies these from a web area found by walking up, so every attribute the reader calls is in it.
    @Test func stageZeroCopiesEveryRangeAttribute() {
        #expect(Self.allRanges.isSubset(of: AXTextMarkerReader.parameterizedAttributes))
        #expect(AXTextMarkerReader.unitRequirements.isSubset(of: AXTextMarkerReader.parameterizedAttributes))
        #expect(AXTextMarkerReader.selectionRequirements.isSubset(of: AXTextMarkerReader.parameterizedAttributes))
    }

    // MARK: - Gecko fallback (R5)

    @Test func paragraphIsCutToTheSentenceAtThePointerOffset() {
        let paragraph = "First one. Second one here. Third."
        #expect(AXTextMarkerReader.sentence(in: paragraph, pointerOffset: 0) == "First one.")
        #expect(AXTextMarkerReader.sentence(in: paragraph, pointerOffset: 15) == "Second one here.")
        #expect(AXTextMarkerReader.sentence(in: paragraph, pointerOffset: 30) == "Third.")
    }

    @Test func offsetOnTheSpaceAfterASentenceBelongsToIt() {
        // Offset 10 is the space after "First one.".
        #expect(AXTextMarkerReader.sentence(in: "First one. Second.", pointerOffset: 10) == "First one.")
    }

    @Test func offsetOutsideTheTextIsClamped() {
        let paragraph = "First one. Last one."
        #expect(AXTextMarkerReader.sentence(in: paragraph, pointerOffset: 500) == "Last one.")
        #expect(AXTextMarkerReader.sentence(in: paragraph, pointerOffset: -3) == "First one.")
    }

    /// Without the start-marker attributes the offset is unknown: the whole paragraph is larger than a
    /// sentence, but never the wrong text.
    @Test func unknownOffsetKeepsTheWholeText() {
        #expect(AXTextMarkerReader.sentence(in: "One. Two.", pointerOffset: nil) == "One. Two.")
    }

    @Test func blankTextHasNoSentence() {
        #expect(AXTextMarkerReader.sentence(in: " \n ", pointerOffset: 1) == nil)
        #expect(AXTextMarkerReader.sentence(in: " \n ", pointerOffset: nil) == nil)
    }

    @Test func offsetsAreUTF16() {
        // "😀" is two UTF-16 units, so "Second." starts at offset 10.
        #expect(AXTextMarkerReader.sentence(in: "First 😀. Second.", pointerOffset: 11) == "Second.")
    }

    // MARK: - Geometry

    /// Marker bounds come back top-left global, like `pointer.global`; the shown frame is AppKit.
    @Test func markerBoundsAreComparedGloballyAndShownInAppKit() {
        let bounds = CGRect(x: 100, y: 50, width: 300, height: 40)
        let pointer = AXGeometry.pointerSample(appKit: CGPoint(x: 150, y: 830), primaryScreenFrame: primary)

        #expect(pointer.global == CGPoint(x: 150, y: 70))
        #expect(AXTextMarkerReader.isUnderPointer(globalBounds: bounds, pointer: pointer))
        #expect(AXGeometry.appKitRect(globalRect: bounds, primaryScreenFrame: primary)
            == CGRect(x: 100, y: 810, width: 300, height: 40))
    }

    @Test func markerBoundsOnASecondaryScreenAboveThePrimary() {
        let bounds = CGRect(x: -1820, y: -980, width: 200, height: 30)
        let pointer = AXGeometry.pointerSample(appKit: CGPoint(x: -1700, y: 1860), primaryScreenFrame: primary)

        #expect(AXTextMarkerReader.isUnderPointer(globalBounds: bounds, pointer: pointer))
        #expect(AXGeometry.appKitRect(globalRect: bounds, primaryScreenFrame: primary)
            == CGRect(x: -1820, y: 1850, width: 200, height: 30))
    }

    // MARK: - Selection and unit under the pointer

    @Test func selectionIsKeptOnlyWithThePointerInsideItsBounds() {
        let bounds = CGRect(x: 100, y: 50, width: 300, height: 40)
        let inside = PointerSample(appKit: .zero, global: CGPoint(x: 120, y: 60))
        let below = PointerSample(appKit: .zero, global: CGPoint(x: 120, y: 95))
        let left = PointerSample(appKit: .zero, global: CGPoint(x: 99, y: 60))

        #expect(AXTextMarkerReader.isUnderPointer(globalBounds: bounds, pointer: inside))
        #expect(!AXTextMarkerReader.isUnderPointer(globalBounds: bounds, pointer: below))
        #expect(!AXTextMarkerReader.isUnderPointer(globalBounds: bounds, pointer: left))
    }

    /// A caret is a collapsed selection range: its bounds have no width and never hold the pointer.
    @Test func collapsedSelectionIsNeverUnderThePointer() {
        let caret = CGRect(x: 120, y: 50, width: 0, height: 20)
        let pointer = PointerSample(appKit: .zero, global: CGPoint(x: 120, y: 60))

        #expect(!AXTextMarkerReader.isUnderPointer(globalBounds: caret, pointer: pointer))
    }
}

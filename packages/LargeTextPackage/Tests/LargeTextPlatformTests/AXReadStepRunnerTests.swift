import ApplicationServices
import CoreGraphics
import LargeTextCore
import Testing
@testable import LargeTextPlatform

/// Pure parts of stage 0 and the step executors: skip logic, web-area decision, merging and error mapping.
@Suite struct AXReadStepRunnerTests {
    let nativeTextView: Set<String> = [
        kAXRangeForPositionParameterizedAttribute,
        kAXStringForRangeParameterizedAttribute,
        kAXBoundsForRangeParameterizedAttribute,
    ]

    // MARK: - Step skipping

    @Test func textStepsRunWhenTheirAttributesAreSupported() {
        #expect(AXReadStepRunner.canRun(.selection, supportedParameterized: nativeTextView))
        #expect(AXReadStepRunner.canRun(.textWindow, supportedParameterized: nativeTextView))
    }

    @Test func textStepsAreSkippedWithoutTheirAttributes() {
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: []))
        #expect(!AXReadStepRunner.canRun(.textWindow, supportedParameterized: []))
        // A window needs both the position lookup and the string fetch.
        #expect(!AXReadStepRunner.canRun(.textWindow, supportedParameterized: [kAXStringForRangeParameterizedAttribute]))
        // The selection is kept only if the pointer is inside its bounds.
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: [kAXStringForRangeParameterizedAttribute]))
    }

    @Test func valueAndWalkNeedNoParameterizedAttributes() {
        #expect(AXReadStepRunner.canRun(.value, supportedParameterized: []))
        #expect(AXReadStepRunner.canRun(.walk, supportedParameterized: []))
    }

    @Test func textMarkersAndDoneNeverRun() {
        let everything = nativeTextView.union(["AXTextMarkerForPosition", "AXStringForTextMarkerRange"])
        #expect(!AXReadStepRunner.canRun(.textMarkers, supportedParameterized: everything))
        #expect(!AXReadStepRunner.canRun(.done, supportedParameterized: everything))
    }

    // MARK: - Value step guard

    @Test func valueIsFetchedOnlyWhenShort() {
        #expect(AXValueReader.shouldFetch(characterCount: 12, role: "AXStaticText", limit: 500))
        #expect(AXValueReader.shouldFetch(characterCount: 500, role: "AXTextArea", limit: 500))
        #expect(!AXValueReader.shouldFetch(characterCount: 1_000_000, role: "AXTextArea", limit: 500))
        #expect(!AXValueReader.shouldFetch(characterCount: 501, role: "AXStaticText", limit: 500))
    }

    @Test func valueWithoutACountIsSkippedOnlyForTextAreas() {
        #expect(AXValueReader.shouldFetch(characterCount: nil, role: "AXStaticText", limit: 500))
        #expect(AXValueReader.shouldFetch(characterCount: nil, role: nil, limit: 500))
        #expect(!AXValueReader.shouldFetch(characterCount: nil, role: "AXTextArea", limit: 500))
    }

    // MARK: - Web area

    @Test func textMarkerSupportMeansWebArea() {
        #expect(AXStageZeroReader.isWebArea(supportedParameterized: ["AXTextMarkerForPosition"], role: "AXStaticText"))
        #expect(!AXStageZeroReader.isWebArea(supportedParameterized: nativeTextView, role: "AXTextArea"))
    }

    @Test func theWebAreaItselfIsWebArea() {
        #expect(AXStageZeroReader.isWebArea(supportedParameterized: [], role: "AXWebArea"))
        #expect(!AXStageZeroReader.isWebArea(supportedParameterized: [], role: nil))
    }

    @Test func onlyBrowsersAndElectronWalkUpForAWebArea() {
        #expect(AXStageZeroReader.shouldWalkUpForWebArea(isWebArea: false, family: .chromiumBrowser))
        #expect(AXStageZeroReader.shouldWalkUpForWebArea(isWebArea: false, family: .otherBrowser))
        #expect(AXStageZeroReader.shouldWalkUpForWebArea(isWebArea: false, family: .electron))
        #expect(!AXStageZeroReader.shouldWalkUpForWebArea(isWebArea: false, family: .native))
        #expect(!AXStageZeroReader.shouldWalkUpForWebArea(isWebArea: true, family: .chromiumBrowser))
    }

    // MARK: - Merging

    @Test func outputsMergeOnlyTheirOwnFields() {
        var candidates = ReadCandidates(pid: 1, role: "AXTextArea", characterCount: 10)
        let window = TextWindow(text: "Hello", start: 3, indexAtPointer: 4)
        let span = TextSpan(text: "llo", frame: CGRect(x: 0, y: 0, width: 10, height: 10))

        AXValueReader.Output(value: "v").merge(into: &candidates)
        AXTextRangeReader.SelectionOutput(selection: span).merge(into: &candidates)
        AXTextRangeReader.WindowOutput(window: window).merge(into: &candidates)

        #expect(candidates == ReadCandidates(
            pid: 1, role: "AXTextArea", value: "v", characterCount: 10, selection: span, window: window
        ))
    }

    @Test func walkOutputAppendsAndNeverClearsHidden() {
        var candidates = ReadCandidates(pid: 1, childTexts: ["a"], ancestorLabel: "first", hiddenEncountered: true)

        AXElementWalker.Output(childTexts: ["b", "c"], ancestorLabel: "second", hiddenEncountered: false)
            .merge(into: &candidates)

        #expect(candidates.childTexts == ["a", "b", "c"])
        #expect(candidates.ancestorLabel == "first")
        #expect(candidates.hiddenEncountered)
    }

    // MARK: - Error policy

    @Test func onlyCannotCompleteAndAPIDisabledAbort() throws {
        #expect(try AXReadError.check(.success))
        #expect(try !AXReadError.check(.attributeUnsupported))
        #expect(try !AXReadError.check(.noValue))
        #expect(try !AXReadError.check(.parameterizedAttributeUnsupported))
        #expect(try !AXReadError.check(.invalidUIElement))
        #expect(throws: AXReadError.cannotComplete) { try AXReadError.check(.cannotComplete) }
        #expect(throws: AXReadError.apiDisabled) { try AXReadError.check(.apiDisabled) }
    }
}

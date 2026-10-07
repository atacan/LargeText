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
    let webContent: Set<String> = [
        "AXTextMarkerForPosition",
        "AXSentenceTextMarkerRangeForTextMarker",
        "AXStringForTextMarkerRange",
        "AXBoundsForTextMarkerRange",
    ]

    // MARK: - Step skipping

    @Test func textStepsRunWhenTheirAttributesAreSupported() {
        #expect(AXReadStepRunner.canRun(.selection, supportedParameterized: nativeTextView, webArea: false))
        #expect(AXReadStepRunner.canRun(.textWindow, supportedParameterized: nativeTextView, webArea: false))
    }

    @Test func textStepsAreSkippedWithoutTheirAttributes() {
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: [], webArea: false))
        #expect(!AXReadStepRunner.canRun(.textWindow, supportedParameterized: [], webArea: false))
        // A window needs both the position lookup and the string fetch.
        #expect(!AXReadStepRunner.canRun(.textWindow, supportedParameterized: [kAXStringForRangeParameterizedAttribute], webArea: false))
        // The selection is kept only if the pointer is inside its bounds.
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: [kAXStringForRangeParameterizedAttribute], webArea: false))
    }

    @Test func valueAndWalkNeedNoParameterizedAttributes() {
        #expect(AXReadStepRunner.canRun(.value, supportedParameterized: [], webArea: false))
        #expect(AXReadStepRunner.canRun(.walk, supportedParameterized: [], webArea: false))
    }

    @Test func doneNeverRuns() {
        let everything = nativeTextView.union(AXTextMarkerReader.parameterizedAttributes)
        #expect(!AXReadStepRunner.canRun(.done, supportedParameterized: everything, webArea: false))
        #expect(!AXReadStepRunner.canRun(.done, supportedParameterized: everything, webArea: true))
    }

    // MARK: - Web steps

    @Test func textMarkersNeedTheMarkerAtThePointerAndTheRangeString() {
        #expect(AXReadStepRunner.requiredParameterized(for: .textMarkers, webArea: true)
            == ["AXTextMarkerForPosition", "AXStringForTextMarkerRange"])
        #expect(AXReadStepRunner.canRun(.textMarkers, supportedParameterized: webContent, webArea: true))
        #expect(!AXReadStepRunner.canRun(.textMarkers, supportedParameterized: ["AXStringForTextMarkerRange"], webArea: true))
        #expect(!AXReadStepRunner.canRun(.textMarkers, supportedParameterized: nativeTextView, webArea: true))
    }

    @Test func webSelectionNeedsMarkerBoundsAndStringNotTheNativeOnes() {
        #expect(AXReadStepRunner.requiredParameterized(for: .selection, webArea: true)
            == ["AXBoundsForTextMarkerRange", "AXStringForTextMarkerRange"])
        #expect(AXReadStepRunner.canRun(.selection, supportedParameterized: webContent, webArea: true))
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: nativeTextView, webArea: true))
        // Without bounds the pointer-inside rule can't be checked, so the step is skipped.
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: ["AXStringForTextMarkerRange"], webArea: true))
    }

    @Test func nativeSelectionIsUnchangedOutsideWebAreas() {
        #expect(AXReadStepRunner.requiredParameterized(for: .selection, webArea: false)
            == [kAXBoundsForRangeParameterizedAttribute, kAXStringForRangeParameterizedAttribute])
        #expect(!AXReadStepRunner.canRun(.selection, supportedParameterized: webContent, webArea: false))
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

    @Test func markerUnitMergesOnlyItsGranularity() {
        let paragraph = TextSpan(text: "A paragraph. Two sentences.")
        let sentence = TextSpan(text: "Two sentences.", frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        var candidates = ReadCandidates(pid: 1, markerUnits: [.paragraph: paragraph], webArea: true)

        AXTextMarkerReader.UnitOutput(granularity: .sentence, unit: sentence).merge(into: &candidates)
        #expect(candidates.markerUnits == [.paragraph: paragraph, .sentence: sentence])

        AXTextMarkerReader.UnitOutput(granularity: .line).merge(into: &candidates)
        #expect(candidates.markerUnits == [.paragraph: paragraph, .sentence: sentence])
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

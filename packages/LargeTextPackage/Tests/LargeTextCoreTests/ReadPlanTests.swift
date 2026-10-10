import Testing
import LargeTextCore

struct ReadPlanTests {
    /// Runs the extraction loop the way Platform does: ask, run (`fill` merges what the step found, or
    /// nothing for an unsupported or failed step), record the attempt, ask again.
    static func steps(
        from start: ReadCandidates,
        granularity: ReadGranularity = .sentence,
        fill: (ReadStep, inout ReadCandidates) -> Void = { _, _ in }
    ) -> [ReadStep] {
        var candidates = start
        var steps: [ReadStep] = []
        for _ in 0..<10 {
            let step = ReadPlan.next(after: candidates, granularity: granularity, policy: .standard)
            guard step != .done else { return steps }
            steps.append(step)
            fill(step, &candidates)
            candidates.attemptedSteps.insert(step)
        }
        Issue.record("ReadPlan did not reach .done: \(steps)")
        return steps
    }

    static func element(_ role: String?, count: Int? = nil, webArea: Bool = false) -> ReadCandidates {
        ReadCandidates(pid: 1, role: role, characterCount: count, webArea: webArea)
    }

    // MARK: - Native

    @Test func shortNativeStaticTextFetchesItsValueThenStops() {
        let steps = Self.steps(from: Self.element("AXStaticText")) { step, candidates in
            if step == .value { candidates.value = "Save changes?" }
        }

        #expect(steps == [.value])
    }

    @Test func buttonWithADescriptionFetchesItsValueThenStops() {
        var button = Self.element("AXButton")
        button.description = "Soniox"

        #expect(Self.steps(from: button) == [.value])
        #expect(Self.steps(from: button) { step, candidates in
            if step == .value { candidates.value = "Selected" }
        } == [.value])
    }

    @Test func checkBoxWithATitleNeverFetchesItsValue() {
        var checkBox = Self.element("AXCheckBox")
        checkBox.title = "Enabled"

        #expect(Self.steps(from: checkBox) == [])
    }

    @Test func hugeTextAreaNeverFetchesItsValue() {
        #expect(Self.steps(from: Self.element("AXTextArea", count: 1_000_000)) == [.selection, .textWindow])
    }

    @Test func textInputOfUnknownLengthNeverFetchesItsValue() {
        #expect(Self.steps(from: Self.element("AXTextField")) == [.selection, .textWindow])
    }

    @Test func textAreaStopsOnceTheWindowHasAUnit() {
        let steps = Self.steps(from: Self.element("AXTextArea", count: 1_000_000)) { step, candidates in
            if step == .textWindow {
                candidates.window = TextWindow(text: "One. Two.", start: 500, indexAtPointer: 501)
            }
        }

        #expect(steps == [.selection, .textWindow])
    }

    @Test func selectionUnderThePointerEndsThePlan() {
        let steps = Self.steps(from: Self.element("AXTextArea", count: 1_000_000)) { step, candidates in
            if step == .selection { candidates.selection = TextSpan(text: "picked") }
        }

        #expect(steps == [.selection])
    }

    @Test func shortTextFieldFallsBackToItsValueWhenTheWindowFails() {
        #expect(Self.steps(from: Self.element("AXTextField", count: 20)) == [.selection, .textWindow, .value])
    }

    @Test func valueAtTheLimitIsAllowedAndOneOverIsNot() {
        #expect(Self.steps(from: Self.element("AXTextField", count: 500)).contains(.value))
        #expect(!Self.steps(from: Self.element("AXTextField", count: 501)).contains(.value))
        #expect(!Self.steps(from: Self.element("AXStaticText", count: 501)).contains(.value))
    }

    @Test func emptyGroupIsWalked() {
        #expect(Self.steps(from: Self.element("AXGroup")) == [.walk])
    }

    @Test(arguments: ["AXCheckBox", "AXSlider", "AXLink"])
    func nonTextValuesAreNeverFetched(role: String) {
        #expect(!Self.steps(from: Self.element(role)).contains(.value))
    }

    @Test func linkIsWalkedForItsText() {
        #expect(Self.steps(from: Self.element("AXLink")) == [.walk])
    }

    @Test func labelledContainerIsNotWalked() {
        var group = Self.element("AXGroup")
        group.description = "Toolbar"

        #expect(Self.steps(from: group) == [])
    }

    @Test func cellTriesItsValueThenWalks() {
        #expect(Self.steps(from: Self.element("AXCell")) == [.value, .walk])
    }

    // MARK: - Web

    @Test func shortStaticTextInAWebAreaUsesTextMarkersNotItsValue() {
        let steps = Self.steps(from: Self.element("AXStaticText", count: 4, webArea: true)) { step, candidates in
            if step == .textMarkers {
                candidates.markerUnits[.sentence] = TextSpan(text: "Click here to continue.")
            }
        }

        #expect(steps == [.selection, .textMarkers])
    }

    @Test func textMarkersAnswerTheRequestedUnit() {
        var candidates = Self.element("AXStaticText", webArea: true)
        candidates.attemptedSteps = [.selection]
        candidates.markerUnits[.sentence] = TextSpan(text: "A sentence.")

        #expect(ReadPlan.next(after: candidates, granularity: .sentence, policy: .standard) == .done)
        #expect(ReadPlan.next(after: candidates, granularity: .paragraph, policy: .standard) == .textMarkers)
    }

    @Test func webStaticTextFallsBackToItsValueWhenMarkersFail() {
        #expect(Self.steps(from: Self.element("AXStaticText", webArea: true)) == [.selection, .textMarkers, .value])
    }

    // MARK: - Termination and hidden content

    @Test(arguments: [
        ReadCandidates(pid: 1, role: "AXTextArea", characterCount: 30),
        ReadCandidates(pid: 1, role: "AXGroup", webArea: true),
        ReadCandidates(pid: 1, role: "AXCell"),
        ReadCandidates(pid: 1),
    ])
    func unsupportedOrFailedStepsAreNeverRepeated(candidates: ReadCandidates) {
        let steps = Self.steps(from: candidates)

        #expect(Set(steps).count == steps.count)
    }

    @Test func neverReturnsAnAttemptedStep() {
        var candidates = Self.element("AXTextArea", count: 10)
        candidates.attemptedSteps = [.selection, .textWindow, .value, .textMarkers, .walk]

        #expect(ReadPlan.next(after: candidates, granularity: .sentence, policy: .standard) == .done)
    }

    @Test func hiddenContentFetchesNothing() {
        var secure = Self.element("AXTextField", count: 8)
        secure.subrole = "AXSecureTextField"
        var walked = Self.element("AXGroup")
        walked.hiddenEncountered = true
        var denylisted = Self.element("AXStaticText")
        denylisted.bundleIdentifier = "com.1password.1password"

        for candidates in [secure, walked, denylisted] {
            #expect(ReadPlan.next(after: candidates, granularity: .sentence, policy: .standard) == .done)
        }
    }
}

import CoreGraphics
import Testing
import LargeTextCore

/// The §3.3 ladder, rung by rung.
struct ReadTextChooserTests {
    static let elementFrame = CGRect(x: 10, y: 20, width: 300, height: 100)

    static func candidates(role: String? = "AXStaticText", _ configure: (inout ReadCandidates) -> Void = { _ in }) -> ReadCandidates {
        var candidates = ReadCandidates(pid: 1, bundleIdentifier: "com.apple.TextEdit", role: role, elementFrame: elementFrame)
        configure(&candidates)
        return candidates
    }

    static func choose(_ candidates: ReadCandidates, granularity: ReadGranularity = .sentence) -> ReadResult {
        ReadTextChooser.choose(from: candidates, granularity: granularity, policy: .standard, appName: "TextEdit")
    }

    static func text(_ result: ReadResult) -> ReadText? {
        guard case .text(let text) = result else { return nil }
        return text
    }

    // MARK: - 1. Hidden

    @Test func secureSubroleIsHiddenEvenWithText() {
        let result = Self.choose(Self.candidates(role: "AXTextField") {
            $0.subrole = "AXSecureTextField"
            $0.value = "hunter2"
            $0.title = "Password"
        })

        #expect(result == .hidden)
    }

    @Test func secureRoleIsHidden() {
        #expect(Self.choose(Self.candidates(role: "AXSecureTextField")) == .hidden)
    }

    @Test func secureElementFoundDuringAWalkHidesEverything() {
        let result = Self.choose(Self.candidates(role: "AXGroup") {
            $0.childTexts = ["Username", "alice"]
            $0.hiddenEncountered = true
        })

        #expect(result == .hidden)
    }

    @Test func denylistedAppIsHiddenAsDefenceInDepth() {
        let result = Self.choose(Self.candidates {
            $0.bundleIdentifier = "com.bitwarden.desktop"
            $0.value = "482 913"
        })

        #expect(result == .hidden)
    }

    // MARK: - 2. Selection

    @Test func nativeSelectionWinsWithItsOwnFrame() throws {
        let selectionFrame = CGRect(x: 50, y: 60, width: 80, height: 20)
        let result = Self.choose(Self.candidates(role: "AXTextArea") {
            $0.selection = TextSpan(text: "  chosen words \n", frame: selectionFrame)
            $0.window = TextWindow(text: "Some sentence.", start: 0, indexAtPointer: 2)
            $0.title = "Document"
        })

        let text = try #require(Self.text(result))
        #expect(text.text == "chosen words")
        #expect(text.source == .selection)
        #expect(text.sourceFrame == selectionFrame)
        #expect(text.window == nil)
        #expect(text.appName == "TextEdit")
        #expect(text.bundleIdentifier == "com.apple.TextEdit")
    }

    @Test func webSelectionWinsOverTheMarkerUnit() throws {
        let result = Self.choose(Self.candidates {
            $0.webArea = true
            $0.selection = TextSpan(text: "selected on the page")
            $0.markerUnits[.sentence] = TextSpan(text: "The whole sentence.")
        })

        let text = try #require(Self.text(result))
        #expect(text.text == "selected on the page")
        #expect(text.source == .selection)
        #expect(text.sourceFrame == Self.elementFrame)
    }

    @Test func blankSelectionIsSkipped() throws {
        let result = Self.choose(Self.candidates {
            $0.selection = TextSpan(text: " \n ")
            $0.value = "Label text"
        })

        #expect(try #require(Self.text(result)).source == .element)
    }

    // MARK: - 3. Unit

    @Test func webUnitUsesTheRequestedGranularityAndItsBounds() throws {
        let sentenceFrame = CGRect(x: 1, y: 2, width: 3, height: 4)
        let result = Self.choose(Self.candidates {
            $0.webArea = true
            $0.markerUnits = [
                .sentence: TextSpan(text: "Click here to continue.", frame: sentenceFrame),
                .paragraph: TextSpan(text: "Welcome. Click here to continue."),
            ]
            $0.value = "here"
        })

        let text = try #require(Self.text(result))
        #expect(text.text == "Click here to continue.")
        #expect(text.source == .unit)
        #expect(text.granularity == .sentence)
        #expect(text.sourceFrame == sentenceFrame)
        #expect(text.window == nil)
    }

    /// Marker bounds are optional (`AXBoundsForTextMarkerRange` unsupported): the highlight falls back to the
    /// element.
    @Test func webUnitWithoutBoundsUsesTheElementFrame() throws {
        let result = Self.choose(Self.candidates {
            $0.webArea = true
            $0.markerUnits[.sentence] = TextSpan(text: "No bounds for this one.")
            $0.value = "this"
        })

        let text = try #require(Self.text(result))
        #expect(text.source == .unit)
        #expect(text.sourceFrame == Self.elementFrame)
        #expect(text.window == nil)
    }

    /// Only the requested unit counts; a paragraph is never shown for a sentence request.
    @Test func webUnitOfAnotherGranularityFallsThroughToTheValue() throws {
        let result = Self.choose(Self.candidates {
            $0.webArea = true
            $0.markerUnits[.paragraph] = TextSpan(text: "A whole paragraph. Of two sentences.")
            $0.value = "Short value"
        })

        let text = try #require(Self.text(result))
        #expect(text.text == "Short value")
        #expect(text.source == .element)
    }

    @Test func nativeUnitIsSegmentedFromTheWindowAndKeepsIt() throws {
        let window = TextWindow(text: "First one. Second one here. Third.", start: 1_000, indexAtPointer: 1_015)
        let result = Self.choose(Self.candidates(role: "AXTextArea") { $0.window = window })

        let text = try #require(Self.text(result))
        #expect(text.text == "Second one here.")
        #expect(text.source == .unit)
        #expect(text.window == window)
        #expect(text.sourceFrame == Self.elementFrame)
    }

    // MARK: - 4. Element text

    @Test func shortValueIsTheElementText() throws {
        let result = Self.choose(Self.candidates { $0.value = "  Saved 2 minutes ago  " })

        let text = try #require(Self.text(result))
        #expect(text.text == "Saved 2 minutes ago")
        #expect(text.source == .element)
    }

    @Test func longValueIsNotUsedAsElementText() throws {
        let result = Self.choose(Self.candidates {
            $0.value = String(repeating: "a", count: 501)
            $0.title = "Notes"
        })

        let text = try #require(Self.text(result))
        #expect(text.text == "Notes")
        #expect(text.source == .label)
    }

    // MARK: - 5. Label

    @Test func labelOrderIsTitleDescriptionHelpPlaceholder() throws {
        func label(_ configure: (inout ReadCandidates) -> Void) throws -> String {
            try #require(Self.text(Self.choose(Self.candidates(role: "AXButton", configure)))).text
        }

        #expect(try label { $0.title = "T"; $0.description = "D"; $0.help = "H"; $0.placeholder = "P" } == "T")
        #expect(try label { $0.title = " "; $0.description = "D"; $0.help = "H"; $0.placeholder = "P" } == "D")
        #expect(try label { $0.help = "H"; $0.placeholder = "P" } == "H")
        #expect(try label { $0.placeholder = "P" } == "P")
    }

    // MARK: - 6. Walk

    @Test func walkJoinsChildTextsVerbatim() throws {
        let result = Self.choose(Self.candidates(role: "AXCell") {
            $0.childTexts = ["  Report.pdf ", "", "Today at 09:41"]
            $0.ancestorLabel = "Files"
        })

        let text = try #require(Self.text(result))
        #expect(text.text == "Report.pdf\nToday at 09:41")
        #expect(text.source == .walk)
    }

    @Test func walkFallsBackToTheAncestorLabel() throws {
        let result = Self.choose(Self.candidates(role: "AXGroup") { $0.ancestorLabel = "Sidebar" })

        let text = try #require(Self.text(result))
        #expect(text.text == "Sidebar")
        #expect(text.source == .walk)
    }

    // MARK: - 7. Nothing; formatting

    @Test func nothingFound() {
        #expect(Self.choose(Self.candidates(role: "AXGroup") { $0.childTexts = ["  "] }) == .nothing)
    }

    @Test func textIsVerbatimInsideAndCappedWithAnEllipsis() throws {
        let inner = "Line one\n\n  indented\ttab"
        let short = try #require(Self.text(Self.choose(Self.candidates { $0.value = "\n \(inner) \n" })))
        #expect(short.text == inner)

        let long = String(repeating: "word ", count: 2_000)
        let capped = try #require(Self.text(Self.choose(Self.candidates(role: "AXTextArea") {
            $0.selection = TextSpan(text: long)
        })))
        #expect(capped.text.count == ReadPolicy.standard.maxCharacters)
        #expect(capped.text.hasSuffix("…"))
    }
}

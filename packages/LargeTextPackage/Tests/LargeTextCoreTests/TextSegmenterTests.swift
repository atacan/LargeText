import Foundation
import Testing
import LargeTextCore

struct TextSegmenterTests {
    static func window(_ text: String, start: Int = 1_000, pointerAt local: Int) -> TextWindow {
        TextWindow(text: text, start: start, indexAtPointer: start + local)
    }

    /// The local UTF-16 offset of `part` in `text`.
    static func offset(of part: String, in text: String) -> Int {
        (text as NSString).range(of: part).location
    }

    // MARK: - Units and offsets

    @Test func sentenceAtThePointerMapsBackToElementOffsets() {
        let window = Self.window("First one. Second one here. Third.", pointerAt: 15)

        #expect(TextSegmenter.unit(.sentence, in: window) == TextSegment(text: "Second one here.", range: 1_011..<1_027))
    }

    @Test func pointerOnTrailingSpaceBelongsToTheSentenceBefore() {
        let window = Self.window("First one. Second.", pointerAt: 10)

        #expect(TextSegmenter.unit(.sentence, in: window)?.text == "First one.")
    }

    @Test func paragraphSpansItsSentences() {
        let text = "Intro.\nOne sentence. Another one.\nOutro."
        let window = Self.window(text, pointerAt: Self.offset(of: "Another", in: text))

        let paragraph = TextSegmenter.unit(.paragraph, in: window)
        #expect(paragraph?.text == "One sentence. Another one.")
        #expect(paragraph?.range.lowerBound == 1_007)
    }

    @Test func lineStopsAtALineSeparatorButTheParagraphDoesNot() {
        let text = "Top line\u{2028}bottom line"
        let window = Self.window(text, pointerAt: Self.offset(of: "bottom", in: text))

        #expect(TextSegmenter.unit(.line, in: window)?.text == "bottom line")
        #expect(TextSegmenter.unit(.paragraph, in: window)?.text == text)
    }

    @Test func resegmentsAStoredWindowToThePinnedUnit() {
        let text = "Heading\n\nFirst sentence. Second sentence is longer.\n\nNext."
        let window = Self.window(text, pointerAt: Self.offset(of: "longer", in: text))

        #expect(TextSegmenter.unit(.sentence, in: window)?.text == "Second sentence is longer.")
        #expect(TextSegmenter.unit(.paragraph, in: window)?.text == "First sentence. Second sentence is longer.")
    }

    // MARK: - Separators and UTF-16

    @Test func crlfIsASingleSeparatorAndNeverPartOfTheUnit() {
        let text = "One line.\r\nTwo line.\r\n"
        let two = Self.offset(of: "Two", in: text)

        #expect(TextSegmenter.unit(.line, in: Self.window(text, pointerAt: two)) == TextSegment(text: "Two line.", range: 1_011..<1_020))
        // Pointer on the \r or the \n: still the first line.
        #expect(TextSegmenter.unit(.line, in: Self.window(text, pointerAt: 9))?.text == "One line.")
        #expect(TextSegmenter.unit(.line, in: Self.window(text, pointerAt: 10))?.text == "One line.")
        #expect(TextSegmenter.unit(.paragraph, in: Self.window(text, pointerAt: two))?.text == "Two line.")
    }

    @Test func emojiAndSurrogatePairsUseUTF16Offsets() throws {
        let text = "👋🏽 Hi there. 👨‍👩‍👧 Family time. End."
        let family = "👨‍👩‍👧 Family time."
        let start = Self.offset(of: family, in: text)
        // Inside the family emoji, between the halves of a surrogate pair.
        let window = Self.window(text, start: 40, pointerAt: start + 3)

        let unit = try #require(TextSegmenter.unit(.sentence, in: window))
        #expect(unit.text == family)
        #expect(unit.range == (40 + start)..<(40 + start + family.utf16.count))
    }

    // MARK: - Window edges

    @Test func pointerAtTheWindowStartAndEnd() {
        let text = "ond half of a cut sentence. Last one"
        #expect(TextSegmenter.unit(.sentence, in: Self.window(text, start: 5_000, pointerAt: 0))
            == TextSegment(text: "ond half of a cut sentence.", range: 5_000..<5_027))
        // Just past the last character, e.g. at the end of the element.
        #expect(TextSegmenter.unit(.sentence, in: Self.window(text, start: 5_000, pointerAt: text.utf16.count))?.text == "Last one")
    }

    @Test func pointerOutsideTheWindowOrAnEmptyWindowFindsNothing() {
        let text = "Some text."
        #expect(TextSegmenter.unit(.sentence, in: Self.window(text, pointerAt: -1)) == nil)
        #expect(TextSegmenter.unit(.sentence, in: Self.window(text, pointerAt: text.utf16.count + 1)) == nil)
        #expect(TextSegmenter.unit(.sentence, in: Self.window("", pointerAt: 0)) == nil)
    }

    @Test func pointerOnABlankLineFindsNothing() {
        let window = Self.window("A.\n\nB.", pointerAt: 3)

        #expect(TextSegmenter.unit(.paragraph, in: window) == nil)
    }

    // MARK: - Display text and the cap

    @Test func displayTextTrimsOnlyTheOuterWhitespace() {
        #expect(TextSegmenter.displayText("\n\t  a  b\n\nc \n", maxCharacters: 100) == "a  b\n\nc")
        #expect(TextSegmenter.displayText(" \n\t ", maxCharacters: 100) == nil)
    }

    @Test func capEndsInAnEllipsisWithinTheLimit() {
        #expect(TextSegmenter.displayText("abcdef", maxCharacters: 4) == "abc…")
        #expect(TextSegmenter.displayText("abcd", maxCharacters: 4) == "abcd")
    }

    @Test func capNeverSplitsAnEmoji() {
        let family = "👨‍👩‍👧"
        #expect(TextSegmenter.displayText(family + family + family, maxCharacters: 2) == family + "…")
    }
}

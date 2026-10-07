import Foundation

/// A unit of text found in a `TextWindow`.
package struct TextSegment: Equatable, Sendable {
    /// Verbatim, with only the outer whitespace trimmed. Not capped.
    package var text: String
    /// UTF-16 offsets of `text` in the element (not in the window).
    package var range: Range<Int>

    package init(text: String, range: Range<Int>) {
        self.text = text
        self.range = range
    }
}

/// Finds the sentence, line or paragraph at the pointer inside a native `TextWindow` and maps it back to
/// element offsets (§4.3). Pure; all offsets are UTF-16, as AX reports them.
package enum TextSegmenter {
    /// The unit containing `window.indexAtPointer`, or `nil` when the pointer is outside the window or on a
    /// unit that is only whitespace (e.g. a blank line between paragraphs).
    ///
    /// The window is cut from a longer element, so a unit touching one of its edges may itself be cut; it is
    /// returned as far as the window reaches.
    package static func unit(_ granularity: ReadGranularity, in window: TextWindow) -> TextSegment? {
        let string = window.text as NSString
        let length = string.length
        var index = window.indexAtPointer - window.start
        guard length > 0, (0...length).contains(index) else { return nil }
        // A pointer just past the last character (e.g. at the end of a line) belongs to it.
        index = min(index, length - 1)

        var found: NSRange?
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: length),
            options: [granularity.enumerationOption, .substringNotRequired]
        ) { _, substringRange, enclosingRange, stop in
            // The enclosing range includes the trailing spaces and separators, so a pointer on them still
            // belongs to the unit before.
            guard NSLocationInRange(index, enclosingRange) else { return }
            found = substringRange
            stop.pointee = true
        }
        guard let found, found.length > 0 else { return nil }

        guard let trimmed = trimmed(string.substring(with: found)) else { return nil }
        let start = window.start + found.location + trimmed.offsets.lowerBound
        return TextSegment(text: trimmed.text, range: start..<(start + trimmed.offsets.count))
    }

    /// The text as the reader shows it: verbatim, with only the outer whitespace trimmed, and capped at
    /// `maxCharacters` characters including a closing ellipsis. `nil` when nothing but whitespace is left.
    package static func displayText(_ text: String, maxCharacters: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Counted in `Character`s, so the cut never splits an emoji or a combining sequence.
        guard trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(max(maxCharacters - 1, 0))) + "…"
    }

    /// `text` without its leading and trailing whitespace, with the UTF-16 offsets of what is left;
    /// `nil` if it is all whitespace.
    private static func trimmed(_ text: String) -> (text: String, offsets: Range<Int>)? {
        let scalars = text.unicodeScalars
        let isText = { (scalar: Unicode.Scalar) in !CharacterSet.whitespacesAndNewlines.contains(scalar) }
        guard let first = scalars.firstIndex(where: isText), let last = scalars.lastIndex(where: isText) else {
            return nil
        }
        let end = scalars.index(after: last)
        let lower = text.utf16.distance(from: text.startIndex, to: first)
        let upper = text.utf16.distance(from: text.startIndex, to: end)
        return (String(scalars[first..<end]), lower..<upper)
    }
}

extension ReadGranularity {
    fileprivate var enumerationOption: NSString.EnumerationOptions {
        switch self {
        case .sentence: .bySentences
        case .line: .byLines
        case .paragraph: .byParagraphs
        }
    }
}

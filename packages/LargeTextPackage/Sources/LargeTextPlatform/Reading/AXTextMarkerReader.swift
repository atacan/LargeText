import ApplicationServices
import CoreGraphics
import LargeTextCore
import os

// Text markers are undocumented. They are the attributes VoiceOver relies on, and WebKit (Safari, Mail),
// Chromium (Chrome, Arc, Electron) and Gecko (Firefox) implement them on their `AXWebArea`. A marker or a
// marker range is an opaque `AXTextMarker` / `AXTextMarkerRange` CF value: it is only ever passed back as a
// parameter, never inspected.

/// The web path of the reader (§4.3): the selection and the unit at the pointer in web content, read with
/// text markers on the `AXWebArea` around the hit element.
///
/// The caller checks `supportedParameterized` first (`AXReadStepRunner.canRun`); each optional attribute is
/// checked again here and skipped without an AX call when it isn't listed. For a hit element that supports
/// text markers itself, its list stands in for the web area's: the engines list the same set on every
/// element. For one that doesn't, stage 0 adds the web area's marker attributes to the list.
///
/// Not `Sendable`: one instance per read, on the reader's queue. It remembers the web area it found, so the
/// `.selection` and `.textMarkers` steps of one read walk up only once.
package final class AXTextMarkerReader {
    package struct UnitOutput: ReadStepOutput {
        package var granularity: ReadGranularity
        package var unit: TextSpan?

        package init(granularity: ReadGranularity, unit: TextSpan? = nil) {
            self.granularity = granularity
            self.unit = unit
        }

        package func merge(into candidates: inout ReadCandidates) {
            candidates.markerUnits[granularity] = unit
        }
    }

    /// One marker-range attribute to try for a unit.
    package struct RangeAttempt: Equatable, Sendable {
        package var attribute: String
        /// The attribute returns a larger unit (a paragraph or line) that is cut down to the sentence at the
        /// pointer with `TextSegmenter` (R5: Gecko has no sentence ranges).
        package var segmentsLocally: Bool
    }

    package enum Attribute {
        static let textMarkerForPosition = "AXTextMarkerForPosition"
        static let sentenceRange = "AXSentenceTextMarkerRangeForTextMarker"
        static let paragraphRange = "AXParagraphTextMarkerRangeForTextMarker"
        static let lineRange = "AXLineTextMarkerRangeForTextMarker"
        static let string = "AXStringForTextMarkerRange"
        static let bounds = "AXBoundsForTextMarkerRange"
        static let startMarker = "AXStartTextMarkerForTextMarkerRange"
        static let rangeForMarkers = "AXTextMarkerRangeForUnorderedTextMarkers"
        /// A plain attribute of the web area, not a parameterized one.
        static let selectedRange = "AXSelectedTextMarkerRange"
    }

    /// The parameterized attributes the web steps use; stage 0 copies these from a web area it found by
    /// walking up.
    package static let parameterizedAttributes: Set<String> = [
        Attribute.textMarkerForPosition,
        Attribute.sentenceRange,
        Attribute.paragraphRange,
        Attribute.lineRange,
        Attribute.string,
        Attribute.bounds,
        Attribute.startMarker,
        Attribute.rangeForMarkers,
    ]

    /// What `ReadStep.textMarkers` needs: the marker under the pointer and the string of a range.
    package static let unitRequirements: Set<String> = [Attribute.textMarkerForPosition, Attribute.string]
    /// What `ReadStep.selection` needs in a web area: the selection is kept only if the pointer is inside its
    /// bounds.
    package static let selectionRequirements: Set<String> = [Attribute.bounds, Attribute.string]

    static let webAreaRole = "AXWebArea"
    /// Bounds the parent walk for browser chrome (toolbars, tabs) that never reaches a web area.
    static let maxWebAreaWalkDepth = 8
    static let webAreaWalkStopRoles: Set<String> = [kAXWindowRole, kAXApplicationRole]

    private let primaryScreenFrame: CGRect
    /// `nil` until the first search; then the web area, or `.some(nil)` if there was none.
    private var locatedWebArea: AXAttributes??

    package init(primaryScreenFrame: CGRect = AXGeometry.primaryScreenFrame()) {
        self.primaryScreenFrame = primaryScreenFrame
    }

    // MARK: - Steps

    /// `ReadStep.selection` in a web area: `AXSelectedTextMarkerRange` on the web area, kept only if the pointer
    /// is inside its bounds, the same rule as the native selection. A marker range can't be cut, so the whole
    /// selection is fetched; the chooser caps what is shown. Up to three AX calls after the walk.
    package func readSelection(
        _ hit: AXAttributes,
        role: String?,
        pointer: PointerSample,
        supported: Set<String>
    ) throws(AXReadError) -> AXTextRangeReader.SelectionOutput {
        guard supported.isSuperset(of: Self.selectionRequirements),
              let webArea = try webArea(from: hit, role: role),
              let selected = try webArea.value(Attribute.selectedRange),
              let globalBounds = try webArea.rect(Attribute.bounds, with: selected),
              Self.isUnderPointer(globalBounds: globalBounds, pointer: pointer),
              let text = try webArea.string(Attribute.string, with: selected).nonEmpty
        else { return AXTextRangeReader.SelectionOutput() }
        let frame = AXGeometry.appKitRect(globalRect: globalBounds, primaryScreenFrame: primaryScreenFrame)
        return AXTextRangeReader.SelectionOutput(selection: TextSpan(text: text, frame: frame))
    }

    /// `ReadStep.textMarkers`: the marker under the pointer, its unit's range for `granularity`, then that
    /// range's string and bounds. When sentence ranges are unsupported or empty, the paragraph (else the line)
    /// is fetched and cut down to the sentence at the pointer (R5). A unit whose bounds don't contain the
    /// pointer (e.g. the nearest text to an image or a margin) is dropped, so the ladder falls through to the
    /// element's own text or label.
    package func readUnit(
        _ hit: AXAttributes,
        role: String?,
        granularity: ReadGranularity,
        pointer: PointerSample,
        supported: Set<String>
    ) throws(AXReadError) -> UnitOutput {
        let empty = UnitOutput(granularity: granularity)
        let attempts = Self.rangeAttempts(for: granularity, supported: supported)
        guard supported.isSuperset(of: Self.unitRequirements), !attempts.isEmpty,
              let webArea = try webArea(from: hit, role: role),
              let marker = try webArea.parameterized(Attribute.textMarkerForPosition, AXValueBox.make(pointer.global))
        else { return empty }

        for attempt in attempts {
            guard let range = try webArea.parameterized(attempt.attribute, marker),
                  let text = try webArea.string(Attribute.string, with: range), Self.hasText(text)
            else {
                Logger.platform.debug("Text markers: \(attempt.attribute, privacy: .public) gave no text")
                continue
            }
            let globalBounds: CGRect? = if supported.contains(Attribute.bounds) {
                try webArea.rect(Attribute.bounds, with: range)
            } else {
                nil
            }
            if let globalBounds, !Self.isUnderPointer(globalBounds: globalBounds, pointer: pointer) {
                // A larger unit around the same marker won't be under the pointer either.
                Logger.platform.debug("Text markers: \(attempt.attribute, privacy: .public) unit not under the pointer")
                return empty
            }
            var shown = text
            var offset: Int?
            if attempt.segmentsLocally {
                offset = try pointerOffset(from: range, to: marker, on: webArea, supported: supported)
                guard let sentence = Self.sentence(in: text, pointerOffset: offset) else { continue }
                shown = sentence
            }
            // §4.10: attribute names and lengths only.
            Logger.platform.debug(
                """
                Text markers: \(attempt.attribute, privacy: .public) length=\(text.utf16.count) \
                segmented=\(attempt.segmentsLocally) pointerOffset=\(offset ?? -1) shownLength=\(shown.utf16.count) \
                hasBounds=\(globalBounds != nil)
                """
            )
            let frame = globalBounds.map { AXGeometry.appKitRect(globalRect: $0, primaryScreenFrame: primaryScreenFrame) }
            return UnitOutput(granularity: granularity, unit: TextSpan(text: shown, frame: frame))
        }
        return empty
    }

    // MARK: - Web area

    /// The hit element if it is the web area, else the nearest `AXWebArea` ancestor within
    /// `maxWebAreaWalkDepth` levels; found once per read.
    private func webArea(from hit: AXAttributes, role: String?) throws(AXReadError) -> AXAttributes? {
        if let locatedWebArea { return locatedWebArea }
        let found = try Self.locateWebArea(from: hit, role: role)
        locatedWebArea = .some(found)
        if found == nil { Logger.platform.debug("Text markers: no AXWebArea above the hit element") }
        return found
    }

    /// No call when `role` already says the hit is the web area; else two calls (parent, role) per level,
    /// stopping at a window or the application.
    static func locateWebArea(from hit: AXAttributes, role: String?) throws(AXReadError) -> AXAttributes? {
        if role == webAreaRole { return hit }
        var current = hit
        for _ in 0..<maxWebAreaWalkDepth {
            guard let parent = try current.element(kAXParentAttribute) else { return nil }
            current = current.on(parent)
            guard let role = try current.string(kAXRoleAttribute) else { return nil }
            if role == webAreaRole { return current }
            if webAreaWalkStopRoles.contains(role) { return nil }
        }
        return nil
    }

    // MARK: - Gecko fallback (R5)

    /// The heuristic for where the pointer is inside a paragraph or line: the length of the text from the
    /// unit's start marker to the pointer's marker. Three AX calls; `nil` when an attribute is missing or the
    /// app returns nothing (e.g. for an empty prefix).
    private func pointerOffset(
        from range: CFTypeRef,
        to marker: CFTypeRef,
        on webArea: AXAttributes,
        supported: Set<String>
    ) throws(AXReadError) -> Int? {
        guard supported.isSuperset(of: [Attribute.startMarker, Attribute.rangeForMarkers]),
              let start = try webArea.parameterized(Attribute.startMarker, range),
              let prefix = try webArea.parameterized(Attribute.rangeForMarkers, [start, marker] as CFArray),
              let text = try webArea.string(Attribute.string, with: prefix)
        else { return nil }
        return text.utf16.count
    }

    // MARK: - Decisions (pure)

    /// The marker-range attributes to try, in order, for `granularity`, keeping only those in `supported`.
    /// A sentence falls back to the paragraph, then the line, segmented locally; a paragraph or a line has no
    /// fallback.
    package static func rangeAttempts(for granularity: ReadGranularity, supported: Set<String>) -> [RangeAttempt] {
        let attempts: [RangeAttempt] = switch granularity {
        case .sentence: [
            RangeAttempt(attribute: Attribute.sentenceRange, segmentsLocally: false),
            RangeAttempt(attribute: Attribute.paragraphRange, segmentsLocally: true),
            RangeAttempt(attribute: Attribute.lineRange, segmentsLocally: true),
        ]
        case .paragraph: [RangeAttempt(attribute: Attribute.paragraphRange, segmentsLocally: false)]
        case .line: [RangeAttempt(attribute: Attribute.lineRange, segmentsLocally: false)]
        }
        return attempts.filter { supported.contains($0.attribute) }
    }

    /// The sentence of a paragraph or line that contains the pointer, for engines without sentence ranges
    /// (R5). `pointerOffset` is the UTF-16 length of the text before the pointer (see `pointerOffset(from:…)`),
    /// clamped to the text. Without it the whole text is returned: a larger unit, but never the wrong one.
    /// `nil` when the text, or the sentence at the offset, is only whitespace.
    package static func sentence(in text: String, pointerOffset: Int?) -> String? {
        guard hasText(text) else { return nil }
        guard let pointerOffset else { return text }
        let index = min(max(pointerOffset, 0), text.utf16.count)
        return TextSegmenter.unit(.sentence, in: TextWindow(text: text, start: 0, indexAtPointer: index))?.text
    }

    /// Bounds come back in top-left global coordinates, like the pointer's `global` point. An empty rect (a
    /// collapsed selection) never contains it.
    package static func isUnderPointer(globalBounds: CGRect, pointer: PointerSample) -> Bool {
        !globalBounds.isEmpty && globalBounds.contains(pointer.global)
    }

    private static func hasText(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace }
    }
}

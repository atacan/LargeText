import ApplicationServices
import CoreGraphics
import LargeTextCore

/// Native text under the pointer without fetching the full text (§4.3): the selection, a window of text
/// around the pointer, and bounds for the highlight. All offsets are UTF-16, as AX counts them. There is no
/// support cache in v1; the caller checks `supportedParameterized` first (`AXReadStepRunner.canRun`).
package struct AXTextRangeReader {
    package struct SelectionOutput: ReadStepOutput {
        package var selection: TextSpan?

        package func merge(into candidates: inout ReadCandidates) {
            candidates.selection = selection
        }
    }

    package struct WindowOutput: ReadStepOutput {
        package var window: TextWindow?

        package func merge(into candidates: inout ReadCandidates) {
            candidates.window = window
        }
    }

    /// The window is about `indexAtPointer ± windowRadius` units.
    package static let windowRadius = 2_000

    private let primaryScreenFrame: CGRect

    package init(primaryScreenFrame: CGRect = AXGeometry.primaryScreenFrame()) {
        self.primaryScreenFrame = primaryScreenFrame
    }

    /// `ReadStep.selection`. Up to three AX calls: the selected range, its bounds and its text. The selection
    /// is kept only if the pointer is inside its bounds (for a multi-line selection, the bounding box), and
    /// at most `maxLength` units of it are fetched, so selecting a whole document costs no more than a window.
    /// Needs `kAXBoundsForRangeParameterizedAttribute` and `kAXStringForRangeParameterizedAttribute`.
    package func readSelection(_ ax: AXAttributes, pointer: PointerSample, maxLength: Int) throws(AXReadError) -> SelectionOutput {
        guard let selected = try ax.range(kAXSelectedTextRangeAttribute), !selected.isEmpty,
              let globalBounds = try ax.rect(kAXBoundsForRangeParameterizedAttribute, for: selected),
              globalBounds.contains(pointer.global) else { return SelectionOutput() }
        let fetched = selected.lowerBound..<(selected.lowerBound + min(selected.count, maxLength))
        guard let text = try ax.string(kAXStringForRangeParameterizedAttribute, for: fetched).nonEmpty else {
            return SelectionOutput()
        }
        let frame = AXGeometry.appKitRect(globalRect: globalBounds, primaryScreenFrame: primaryScreenFrame)
        return SelectionOutput(selection: TextSpan(text: text, frame: frame))
    }

    /// `ReadStep.textWindow`. Two AX calls: the index under the pointer, then the text around it. Needs
    /// `kAXRangeForPositionParameterizedAttribute` and `kAXStringForRangeParameterizedAttribute`.
    package func readWindow(_ ax: AXAttributes, pointer: PointerSample, characterCount: Int?) throws(AXReadError) -> WindowOutput {
        guard let hit = try ax.range(kAXRangeForPositionParameterizedAttribute, for: pointer.global) else {
            return WindowOutput()
        }
        let index = Self.clamp(index: hit.lowerBound, characterCount: characterCount)
        let range = Self.windowRange(around: index, radius: Self.windowRadius, characterCount: characterCount)
        guard !range.isEmpty, let text = try ax.string(kAXStringForRangeParameterizedAttribute, for: range).nonEmpty else {
            return WindowOutput()
        }
        return WindowOutput(window: TextWindow(text: text, start: range.lowerBound, indexAtPointer: index))
    }

    /// Bounds of an element range in AppKit coordinates, e.g. the chosen sentence for the highlight. One AX
    /// call; needs `kAXBoundsForRangeParameterizedAttribute`.
    package func bounds(forRange range: Range<Int>, on ax: AXAttributes) throws(AXReadError) -> CGRect? {
        try ax.rect(kAXBoundsForRangeParameterizedAttribute, for: range).map {
            AXGeometry.appKitRect(globalRect: $0, primaryScreenFrame: primaryScreenFrame)
        }
    }

    /// `index ± radius`, clamped to `0...characterCount`. Without a count only the lower end is clamped and the
    /// app clamps (or rejects) the upper end.
    package static func windowRange(around index: Int, radius: Int, characterCount: Int?) -> Range<Int> {
        let index = clamp(index: index, characterCount: characterCount)
        let lower = max(0, index - radius)
        let upper = characterCount.map { min(index + radius, $0) } ?? index + radius
        return lower..<max(lower, upper)
    }

    /// The pointer index inside `0...characterCount`; past the end means "after the last character".
    package static func clamp(index: Int, characterCount: Int?) -> Int {
        let index = max(0, index)
        return characterCount.map { min(index, max(0, $0)) } ?? index
    }
}

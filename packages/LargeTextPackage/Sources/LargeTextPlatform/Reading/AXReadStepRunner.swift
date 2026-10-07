import ApplicationServices
import CoreGraphics
import LargeTextCore
import os

/// The partial result of one `ReadStep`. Sendable, so it may leave the reader's actor; it never holds an
/// `AXUIElement`.
package protocol ReadStepOutput: Sendable {
    /// Sets only the fields this step owns.
    func merge(into candidates: inout ReadCandidates)
}

/// Runs one `ReadStep` named by Core's `ReadPlan` on the hit element and merges its result (§4.3).
///
/// Every step, including a skipped one, is added to `attemptedSteps`, so a plan that never repeats an
/// attempted step always reaches `.done`. A step whose parameterized attributes aren't in
/// `supportedParameterized` is skipped without an AX call; a failed step leaves its fields `nil`. Only
/// `AXReadError` (`cannotComplete`, `apiDisabled`) escapes, and it aborts the whole read.
package struct AXReadStepRunner {
    private let policy: ReadPolicy
    private let textRanges: AXTextRangeReader
    /// One per read, so the `.selection` and `.textMarkers` steps share the web area it finds.
    private let textMarkers: AXTextMarkerReader

    /// One runner per read.
    package init(policy: ReadPolicy, primaryScreenFrame: CGRect = AXGeometry.primaryScreenFrame()) {
        self.policy = policy
        self.textRanges = AXTextRangeReader(primaryScreenFrame: primaryScreenFrame)
        self.textMarkers = AXTextMarkerReader(primaryScreenFrame: primaryScreenFrame)
    }

    /// - Parameters:
    ///   - ax: the hit element, with the read's call counter.
    ///   - granularity: the unit `.textMarkers` fetches.
    package func run(
        _ step: ReadStep,
        on ax: AXAttributes,
        pointer: PointerSample,
        granularity: ReadGranularity,
        candidates: ReadCandidates
    ) throws(AXReadError) -> ReadCandidates {
        var candidates = candidates
        candidates.attemptedSteps.insert(step)
        guard Self.canRun(step, supportedParameterized: candidates.supportedParameterized, webArea: candidates.webArea) else {
            Logger.platform.debug("Step \(String(describing: step), privacy: .public) skipped")
            return candidates
        }
        let start = ContinuousClock.now
        let output = try output(of: step, on: ax, pointer: pointer, granularity: granularity, candidates: candidates)
        output?.merge(into: &candidates)
        Logger.platform.debug(
            """
            Step \(String(describing: step), privacy: .public) in \(Self.milliseconds(since: start), format: .fixed(precision: 1), privacy: .public) ms: \
            valueLength=\(candidates.value?.utf16.count ?? 0) selectionLength=\(candidates.selection?.text.utf16.count ?? 0) \
            windowLength=\(candidates.window?.text.utf16.count ?? 0) \
            markerUnitLength=\(candidates.markerUnits[granularity]?.text.utf16.count ?? 0) childTexts=\(candidates.childTexts.count) \
            hasAncestorLabel=\(candidates.ancestorLabel != nil) hidden=\(candidates.hiddenEncountered)
            """
        )
        return candidates
    }

    /// The parameterized attributes a step needs. In a web area `.selection` is the web selection
    /// (`AXSelectedTextMarkerRange` on the `AXWebArea`), so `ReadPlan`'s steps keep one meaning on both paths:
    /// `.selection` is the selection under the pointer, `.textMarkers` the unit at the pointer.
    package static func requiredParameterized(for step: ReadStep, webArea: Bool) -> Set<String> {
        switch step {
        case .selection where webArea: AXTextMarkerReader.selectionRequirements
        case .selection: [kAXBoundsForRangeParameterizedAttribute, kAXStringForRangeParameterizedAttribute]
        case .textWindow: [kAXRangeForPositionParameterizedAttribute, kAXStringForRangeParameterizedAttribute]
        case .textMarkers: AXTextMarkerReader.unitRequirements
        case .value, .walk, .done: []
        }
    }

    /// `.done` does nothing; every other step runs when its attributes are supported.
    package static func canRun(_ step: ReadStep, supportedParameterized: Set<String>, webArea: Bool) -> Bool {
        switch step {
        case .done: false
        case .value, .selection, .textWindow, .textMarkers, .walk:
            requiredParameterized(for: step, webArea: webArea).isSubset(of: supportedParameterized)
        }
    }

    private func output(
        of step: ReadStep,
        on ax: AXAttributes,
        pointer: PointerSample,
        granularity: ReadGranularity,
        candidates: ReadCandidates
    ) throws(AXReadError) -> (any ReadStepOutput)? {
        switch step {
        case .value:
            try AXValueReader(limit: policy.elementTextLimit)
                .read(ax, characterCount: candidates.characterCount, role: candidates.role)
        case .selection where candidates.webArea:
            try textMarkers.readSelection(
                ax,
                role: candidates.role,
                pointer: pointer,
                supported: candidates.supportedParameterized
            )
        case .selection:
            // One unit over the cap lets the chooser tell that it must add an ellipsis.
            try textRanges.readSelection(ax, pointer: pointer, maxLength: policy.maxCharacters + 1)
        case .textWindow:
            try textRanges.readWindow(ax, pointer: pointer, characterCount: candidates.characterCount)
        case .walk:
            try AXElementWalker(valueLimit: policy.elementTextLimit).walk(ax)
        case .textMarkers:
            try textMarkers.readUnit(
                ax,
                role: candidates.role,
                granularity: granularity,
                pointer: pointer,
                supported: candidates.supportedParameterized
            )
        case .done:
            nil
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
}

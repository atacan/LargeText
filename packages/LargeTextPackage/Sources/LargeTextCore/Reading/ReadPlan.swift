import Foundation

/// Names the next expensive extraction step for Platform to run (§4.3). Pure.
///
/// Platform runs the step, adds it to `attemptedSteps`, merges what it found and asks again. A step in
/// `attemptedSteps` is never returned, so the loop always reaches `.done`.
package enum ReadPlan {
    /// Roles whose `value` may be a whole document: `.value` only when `characterCount` says it is short.
    package static let textInputRoles: Set<String> = ["AXTextArea", "AXTextField"]
    /// Roles that usually wrap their text in children, which the bounded walk reads.
    package static let containerRoles: Set<String> = ["AXGroup", "AXCell", "AXRow", "AXLink"]
    /// Roles whose `value` isn't their text (a checkbox's 0/1, a slider's number, a link's URL) or is
    /// normally empty (groups, rows): `.value` is never fetched for them.
    package static let nonTextValueRoles: Set<String> = [
        "AXCheckBox",
        "AXRadioButton",
        "AXSlider",
        "AXScrollBar",
        "AXIncrementor",
        "AXValueIndicator",
        "AXProgressIndicator",
        "AXLevelIndicator",
        "AXDisclosureTriangle",
        "AXLink",
        "AXGroup",
        "AXRow",
    ]

    /// The order, each step skipped once attempted or once a higher rung of the §3.3 ladder has text:
    /// 1. `.selection` (web areas and text inputs);
    /// 2. `.textMarkers` (web) or `.textWindow` (native text inputs) for the unit at the pointer;
    /// 3. `.value`, only when the element text is known to be short, or the role isn't a text input and the
    ///    length is unknown; never for `nonTextValueRoles`;
    /// 4. `.walk`, for a container without its own text or label.
    package static func next(after candidates: ReadCandidates, granularity: ReadGranularity, policy: ReadPolicy) -> ReadStep {
        if ReadTextChooser.isHidden(candidates, policy: policy) { return .done }

        func untried(_ step: ReadStep) -> Bool { !candidates.attemptedSteps.contains(step) }
        let isTextInput = candidates.role.map(textInputRoles.contains) ?? false

        if candidates.webArea || isTextInput {
            if hasText(candidates.selection?.text) { return .done }
            if untried(.selection) { return .selection }
        }

        if candidates.webArea {
            if hasText(candidates.markerUnits[granularity]?.text) { return .done }
            if untried(.textMarkers) { return .textMarkers }
        } else if isTextInput {
            if let window = candidates.window, TextSegmenter.unit(granularity, in: window) != nil { return .done }
            if untried(.textWindow) { return .textWindow }
        }

        if mayFetchValue(candidates, isTextInput: isTextInput, limit: policy.elementTextLimit) {
            if let value = candidates.value, value.utf16.count <= policy.elementTextLimit, hasText(value) {
                return .done
            }
            if untried(.value) { return .value }
        }

        let labels = [candidates.title, candidates.description, candidates.help, candidates.placeholder]
        if labels.contains(where: hasText) { return .done }

        if let role = candidates.role, containerRoles.contains(role), untried(.walk) { return .walk }
        return .done
    }

    /// Never fetch a value that is known to be long: on a text area it can be megabytes over IPC.
    private static func mayFetchValue(_ candidates: ReadCandidates, isTextInput: Bool, limit: Int) -> Bool {
        if let role = candidates.role, nonTextValueRoles.contains(role) { return false }
        if let count = candidates.characterCount { return count <= limit }
        return !isTextInput
    }

    private static func hasText(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

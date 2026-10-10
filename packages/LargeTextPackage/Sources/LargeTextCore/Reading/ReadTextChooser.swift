import Foundation

/// Picks the text to show from the final `ReadCandidates`: the §3.3 ladder. Pure.
package enum ReadTextChooser {
    /// Roles whose `value` is the text itself, rather than a control's state. A `nil` role also uses value first.
    package static let textValueRoles: Set<String> = ["AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXCell"]

    /// The ladder:
    /// 1. hidden content (a secure element, a secure element met in a walk, a denylisted app);
    /// 2. the selection under the pointer;
    /// 3. the unit at the pointer (web text markers, or a native text window);
    /// 4. a short value for text-value roles; for controls, the name (title, then description) and a distinct
    ///    short value on the next line, or whichever exists;
    /// 5. a fallback label: title, then description, then help, then placeholder;
    /// 6. what the bounded walk found: child texts, then an ancestor's label;
    /// 7. nothing.
    ///
    /// Text is verbatim with only the outer whitespace trimmed, and capped at `policy.maxCharacters`.
    package static func choose(
        from candidates: ReadCandidates,
        granularity: ReadGranularity,
        policy: ReadPolicy,
        appName: String? = nil
    ) -> ReadResult {
        if isHidden(candidates, policy: policy) { return .hidden }

        func text(_ raw: String?, source: ReadSource, frame: CGRect?, window: TextWindow? = nil) -> ReadResult? {
            guard let raw, let shown = TextSegmenter.displayText(raw, maxCharacters: policy.maxCharacters) else {
                return nil
            }
            return .text(ReadText(
                text: shown,
                granularity: granularity,
                source: source,
                appName: appName,
                bundleIdentifier: candidates.bundleIdentifier,
                sourceFrame: frame ?? candidates.elementFrame,
                window: window
            ))
        }

        if let selection = candidates.selection,
           let result = text(selection.text, source: .selection, frame: selection.frame) {
            return result
        }
        if let span = candidates.markerUnits[granularity],
           let result = text(span.text, source: .unit, frame: span.frame) {
            return result
        }
        // The window is kept so the coordinator can re-segment to another unit without a new read.
        if let window = candidates.window,
           let unit = TextSegmenter.unit(granularity, in: window),
           let result = text(unit.text, source: .unit, frame: nil, window: window) {
            return result
        }
        let value = candidates.value.flatMap { raw -> String? in
            guard raw.utf16.count <= policy.elementTextLimit,
                  !(candidates.role.map(ReadPlan.nonTextValueRoles.contains) ?? false) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if !(candidates.role.map(textValueRoles.contains) ?? true) {
            let name = [candidates.title, candidates.description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let name {
                let combined: String
                if let value, name.caseInsensitiveCompare(value) != .orderedSame {
                    combined = name + "\n" + value
                } else {
                    combined = name
                }
                if let result = text(combined, source: .label, frame: nil) { return result }
            }
        }
        if let result = text(value, source: .element, frame: nil) {
            return result
        }
        for label in [candidates.title, candidates.description, candidates.help, candidates.placeholder] {
            if let result = text(label, source: .label, frame: nil) { return result }
        }
        let children = candidates.childTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let result = text(children.joined(separator: "\n"), source: .walk, frame: nil) {
            return result
        }
        if let result = text(candidates.ancestorLabel, source: .walk, frame: nil) {
            return result
        }
        return .nothing
    }

    /// Whether the candidates must be shown as "Hidden text". `ReadPlan` stops at once in that case, and
    /// Platform checks the denylist before stage 0; this repeats it as defence in depth.
    package static func isHidden(_ candidates: ReadCandidates, policy: ReadPolicy) -> Bool {
        if candidates.hiddenEncountered { return true }
        if ElementKind.classify(role: candidates.role, subrole: candidates.subrole) == .secureText { return true }
        if let bundleIdentifier = candidates.bundleIdentifier, policy.denylist.contains(bundleIdentifier) {
            return true
        }
        return false
    }
}

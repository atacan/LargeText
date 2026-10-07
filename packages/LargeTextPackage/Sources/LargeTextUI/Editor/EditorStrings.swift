import LargeTextCore

/// The overlay's user-visible strings, derived purely from `OverlayChrome`.
package enum EditorStrings {
    package static let neutralTitle = "LargeText"
    package static let footer = "↩ Insert   ⌘↩ Insert & Submit   ⎋ Cancel   ⌘± Size"
    package static let willCopyHint = "Will copy to clipboard"
    package static let flattensNewlinesHint = "Line breaks become spaces"

    package static func title(targetName: String?) -> String {
        guard let targetName, !targetName.isEmpty else { return neutralTitle }
        return "Typing into \(targetName)"
    }

    package static func hints(_ hints: TargetHints) -> [String] {
        var result: [String] = []
        if hints.willCopyToClipboard { result.append(willCopyHint) }
        if hints.flattensNewlines { result.append(flattensNewlinesHint) }
        return result
    }
}

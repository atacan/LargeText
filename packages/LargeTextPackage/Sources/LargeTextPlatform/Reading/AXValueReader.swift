import ApplicationServices
import LargeTextCore

/// `ReadStep.value`: the element's `value`, fetched only when it is known or expected to be short (§3.3).
package struct AXValueReader {
    package struct Output: ReadStepOutput {
        package var value: String?

        package func merge(into candidates: inout ReadCandidates) {
            candidates.value = value
        }
    }

    /// Fetch only up to this many characters (UTF-16 units, as `kAXNumberOfCharactersAttribute` counts).
    private let limit: Int

    package init(limit: Int) {
        self.limit = limit
    }

    /// One AX call, or none when `shouldFetch` says no. A non-string value (a slider's number) is `nil`.
    package func read(_ ax: AXAttributes, characterCount: Int?, role: String?) throws(AXReadError) -> Output {
        guard Self.shouldFetch(characterCount: characterCount, role: role, limit: limit) else { return Output() }
        return Output(value: try ax.string(kAXValueAttribute).nonEmpty)
    }

    /// A known count decides. Without one, a multi-line text area may hold a whole document, so it is never
    /// fetched; anything else (a static text, which often has no count) is.
    package static func shouldFetch(characterCount: Int?, role: String?, limit: Int) -> Bool {
        if let characterCount { return characterCount <= limit }
        guard let role else { return true }
        return !ElementKind.multiLineTextRoles.contains(role)
    }
}

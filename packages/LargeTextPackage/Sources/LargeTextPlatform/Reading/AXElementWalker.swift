import ApplicationServices
import LargeTextCore

/// `ReadStep.walk`: a bounded walk around an element with no text of its own (§3.3, §4.3), e.g. an empty
/// `AXGroup` or a cell whose label is a child or an ancestor.
///
/// - Down: depth-first, so child texts keep document order; at most `maxDepth` levels and `maxNodesPerLevel`
///   nodes per level. Only nodes without text of their own are descended into.
/// - Up: at most `maxAncestorLevels` parents, for the first one with a title or description; never past a
///   window.
///
/// Every visited node is classified with `ElementKind.classify`; a secure one sets `hiddenEncountered` and
/// its text is never read.
package struct AXElementWalker {
    package struct Output: ReadStepOutput {
        package var childTexts: [String] = []
        package var ancestorLabel: String?
        package var hiddenEncountered = false

        package func merge(into candidates: inout ReadCandidates) {
            candidates.childTexts += childTexts
            candidates.ancestorLabel = candidates.ancestorLabel ?? ancestorLabel
            candidates.hiddenEncountered = candidates.hiddenEncountered || hiddenEncountered
        }
    }

    static let maxDepth = 2
    static let maxNodesPerLevel = 20
    static let maxAncestorLevels = 2
    static let nodeAttributes: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXDescriptionAttribute,
        kAXNumberOfCharactersAttribute,
    ]
    static let ancestorStopRoles: Set<String> = [kAXWindowRole, kAXApplicationRole]

    /// A child's `value` is fetched only under this limit (see `AXValueReader.shouldFetch`).
    private let valueLimit: Int

    package init(valueLimit: Int) {
        self.valueLimit = valueLimit
    }

    package func walk(_ ax: AXAttributes) throws(AXReadError) -> Output {
        var output = Output()
        var visitedPerLevel = Array(repeating: 0, count: Self.maxDepth)
        try walkDown(ax, depth: 1, visitedPerLevel: &visitedPerLevel, output: &output)
        try walkUp(ax, output: &output)
        return output
    }

    private func walkDown(
        _ ax: AXAttributes,
        depth: Int,
        visitedPerLevel: inout [Int],
        output: inout Output
    ) throws(AXReadError) {
        let level = depth - 1
        let remaining = Self.maxNodesPerLevel - visitedPerLevel[level]
        guard remaining > 0 else { return }
        for child in try ax.elements(kAXChildrenAttribute, maxCount: remaining) {
            guard visitedPerLevel[level] < Self.maxNodesPerLevel else { return }
            visitedPerLevel[level] += 1
            let node = ax.on(child)
            let batch = try node.batch(Self.nodeAttributes)
            let role = batch.string(for: kAXRoleAttribute)
            if ElementKind.classify(role: role, subrole: batch.string(for: kAXSubroleAttribute)) == .secureText {
                output.hiddenEncountered = true
                continue
            }
            if let text = try text(of: node, batch: batch, role: role) {
                output.childTexts.append(text)
            } else if depth < Self.maxDepth {
                try walkDown(node, depth: depth + 1, visitedPerLevel: &visitedPerLevel, output: &output)
            }
        }
    }

    private func walkUp(_ ax: AXAttributes, output: inout Output) throws(AXReadError) {
        var current = ax
        for _ in 0..<Self.maxAncestorLevels {
            guard let parent = try current.element(kAXParentAttribute) else { return }
            current = current.on(parent)
            let batch = try current.batch(Self.nodeAttributes)
            let role = batch.string(for: kAXRoleAttribute)
            if ElementKind.classify(role: role, subrole: batch.string(for: kAXSubroleAttribute)) == .secureText {
                output.hiddenEncountered = true
                return
            }
            if let role, Self.ancestorStopRoles.contains(role) { return }
            if let label = batch.string(for: kAXTitleAttribute).nonEmpty ?? batch.string(for: kAXDescriptionAttribute).nonEmpty {
                output.ancestorLabel = label
                return
            }
        }
    }

    /// Title, else description, else a short `value` (static texts carry their text there).
    private func text(of node: AXAttributes, batch: AXBatchResult, role: String?) throws(AXReadError) -> String? {
        if let label = batch.string(for: kAXTitleAttribute).nonEmpty ?? batch.string(for: kAXDescriptionAttribute).nonEmpty {
            return label
        }
        let characterCount = batch.int(for: kAXNumberOfCharactersAttribute)
        guard AXValueReader.shouldFetch(characterCount: characterCount, role: role, limit: valueLimit) else { return nil }
        return try node.string(kAXValueAttribute).nonEmpty
    }
}

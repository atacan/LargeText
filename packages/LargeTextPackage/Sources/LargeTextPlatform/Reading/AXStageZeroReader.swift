import ApplicationServices
import CoreGraphics
import LargeTextCore
import os

/// Stage 0 of every read (§4.3): one batched attribute read plus the parameterized attribute names of the
/// hit element. Fills the cheap `ReadCandidates` fields; Core's `ReadPlan` then names the next step.
package struct AXStageZeroReader {
    /// **No `value`**: on an `AXTextArea` it is the whole document, often megabytes over IPC. `ReadStep.value`
    /// fetches it only for short elements.
    static let batchAttributes: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXDescriptionAttribute,
        kAXHelpAttribute,
        kAXPlaceholderValueAttribute,
        kAXNumberOfCharactersAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
    ]

    /// Undocumented; supported by elements inside WebKit, Chromium and Gecko web content.
    static let textMarkerForPosition = "AXTextMarkerForPosition"
    static let webAreaRole = "AXWebArea"
    /// Bounds the parent walk for browser chrome (toolbars, tabs) that never reaches a web area.
    static let maxWebAreaWalkDepth = 8
    static let webAreaWalkStopRoles: Set<String> = [kAXWindowRole, kAXApplicationRole]

    private let primaryScreenFrame: CGRect

    package init(primaryScreenFrame: CGRect = AXGeometry.primaryScreenFrame()) {
        self.primaryScreenFrame = primaryScreenFrame
    }

    /// Two AX calls, plus at most `2 × maxWebAreaWalkDepth` for a browser or Electron element that doesn't
    /// support text markers itself. Empty strings come back as `nil`.
    package func read(_ target: AXHitTarget, calls: AXCallCounter) throws(AXReadError) -> ReadCandidates {
        let ax = AXAttributes(target.element, calls: calls)
        let batch = try ax.batch(Self.batchAttributes)
        let supported = try ax.parameterizedAttributeNames()
        let role = batch.string(for: kAXRoleAttribute)

        var webArea = Self.isWebArea(supportedParameterized: supported, role: role)
        if Self.shouldWalkUpForWebArea(isWebArea: webArea, family: target.family) {
            webArea = try hasWebAreaAncestor(ax)
        }

        let frame = batch.point(for: kAXPositionAttribute).flatMap { position in
            batch.size(for: kAXSizeAttribute).map { size in
                AXGeometry.appKitRect(axPosition: position, axSize: size, primaryScreenFrame: primaryScreenFrame)
            }
        }
        let candidates = ReadCandidates(
            pid: target.pid,
            bundleIdentifier: target.bundleIdentifier,
            role: role,
            subrole: batch.string(for: kAXSubroleAttribute),
            title: batch.string(for: kAXTitleAttribute).nonEmpty,
            description: batch.string(for: kAXDescriptionAttribute).nonEmpty,
            help: batch.string(for: kAXHelpAttribute).nonEmpty,
            placeholder: batch.string(for: kAXPlaceholderValueAttribute).nonEmpty,
            characterCount: batch.int(for: kAXNumberOfCharactersAttribute),
            elementFrame: frame,
            supportedParameterized: supported,
            webArea: webArea
        )
        // §4.10: role, subrole, lengths and bundle ID only; never a string value.
        Logger.platform.debug(
            """
            Stage 0: app=\(target.bundleIdentifier ?? "nil", privacy: .public) \
            role=\(role ?? "nil", privacy: .public) subrole=\(candidates.subrole ?? "nil", privacy: .public) \
            titleLength=\(candidates.title?.utf16.count ?? 0) descriptionLength=\(candidates.description?.utf16.count ?? 0) \
            characterCount=\(candidates.characterCount ?? -1) parameterized=\(supported.count) webArea=\(webArea)
            """
        )
        return candidates
    }

    /// Text markers on the element itself, or the element is the web area.
    package static func isWebArea(supportedParameterized: Set<String>, role: String?) -> Bool {
        role == webAreaRole || supportedParameterized.contains(textMarkerForPosition)
    }

    /// Only browser and Electron pids pay for the parent walk (§4.3).
    package static func shouldWalkUpForWebArea(isWebArea: Bool, family: AXAppFamily) -> Bool {
        !isWebArea && family.hostsWebContent
    }

    private func hasWebAreaAncestor(_ ax: AXAttributes) throws(AXReadError) -> Bool {
        var current = ax
        for _ in 0..<Self.maxWebAreaWalkDepth {
            guard let parent = try current.element(kAXParentAttribute) else { return false }
            current = current.on(parent)
            guard let role = try current.string(kAXRoleAttribute) else { return false }
            if role == Self.webAreaRole { return true }
            if Self.webAreaWalkStopRoles.contains(role) { return false }
        }
        return false
    }
}

extension Optional where Wrapped == String {
    /// `nil` for a missing or empty string.
    var nonEmpty: String? {
        flatMap { $0.isEmpty ? nil : $0 }
    }
}

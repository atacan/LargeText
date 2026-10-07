import CoreGraphics
import Foundation

package struct FontSize: Equatable, Codable, Sendable {
    package let points: Double
    package init(points: Double) { self.points = points }
}

package enum ZoomStep: Equatable, Sendable {
    case bigger
    case smaller
    case reset
}

package struct TargetHints: Equatable, Sendable {
    /// `InsertionRoute.decide(...)` is `.copyOnly`.
    package var willCopyToClipboard: Bool

    package init(willCopyToClipboard: Bool = false) {
        self.willCopyToClipboard = willCopyToClipboard
    }
}

/// Everything the overlay draws except the text.
package struct OverlayChrome: Equatable, Sendable {
    package var fontSize: FontSize
    /// Rendered as "Typing into Safari".
    package var targetName: String?
    /// UI resolves the icon; Core never sees `NSImage`.
    package var targetBundleIdentifier: String?
    /// UI picks the screen from this.
    package var targetFrame: CGRect?
    package var hints: TargetHints

    package init(
        fontSize: FontSize,
        targetName: String? = nil,
        targetBundleIdentifier: String? = nil,
        targetFrame: CGRect? = nil,
        hints: TargetHints = TargetHints()
    ) {
        self.fontSize = fontSize
        self.targetName = targetName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetFrame = targetFrame
        self.hints = hints
    }
}

/// Tagged with its session; intents for a stale session are ignored.
package struct OverlayIntent: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case commit(CommitMode)
        /// ⎋ and backdrop click → `.userCancelled`; resign key → `.lostFocus`.
        case cancel(CancelReason)
        case zoom(ZoomStep)
    }

    package let sessionID: UUID
    package let kind: Kind

    package init(sessionID: UUID, kind: Kind) {
        self.sessionID = sessionID
        self.kind = kind
    }
}

package enum Notice: Equatable, Sendable {
    case copiedToClipboard(InsertionFallbackReason)
    /// Inserted with `ClipboardRestorePolicy.none`.
    case clipboardReplaced
    case secureFieldUnsupported
    case hotkeyUnavailable(KeyCombo)
    /// A reader tap found no text under the pointer.
    case nothingToRead
    case readerNeedsAccessibility
    /// The status-menu item: the pointer is on the menu, so it explains the shortcut instead of reading.
    case readerMenuHint(KeyCombo)
}

import CoreGraphics
import Foundation

/// What the reader card shows.
package enum ReaderContent: Equatable, Sendable {
    /// `scrollToUTF16`: scroll so the line containing this offset is visible (following-mode overflow).
    case text(String, scrollToUTF16: Int?)
    /// "Hidden text": a secure element or a denylisted app.
    case hidden
    /// "No text here" while following.
    case nothing
}

/// Everything the reader card draws except the content.
package struct ReaderChrome: Equatable, Sendable {
    package enum Mode: Equatable, Sendable {
        /// Hold: click-through, never key, follows the pointer.
        case following
        /// Tap: key, with a backdrop; frozen.
        case pinned
    }

    package var fontSize: FontSize
    package var mode: Mode
    /// Rendered as "Reading from Safari".
    package var appName: String?
    /// UI resolves the icon; Core never sees `NSImage`.
    package var bundleIdentifier: String?
    /// AppKit global coordinates. UI picks the screen and placement from this, and outlines it.
    package var sourceFrame: CGRect?

    package init(
        fontSize: FontSize,
        mode: Mode,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        sourceFrame: CGRect? = nil
    ) {
        self.fontSize = fontSize
        self.mode = mode
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.sourceFrame = sourceFrame
    }
}

package enum ReaderCloseReason: Equatable, Sendable {
    case userCancelled
    case lostFocus
}

/// Tagged with its session; intents for a stale session are ignored.
package struct ReaderIntent: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        /// ⎋ and backdrop click → `.userCancelled`; resign key → `.lostFocus`.
        case close(ReaderCloseReason)
        case zoom(ZoomStep)
    }

    package let sessionID: UUID
    package let kind: Kind

    package init(sessionID: UUID, kind: Kind) {
        self.sessionID = sessionID
        self.kind = kind
    }
}

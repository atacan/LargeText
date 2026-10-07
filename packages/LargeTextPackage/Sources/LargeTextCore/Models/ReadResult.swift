import CoreGraphics
import Foundation

/// The outcome of one `TextReading.read`.
package enum ReadResult: Equatable, Sendable {
    case text(ReadText)
    /// A secure element or a denylisted app. Never carries the text.
    case hidden
    case nothing
    /// Accessibility isn't trusted (or was revoked mid-session).
    case permissionMissing
}

/// Text found under the pointer, verbatim apart from trimmed outer whitespace, capped at
/// `ReadPolicy.maxCharacters`.
package struct ReadText: Equatable, Sendable {
    package var text: String
    /// The unit this text is when `source` is `.unit`; otherwise the unit that was requested.
    package var granularity: ReadGranularity
    package var source: ReadSource
    /// Rendered as "Reading from Safari".
    package var appName: String?
    /// UI resolves the icon; Core never sees `NSImage`.
    package var bundleIdentifier: String?
    /// Bounds of the text (or of its element when unknown); AppKit global coordinates. Drives placement
    /// and the source highlight.
    package var sourceFrame: CGRect?
    /// Native text only: lets Core re-segment to another unit, e.g. on pin, without a new read (§4.3).
    package var window: TextWindow?

    package init(
        text: String,
        granularity: ReadGranularity,
        source: ReadSource,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        sourceFrame: CGRect? = nil,
        window: TextWindow? = nil
    ) {
        self.text = text
        self.granularity = granularity
        self.source = source
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.sourceFrame = sourceFrame
        self.window = window
    }
}

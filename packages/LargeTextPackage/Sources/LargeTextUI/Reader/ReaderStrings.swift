import LargeTextCore

/// The reader card's user-visible strings, derived purely from `ReaderChrome` and `ReaderContent`.
package enum ReaderStrings {
    package static let neutralTitle = "LargeText"
    package static let pinnedFooter = "⎋ Close · ⌘C Copy · ⌘± Size"
    package static let followingFooter = "Release to close · Tap to pin"
    package static let hiddenText = "Hidden text"
    package static let noText = "No text here"

    package static func title(appName: String?) -> String {
        guard let appName, !appName.isEmpty else { return neutralTitle }
        return "Reading from \(appName)"
    }

    package static func footer(_ mode: ReaderChrome.Mode) -> String {
        switch mode {
        case .following: followingFooter
        case .pinned: pinnedFooter
        }
    }
}

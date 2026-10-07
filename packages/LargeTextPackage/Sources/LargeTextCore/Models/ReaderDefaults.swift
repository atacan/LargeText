import Foundation

/// Defaults for the reader preferences (§3.1, §3.2). The default shortcut is `KeyCombo.readerDefault`.
package enum ReaderDefaults {
    /// A release earlier than this after the press is a tap (pin); later is a hold (follow).
    package static let holdThreshold: Duration = .milliseconds(300)
    package static let followingUnit: ReadGranularity = .sentence
    package static let pinnedUnit: ReadGranularity = .paragraph
}

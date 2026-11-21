import Foundation

/// Defaults for the reader preferences (§3.1, §3.2). The default shortcut is `KeyCombo.readerDefault`.
package enum ReaderDefaults {
    /// A release earlier than this after the press is a tap (pin); later is a hold (follow).
    package static let holdThreshold: Duration = .milliseconds(300)
    package static let followingUnit: ReadGranularity = .sentence
    package static let pinnedUnit: ReadGranularity = .paragraph

    /// What the Settings slider offers. The store still accepts any positive value from `defaults write`.
    package static let holdThresholdRange: ClosedRange<Duration> = .milliseconds(150) ... .milliseconds(800)
    package static let holdThresholdStep: Duration = .milliseconds(25)

    /// Brings any threshold into `holdThresholdRange`.
    package static func clampHoldThreshold(_ threshold: Duration) -> Duration {
        min(max(threshold, holdThresholdRange.lowerBound), holdThresholdRange.upperBound)
    }
}

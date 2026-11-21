import Foundation

/// Reader timers that a launch state or a test may need to change.
package struct ReaderTiming: Equatable, Sendable {
    /// Last resort against a lost release while following (§3.1). `nil` disables the cap, e.g. for the
    /// `following` launch state, which holds the session open on purpose.
    package var maxFollowDuration: Duration?

    package init(maxFollowDuration: Duration? = .seconds(30)) {
        self.maxFollowDuration = maxFollowDuration
    }

    package static let standard = ReaderTiming()
}

package struct ReaderDependencies {
    package var textReader: any TextReading
    package var pointer: any PointerTracking
    package var keyState: any KeyStateReading
    package var presenter: any ReaderPresenting
    package var notices: any NoticePresenting
    /// Hotkey, hold threshold, units and `readerFontSize` are read once per session; zoom writes
    /// `readerFontSize`, never the editor's `fontSize`.
    package var preferences: any PreferencesStore
    /// Checked before a session starts, so a missing Accessibility grant shows a notice instead of a card.
    package var permissions: any PermissionsProviding
    /// Schedules the key-state check and the cap; tests park these sleeps.
    package var sleeper: any Sleeper
    package var timing: ReaderTiming
    /// Feeds `PointerThrottle`'s interval. Injected so tests control it; the gesture itself needs no clock.
    package var now: @MainActor () -> ContinuousClock.Instant

    package init(
        textReader: any TextReading,
        pointer: any PointerTracking,
        keyState: any KeyStateReading,
        presenter: any ReaderPresenting,
        notices: any NoticePresenting,
        preferences: any PreferencesStore,
        permissions: any PermissionsProviding,
        sleeper: any Sleeper,
        timing: ReaderTiming = .standard,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.textReader = textReader
        self.pointer = pointer
        self.keyState = keyState
        self.presenter = presenter
        self.notices = notices
        self.preferences = preferences
        self.permissions = permissions
        self.sleeper = sleeper
        self.timing = timing
        self.now = now
    }
}

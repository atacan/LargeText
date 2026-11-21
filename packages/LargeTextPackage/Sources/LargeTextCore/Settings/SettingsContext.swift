import Foundation

/// Where the Settings window's writes end up for this run (Settings plan §3.8). Kit builds it from the
/// launch configuration; the window shows a note per overridden row and a banner for a scenario.
package struct SettingsContext: Equatable, Sendable {
    /// The active `--scenario`. Every scenario uses `InMemoryPreferencesStore`, so nothing is saved.
    package var scenarioName: String?
    /// Keys set on the command line: writes to them stay in memory (`PreferencesOverlay`).
    package var launchOverrides: Set<PreferenceKey>

    package init(scenarioName: String? = nil, launchOverrides: Set<PreferenceKey> = []) {
        self.scenarioName = scenarioName
        self.launchOverrides = launchOverrides
    }

    /// A normal run: every write is saved.
    package static let standard = SettingsContext()

    /// Whether writes to `key` are kept for this run only.
    package func isOverridden(_ key: PreferenceKey) -> Bool {
        launchOverrides.contains(key)
    }
}

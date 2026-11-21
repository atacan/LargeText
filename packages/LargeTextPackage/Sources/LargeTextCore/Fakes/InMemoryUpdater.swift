import Foundation
import os

/// Updates in memory only: every scenario uses it, so a scenario never checks for, or installs, an update.
@MainActor
package final class InMemoryUpdater: UpdateChecking {
    package let isAvailable: Bool
    package var canCheckForUpdates = true
    package var automaticallyChecksForUpdates: Bool
    package private(set) var isStarted = false
    package private(set) var checkCount = 0

    /// - Parameter isAvailable: `false` (the default) behaves like a build without a feed.
    package init(isAvailable: Bool = false, automaticallyChecksForUpdates: Bool = true) {
        self.isAvailable = isAvailable
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    package func start() {
        isStarted = true
        Logger.core.info("InMemoryUpdater: start() (no checks are scheduled)")
    }

    package func checkForUpdates() {
        checkCount += 1
        Logger.core.info("InMemoryUpdater: checkForUpdates() ignored")
    }
}

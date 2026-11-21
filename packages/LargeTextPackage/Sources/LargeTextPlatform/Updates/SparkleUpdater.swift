import AppKit
import LargeTextCore
import os
import Sparkle

/// `UpdateChecking` with Sparkle 2. The feed and the public key come from the app's Info.plist (`SUFeedURL`,
/// `SUPublicEDKey`); a build without both, such as a local build before a key was generated, is unavailable
/// and never creates Sparkle's updater.
///
/// Constructing one has no side effects: the updater is created and started by `start()`.
@MainActor
package final class SparkleUpdater: NSObject, UpdateChecking, SPUStandardUserDriverDelegate {
    package let isAvailable: Bool
    private var controller: SPUStandardUpdaterController?

    package init(bundle: Bundle = .main) {
        isAvailable = Self.hasNonEmptyValue("SUFeedURL", in: bundle)
            && Self.hasNonEmptyValue("SUPublicEDKey", in: bundle)
        super.init()
    }

    package var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    package var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    package func start() {
        guard isAvailable else {
            Logger.platform.info("Updates unavailable: SUFeedURL or SUPublicEDKey is missing")
            return
        }
        guard controller == nil else { return }
        // `startingUpdater: true` starts it now and shows Sparkle's own alert if the configuration is invalid.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        Logger.platform.info("Updater started")
    }

    package func checkForUpdates() {
        guard let controller else {
            Logger.platform.error("Update check ignored: the updater hasn't started")
            return
        }
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// A menu-bar app is rarely active, so a scheduled update shouldn't take focus from the app the user is
    /// typing in: Sparkle shows it without activating LargeText.
    package nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // MARK: - Private

    private static func hasNonEmptyValue(_ key: String, in bundle: Bundle) -> Bool {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return false }
        return !value.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

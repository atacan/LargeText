import Foundation

/// Self-updates (Sparkle in Platform). Scenarios and tests use `InMemoryUpdater`, so they never check the
/// network or replace the app.
@MainActor
package protocol UpdateChecking: AnyObject {
    /// Whether this build can update itself: it has a feed URL and a public key. Menus and Settings leave
    /// updates out otherwise (a local build without a key).
    var isAvailable: Bool { get }
    /// Whether "Check for Updates…" can run now; false while a check or an update is in progress.
    var canCheckForUpdates: Bool { get }
    /// Daily background checks. The first value comes from Sparkle's own prompt on the second launch.
    var automaticallyChecksForUpdates: Bool { get set }
    /// Starts the updater and its scheduled checks. Called once at launch; does nothing when unavailable.
    func start()
    /// A user-initiated check that shows its result, including "You're up to date".
    func checkForUpdates()
}

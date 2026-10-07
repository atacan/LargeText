import ApplicationServices
import os

/// Makes Chromium and Electron apps expose their accessibility tree, scoped to one pid at a time (§4.11).
///
/// Sets `AXManualAccessibility` at most once per pid and logs it. Never sets `AXEnhancedUserInterface`: it
/// breaks Chrome's window animations. Not `Sendable`, on purpose: the reader actor and the focus capturer
/// each own one instance and track their own pids. Setting the attribute twice on one pid is harmless.
package final class AXAppPreparer {
    package enum Outcome: Equatable, Sendable {
        /// This pid was examined before; nothing was done.
        case alreadyExamined
        /// The app's family isn't one this preparer handles.
        case notApplicable
        /// `AXManualAccessibility` was just set. The tree builds asynchronously, so the first read is usually
        /// still empty: retry once after `retryDelay`.
        case prepared
        case failed(AXError)

        package var shouldRetry: Bool {
            self == .prepared
        }
    }

    package static let retryDelay: Duration = .milliseconds(200)
    static let manualAccessibilityAttribute = "AXManualAccessibility"

    /// Roles that count as an empty hit when they have no children (§4.11).
    static let emptyContainerRoles: Set<String> = ["AXWebArea", "AXGroup"]

    private let families: Set<AXAppFamily>
    private let setManualAccessibility: (pid_t) -> AXError
    private(set) var examinedPIDs: Set<pid_t> = []

    /// - Parameters:
    ///   - families: the editor keeps today's behaviour with `[.electron]`; the reader also prepares
    ///     Chromium browsers (spike R3 decides whether they need it).
    ///   - setManualAccessibility: test seam; the live value sets the attribute on the application element.
    package init(
        families: Set<AXAppFamily> = [.electron, .chromiumBrowser],
        setManualAccessibility: @escaping (pid_t) -> AXError = AXAppPreparer.enableManualAccessibility
    ) {
        self.families = families
        self.setManualAccessibility = setManualAccessibility
    }

    /// Examines `pid` once. `family` is only evaluated on the first call for a pid, so the Electron file check
    /// doesn't run on every read. The reader calls this only after an empty hit (`isEmptyHit`); the editor
    /// calls it on every capture, as before.
    @discardableResult
    package func prepareIfNeeded(
        pid: pid_t,
        bundleIdentifier: String?,
        family: @autoclosure () -> AXAppFamily
    ) -> Outcome {
        guard examinedPIDs.insert(pid).inserted else { return .alreadyExamined }
        guard families.contains(family()) else { return .notApplicable }
        let error = setManualAccessibility(pid)
        Logger.platform.info(
            "AXManualAccessibility on \(bundleIdentifier ?? "?", privacy: .public): \(error == .success ? "enabled" : "failed (\(error.rawValue))", privacy: .public)"
        )
        return error == .success ? .prepared : .failed(error)
    }

    /// Whether `prepareIfNeeded` could still act on `pid`: it hasn't been examined and its family is one this
    /// preparer handles. Lets the reader skip the child-count call for every other app.
    package func mayPrepare(pid: pid_t, family: AXAppFamily) -> Bool {
        !examinedPIDs.contains(pid) && families.contains(family)
    }

    /// A hit worth preparing the app for: no element at all, or an `AXWebArea` or `AXGroup` without children.
    package static func isEmptyHit(role: String?, childCount: Int?) -> Bool {
        guard let role else { return true }
        return emptyContainerRoles.contains(role) && (childCount ?? 0) == 0
    }

    package static func enableManualAccessibility(pid: pid_t) -> AXError {
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid),
            manualAccessibilityAttribute as CFString,
            kCFBooleanTrue
        )
    }
}

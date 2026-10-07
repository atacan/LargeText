import ApplicationServices
import os

/// The single home of the process-wide AX messaging timeout (§4.4).
///
/// The timeout set on the system-wide element applies to every AX call this process makes, from the main
/// thread and from the reader's queue alike. Without it, one hung app could block a caller for about 6 s.
package enum AXConfiguration {
    static let messagingTimeout: Float = 0.1

    private static let didApplyMessagingTimeout = OSAllocatedUnfairLock(initialState: false)

    /// Idempotent and thread-safe. The call fails (e.g. `.apiDisabled`) while the app isn't trusted, so it is
    /// retried on every call until it succeeds; callers are launch, every reader `read` and `captureFocus`.
    package static func applyMessagingTimeoutIfNeeded() {
        didApplyMessagingTimeout.withLock { didApply in
            guard !didApply else { return }
            let error = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
            if error == .success {
                didApply = true
                Logger.platform.info("AX messaging timeout set to \(messagingTimeout, privacy: .public) s")
            } else {
                Logger.platform.notice("AXUIElementSetMessagingTimeout failed (\(error.rawValue)); retrying on next use")
            }
        }
    }
}

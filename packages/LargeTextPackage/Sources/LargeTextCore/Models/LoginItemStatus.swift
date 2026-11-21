import Foundation

/// Launch at login as the system reports it (Settings plan §3.7). Mirrors `SMAppService.Status`; the system is
/// the source of truth, never `UserDefaults`.
package enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    /// Registered, but the user still has to allow it in System Settings › Login Items.
    case requiresApproval
    /// The system can't find the app's service, e.g. a build outside /Applications.
    case notFound

    /// The toggle shows on for a registered item, approved or not.
    package var isOn: Bool {
        switch self {
        case .enabled, .requiresApproval: true
        case .notRegistered, .notFound: false
        }
    }
}

package enum LoginItemError: Error, Equatable, Sendable {
    /// The system or the user refused it; System Settings › Login Items can allow it.
    case notPermitted
    /// Any other failure; `code` is the system's error code, for the log.
    case failed(code: Int)
}

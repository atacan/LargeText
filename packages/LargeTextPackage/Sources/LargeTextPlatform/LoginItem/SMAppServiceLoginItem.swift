import Foundation
import LargeTextCore
import os
import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (Settings plan §3.7). The system is the source of truth:
/// `status` is read fresh every time, and nothing is kept in `UserDefaults`.
///
/// `SMAppService.mainApp` is only touched on first use, never in `init`, so `AppEnvironment.live()` stays free
/// of side effects. A build run from DerivedData registers its build path; check by hand from an exported build
/// in /Applications (`docs/manual-testing.md`).
@MainActor
package final class SMAppServiceLoginItem: LoginItemControlling {
    package init() {}

    private var service: SMAppService { .mainApp }

    package var status: LoginItemStatus {
        LoginItemStatus(service.status)
    }

    package func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            Logger.platform.info("Login item: \(enabled ? "registered" : "unregistered", privacy: .public), status \(String(describing: self.status), privacy: .public)")
        } catch {
            let nsError = error as NSError
            guard let mapped = LoginItemError(registrationError: nsError, enabling: enabled) else {
                // Already in the requested state.
                Logger.platform.info("Login item: already \(enabled ? "registered" : "unregistered", privacy: .public) (\(nsError.domain, privacy: .public) \(nsError.code))")
                return
            }
            Logger.platform.error("Login item: \(enabled ? "register" : "unregister", privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.localizedDescription, privacy: .public)")
            throw mapped
        }
    }

    package func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension LoginItemStatus {
    /// Pure mapping from the system's status.
    package init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

extension LoginItemError {
    /// Error codes from `SMErrors.h`, spelled out so the mapping is testable without the framework's globals.
    package enum Code {
        /// `EPERM`, which `register()` reports when the user turned the item off in Login Items.
        package static let operationNotPermitted = 1
        package static let authorizationFailure = 4     // kSMErrorAuthorizationFailure
        package static let jobNotFound = 6              // kSMErrorJobNotFound
        package static let launchDeniedByUser = 11      // kSMErrorLaunchDeniedByUser
        package static let alreadyRegistered = 12       // kSMErrorAlreadyRegistered
    }

    /// Maps an error thrown by `register()` / `unregister()`. Pure.
    /// - Returns: `nil` when the item is already in the requested state (registering an item that is already
    ///   registered, or unregistering one that isn't), which counts as success.
    package init?(registrationError error: NSError, enabling: Bool) {
        switch error.code {
        case Code.alreadyRegistered where enabling, Code.jobNotFound where !enabling:
            return nil
        case Code.operationNotPermitted, Code.authorizationFailure, Code.launchDeniedByUser:
            self = .notPermitted
        default:
            self = .failed(code: error.code)
        }
    }
}

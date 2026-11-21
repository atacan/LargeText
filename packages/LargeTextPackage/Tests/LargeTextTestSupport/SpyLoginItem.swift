import Foundation
import LargeTextCore

/// Records `setEnabled` calls. `failure` makes them throw; `statusWhenEnabled` lets an enable end at
/// `.requiresApproval`, as `SMAppService` may.
@MainActor
package final class SpyLoginItem: LoginItemControlling {
    package var status: LoginItemStatus
    package var failure: LoginItemError?
    package var statusWhenEnabled: LoginItemStatus
    package private(set) var setEnabledCalls: [Bool] = []
    package private(set) var openSystemSettingsCount = 0

    package init(status: LoginItemStatus = .notRegistered, statusWhenEnabled: LoginItemStatus = .enabled) {
        self.status = status
        self.statusWhenEnabled = statusWhenEnabled
    }

    package func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        setEnabledCalls.append(enabled)
        if let failure { throw failure }
        status = enabled ? statusWhenEnabled : .notRegistered
    }

    package func openSystemSettings() {
        openSystemSettingsCount += 1
    }
}

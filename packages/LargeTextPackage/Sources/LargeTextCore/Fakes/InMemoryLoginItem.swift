import Foundation
import os

/// Launch at login in memory only: every scenario uses it, so a scenario never registers the app.
@MainActor
package final class InMemoryLoginItem: LoginItemControlling {
    package var status: LoginItemStatus

    package init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    package func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        status = enabled ? .enabled : .notRegistered
        Logger.core.info("InMemoryLoginItem: \(enabled ? "enabled" : "disabled", privacy: .public) (not saved)")
    }

    package func openSystemSettings() {
        Logger.core.info("InMemoryLoginItem: openSystemSettings() ignored")
    }
}

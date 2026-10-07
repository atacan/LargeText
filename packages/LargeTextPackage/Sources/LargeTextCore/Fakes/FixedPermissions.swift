import Foundation
import os

@MainActor
package final class FixedPermissions: PermissionsProviding {
    package var current: Permissions

    package init(_ permissions: Permissions) {
        current = permissions
    }

    package func requestAccessibility() {
        Logger.core.info("FixedPermissions: requestAccessibility() ignored")
    }

    package func openSystemSettings() {
        Logger.core.info("FixedPermissions: openSystemSettings() ignored")
    }
}

import Foundation
import LargeTextCore

/// Records the prompts and System Settings requests in order; `current` can change between reads, as when
/// the user grants access in System Settings.
@MainActor
package final class SpyPermissions: PermissionsProviding {
    package enum Call: Equatable, Sendable {
        case requestAccessibility
        case openSystemSettings
    }

    package var current: Permissions
    package private(set) var calls: [Call] = []

    package init(_ permissions: Permissions = .allGranted) {
        current = permissions
    }

    package func requestAccessibility() {
        calls.append(.requestAccessibility)
    }

    package func openSystemSettings() {
        calls.append(.openSystemSettings)
    }
}

import Foundation

package enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
}

package struct Permissions: Equatable, Sendable {
    package var accessibility: PermissionStatus
    package var eventPosting: PermissionStatus

    package init(accessibility: PermissionStatus, eventPosting: PermissionStatus) {
        self.accessibility = accessibility
        self.eventPosting = eventPosting
    }

    package static let allGranted = Permissions(accessibility: .granted, eventPosting: .granted)
    package static let allDenied = Permissions(accessibility: .denied, eventPosting: .denied)

    /// What the user still has to do; the status menu and Settings show the same three states.
    package var setup: PermissionSetup {
        switch (accessibility, eventPosting) {
        case (.granted, .granted): .granted
        // Spike 0i: posting may only start working after a relaunch.
        case (.granted, .denied): .needsRelaunch
        case (.denied, _): .needsGrant
        }
    }
}

/// The Accessibility setup as the user sees it, derived from `Permissions` (`Permissions.setup`).
package enum PermissionSetup: Equatable, Sendable {
    /// Nothing left to do.
    case granted
    /// Accessibility is granted but event posting isn't yet: a relaunch finishes the setup.
    case needsRelaunch
    /// Accessibility is missing: "Grant Access…".
    case needsGrant
}

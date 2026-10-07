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
}

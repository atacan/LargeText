import Foundation

package struct EditingSession: Identifiable {
    package let id: UUID
    package let target: FocusTarget

    package init(id: UUID = UUID(), target: FocusTarget) {
        self.id = id
        self.target = target
    }
}

package enum CommitMode: Equatable, Sendable {
    case insert
    case insertAndSubmit
}

package enum CancelReason: Equatable, Sendable {
    case userCancelled
    case lostFocus
}

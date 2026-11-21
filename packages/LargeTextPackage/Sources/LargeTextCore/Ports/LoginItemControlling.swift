import Foundation

/// Launch at login (`SMAppService.mainApp` in Platform). Scenarios and tests use `InMemoryLoginItem`, so they
/// never touch system state.
@MainActor
package protocol LoginItemControlling: AnyObject {
    /// Always a fresh read.
    var status: LoginItemStatus { get }
    /// Registers or unregisters the app. May leave `status` at `.requiresApproval`.
    func setEnabled(_ enabled: Bool) throws(LoginItemError)
    /// System Settings › Login Items.
    func openSystemSettings()
}

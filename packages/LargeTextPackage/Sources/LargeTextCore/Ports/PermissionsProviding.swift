import Foundation

@MainActor
package protocol PermissionsProviding: AnyObject {
    /// Always a fresh read.
    var current: Permissions { get }
    /// Shows the system prompt.
    func requestAccessibility()
    func openSystemSettings()
}

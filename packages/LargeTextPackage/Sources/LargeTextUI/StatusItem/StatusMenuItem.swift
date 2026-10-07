/// One row of the status menu, as a plain value (built by `StatusMenuModel`, rendered by `StatusItemController`).
package enum StatusMenuItem: Equatable, Sendable {
    case action(title: String, action: StatusMenuAction)
    /// Disabled, informational row.
    case info(title: String)
    case separator
}

package enum StatusMenuAction: Equatable, Sendable {
    case openEditor
    case grantAccess
    case relaunch
    case quit
}

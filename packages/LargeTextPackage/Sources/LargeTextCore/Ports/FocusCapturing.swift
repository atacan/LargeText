import Foundation

@MainActor
package protocol FocusCapturing: AnyObject {
    func captureFocus() -> FocusTarget
    /// System-wide `kAXFocusedApplicationAttribute` pid when AX is trusted, else the frontmost app's pid.
    var keyboardFocusProcessIdentifier: Int32? { get }
}

import Foundation

@MainActor
package protocol KeystrokeSending: AnyObject {
    /// Physical (HID) modifier state.
    var pressedModifiers: Modifiers { get }
    func send(_ stroke: Keystroke)
}

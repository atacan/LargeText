import Foundation

@MainActor
package protocol HotkeyRegistering: AnyObject {
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(HotkeyError) -> any HotkeyRegistration
}

@MainActor
package protocol HotkeyRegistration: AnyObject {
    func unregister()
}

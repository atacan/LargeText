import Foundation

/// The Settings window. It shows whatever `SettingsState` says and sends every user action as a
/// `SettingsIntent`; it never writes preferences itself.
@MainActor
package protocol SettingsPresenting: AnyObject {
    /// Shows the window, or brings it to the front with the new state when it is already shown.
    func show(_ state: SettingsState, intents: @escaping @MainActor (SettingsIntent) -> Void)
    /// Replaces the shown state; ignored when the window isn't shown.
    func update(_ state: SettingsState)
    /// Whether the window is on screen. The permission refresh stops once this is false.
    var isVisible: Bool { get }
}

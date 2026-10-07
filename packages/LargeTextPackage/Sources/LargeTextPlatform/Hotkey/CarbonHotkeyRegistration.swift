import Carbon.HIToolbox
import LargeTextCore

/// A live Carbon hotkey. Keeps its registrar alive until `unregister()` is called.
@MainActor
final class CarbonHotkeyRegistration: HotkeyRegistration {
    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private let registrar: CarbonHotkeyRegistrar

    init(identifier: UInt32, hotKeyRef: EventHotKeyRef, registrar: CarbonHotkeyRegistrar) {
        self.identifier = identifier
        self.hotKeyRef = hotKeyRef
        self.registrar = registrar
    }

    /// Idempotent.
    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
        registrar.removeHandler(identifier: identifier)
    }
}

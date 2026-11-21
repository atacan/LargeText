import Foundation

/// Registers the two global shortcuts as one unit (Settings plan §3.8). Kit's `HotkeyBindings` is the live
/// implementation; Settings rebinds through it, so a recorded combo can be tried and rolled back.
@MainActor
package protocol ShortcutBinding: AnyObject {
    /// Unregisters both, then registers the editor and, when non-nil, the reader (with `HotkeyConflicts`).
    /// Unregistering first means two combos that swap slots never collide: Carbon refuses a combo this
    /// process still holds (`eventHotKeyExistsErr`). Returns the slots that couldn't be registered.
    @discardableResult
    func apply(editor: KeyCombo, reader: KeyCombo?) -> [ShortcutSlot: HotkeyError]
    /// Unregisters both while a recorder is recording; the next `apply` registers them again.
    func suspend()
    /// The combos the last `apply` couldn't register, editor first; the status menu lists them.
    var unavailable: [KeyCombo] { get }
    /// The slots the last `apply` couldn't register. Unlike `unavailable`, it tells the two apart when both
    /// combos are equal. Not changed by `suspend()`.
    var unavailableSlots: Set<ShortcutSlot> { get }
}

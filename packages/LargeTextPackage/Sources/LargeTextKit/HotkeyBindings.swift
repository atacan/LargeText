import LargeTextCore
import os

/// The two global shortcuts, registered as one unit (§4.10, Settings plan §3.8). `AppController` owns it and
/// applies the stored combos at launch; Settings will rebind through `ShortcutBinding` while the app runs.
///
/// It tells the user nothing itself: `AppController` turns the failures of the launch-time `apply` into
/// notices, and a rebind from Settings shows them next to the recorder instead.
@MainActor
package final class HotkeyBindings: ShortcutBinding {
    /// The combos the last `apply` couldn't register, editor first.
    package private(set) var unavailable: [KeyCombo] = []
    /// The slots the last `apply` couldn't register.
    package private(set) var unavailableSlots: Set<ShortcutSlot> = []
    /// The editor combo of the last `apply`, registered or not; `nil` before the first one.
    package private(set) var editorCombo: KeyCombo?
    /// The reader combo of the last `apply`, registered or not; `nil` when the reader is off.
    package private(set) var readerCombo: KeyCombo?
    /// Called after every `apply`, so the status menu can show the new combos and `unavailable`.
    package var onChange: (@MainActor () -> Void)?

    private let hotkeys: any HotkeyRegistering
    private let onEditor: @MainActor () -> Void
    private let onReader: @MainActor (HotkeyEvent) -> Void
    private var editorRegistration: (any HotkeyRegistration)?
    private var readerRegistration: (any HotkeyRegistration)?

    /// Stores only; nothing is registered before `apply`.
    /// - Parameters:
    ///   - onEditor: each press of the editor shortcut.
    ///   - onReader: each press and release of the reader shortcut, stamped by the registrar.
    package init(
        hotkeys: any HotkeyRegistering,
        onEditor: @escaping @MainActor () -> Void,
        onReader: @escaping @MainActor (HotkeyEvent) -> Void
    ) {
        self.hotkeys = hotkeys
        self.onEditor = onEditor
        self.onReader = onReader
    }

    @discardableResult
    package func apply(editor: KeyCombo, reader: KeyCombo?) -> [ShortcutSlot: HotkeyError] {
        unregisterAll()
        editorCombo = editor
        readerCombo = reader

        var failures: [ShortcutSlot: HotkeyError] = [:]
        do {
            editorRegistration = try hotkeys.registerPressOnly(editor, onEditor)
        } catch {
            failures[.editor] = error
        }
        if let reader {
            // An equal combo would steal the editor's shortcut: the reader isn't registered then (§4.10).
            do {
                let combo = try HotkeyConflicts.validate(editor: editor, reader: reader).get()
                readerRegistration = try hotkeys.register(combo, handler: onReader)
            } catch {
                failures[.reader] = error
            }
        } else {
            Logger.kit.info("Reader shortcut is off; not registered")
        }

        unavailableSlots = Set(failures.keys)
        unavailable = ShortcutSlot.allCases.compactMap { slot in
            guard case .unavailable(let combo) = failures[slot] else { return nil }
            Logger.kit.error("Hotkey unavailable (\(String(describing: slot), privacy: .public)): \(String(describing: combo), privacy: .public)")
            return combo
        }
        onChange?()
        return failures
    }

    /// Leaves `unavailable`, `unavailableSlots` and the combos as they are, so the menu doesn't change while
    /// recording.
    package func suspend() {
        unregisterAll()
        Logger.kit.info("Shortcuts suspended")
    }

    private func unregisterAll() {
        editorRegistration?.unregister()
        editorRegistration = nil
        readerRegistration?.unregister()
        readerRegistration = nil
    }
}

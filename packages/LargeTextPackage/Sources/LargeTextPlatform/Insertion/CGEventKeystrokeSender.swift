import Carbon.HIToolbox
import CoreGraphics
import LargeTextCore
import os

/// Posts synthesized key events to the HID event tap (§2.5 steps 7–8). Requires event-posting access;
/// `CGEvent.post` fails silently without it, so callers gate on `PermissionsProviding` first.
@MainActor
package final class CGEventKeystrokeSender: KeystrokeSending {
    package init() {}

    /// Physical (HID) modifier state, independent of our private event source.
    package var pressedModifiers: Modifiers {
        Modifiers(cgEventFlags: CGEventSource.flagsState(.hidSystemState))
    }

    package func send(_ stroke: Keystroke) {
        // A private source keeps the user's physical modifier state out of our events.
        guard let source = CGEventSource(stateID: .privateState) else {
            Logger.platform.error("CGEventSource(.privateState) unavailable; \(String(describing: stroke)) not sent")
            return
        }
        switch stroke {
        case .paste:
            let command = CGKeyCode(kVK_Command)
            let v = KeyboardLayoutResolver.pasteKeyCode()
            post(source, command, keyDown: true, flags: .maskCommand)
            post(source, v, keyDown: true, flags: .maskCommand)
            post(source, v, keyDown: false, flags: .maskCommand)
            post(source, command, keyDown: false, flags: [])
            Logger.platform.info("Posted ⌘V (keyCode \(v))")
        case .returnKey:
            let returnKey = CGKeyCode(kVK_Return)
            post(source, returnKey, keyDown: true, flags: [])
            post(source, returnKey, keyDown: false, flags: [])
            Logger.platform.info("Posted ↩")
        }
    }

    private func post(_ source: CGEventSource, _ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            Logger.platform.error("Could not create key event for keyCode \(keyCode)")
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

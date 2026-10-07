import AppKit
import LargeTextCore

extension KeyInput {
    package init(event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: Modifiers(eventFlags: event.modifierFlags)
        )
    }
}

extension Modifiers {
    /// Drops Caps Lock, fn, numeric pad and help flags.
    package init(eventFlags flags: NSEvent.ModifierFlags) {
        var result: Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        self = result
    }
}

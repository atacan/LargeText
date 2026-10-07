import Carbon.HIToolbox
import CoreGraphics
import os

/// Finds the virtual key code that produces a character in the current **ASCII-capable** keyboard layout
/// (§2.5 step 7), so ⌘V works on Dvorak, AZERTY, and when a non-Latin layout (Russian, …) is active.
///
/// Resolved on every call (no cache): the user can switch layouts at any time, and the lookup is cheap.
/// Text Input Sources must be used on the main thread.
@MainActor
package enum KeyboardLayoutResolver {
    /// Key code for "v" with ⌘ held, falling back to `kVK_ANSI_V`.
    package static func pasteKeyCode() -> CGKeyCode {
        keyCode(for: "v", modifiers: UInt32(cmdKey)) ?? CGKeyCode(kVK_ANSI_V)
    }

    /// `carbonModifiers` uses Carbon masks (`cmdKey`, `shiftKey`, …).
    package static func keyCode(for character: String, modifiers carbonModifiers: UInt32) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            Logger.platform.notice("No ASCII-capable Unicode key layout; using kVK_ANSI_V")
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue()
        let keyboardType = UInt32(LMGetKbdType())
        let modifierKeyState = (carbonModifiers >> 8) & 0xFF

        return withExtendedLifetime(source) {
            guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            return search(for: character) { keyCode in
                translate(keyCode, layout: layout, modifierKeyState: modifierKeyState, keyboardType: keyboardType)
            }
        }
    }

    /// Pure search over the 128 virtual key codes; `translate` returns the produced string for a key code.
    nonisolated package static func search(for character: String, translate: (UInt16) -> String?) -> CGKeyCode? {
        let target = character.lowercased()
        for keyCode in UInt16(0)..<128 where translate(keyCode)?.lowercased() == target {
            return CGKeyCode(keyCode)
        }
        return nil
    }

    private static func translate(
        _ keyCode: UInt16,
        layout: UnsafePointer<UCKeyboardLayout>,
        modifierKeyState: UInt32,
        keyboardType: UInt32
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierKeyState,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

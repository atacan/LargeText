import Carbon.HIToolbox
import CoreGraphics
import LargeTextCore
import Testing
@testable import LargeTextPlatform

@Suite struct ModifierMappingTests {
    @Test func carbonFlagsForDefaultHotkey() {
        let flags = CarbonModifierFlags.flags(for: [.control, .option, .command])
        #expect(flags == UInt32(controlKey | optionKey | cmdKey))
        #expect(CarbonModifierFlags.flags(for: []) == 0)
        #expect(CarbonModifierFlags.flags(for: .shift) == UInt32(shiftKey))
    }

    @Test func cgEventFlagsRoundTrip() {
        let all: Modifiers = [.command, .option, .control, .shift]
        #expect(Modifiers(cgEventFlags: all.cgEventFlags) == all)
        #expect(Modifiers(cgEventFlags: []) == [])
    }

    @Test func cgEventFlagsIgnoreUntrackedBits() {
        let flags: CGEventFlags = [.maskCommand, .maskAlphaShift, .maskNumericPad, .maskSecondaryFn]
        #expect(Modifiers(cgEventFlags: flags) == .command)
    }

    @Test func layoutSearchFindsFirstMatchingKeyCode() {
        // Dvorak-like: "v" sits on kVK_ANSI_Period (0x2F).
        let table: [UInt16: String] = [0x09: "k", 0x2F: "v", 0x30: "\t"]
        #expect(KeyboardLayoutResolver.search(for: "v") { table[$0] } == 0x2F)
        #expect(KeyboardLayoutResolver.search(for: "V") { table[$0] } == 0x2F)
        #expect(KeyboardLayoutResolver.search(for: "q") { table[$0] } == nil)
    }
}

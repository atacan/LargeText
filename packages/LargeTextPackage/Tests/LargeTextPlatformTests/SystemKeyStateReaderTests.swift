import CoreGraphics
import LargeTextCore
import Testing
@testable import LargeTextPlatform

@Suite struct SystemKeyStateReaderTests {
    let combo = KeyCombo.readerDefault  // ⌃⌥⌘R
    let held: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    @Test func maskHasExactlyTheCombosModifiers() {
        #expect(SystemKeyStateReader.modifierMask(for: combo) == held)
        #expect(SystemKeyStateReader.modifierMask(for: KeyCombo(keyCode: 0x0F, modifiers: .shift)) == .maskShift)
    }

    @Test func keyStateNeedsTheKeyAndAllModifiers() {
        #expect(SystemKeyStateReader.isDown(keyDown: true, flags: held, combo: combo))
        #expect(!SystemKeyStateReader.isDown(keyDown: false, flags: held, combo: combo))
        #expect(!SystemKeyStateReader.isDown(keyDown: true, flags: [.maskControl, .maskCommand], combo: combo))
    }

    @Test func extraModifiersAndUntrackedBitsDontCountAsRelease() {
        let flags = held.union([.maskShift, .maskAlphaShift, .maskSecondaryFn])
        #expect(SystemKeyStateReader.isDown(keyDown: true, flags: flags, combo: combo))
        #expect(SystemKeyStateReader.modifiersDown(flags: flags, combo: combo) == true)
    }

    @Test func fallbackSaysReleasedWhenAnyModifierIsUp() {
        #expect(SystemKeyStateReader.modifiersDown(flags: held, combo: combo) == true)
        #expect(SystemKeyStateReader.modifiersDown(flags: [.maskControl, .maskAlternate], combo: combo) == false)
        #expect(SystemKeyStateReader.modifiersDown(flags: [], combo: combo) == false)
    }

    @Test func fallbackIsUnknownForAComboWithoutModifiers() {
        let bare = KeyCombo(keyCode: 0x0F, modifiers: [])
        #expect(SystemKeyStateReader.modifiersDown(flags: held, combo: bare) == nil)
    }
}

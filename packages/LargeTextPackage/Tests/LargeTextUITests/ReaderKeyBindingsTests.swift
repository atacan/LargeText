import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("ReaderKeyBindings")
struct ReaderKeyBindingsTests {
    private typealias K = ANSIKeyCode

    private func action(_ keyCode: UInt16, _ characters: String?, _ modifiers: Modifiers = []) -> ReaderAction? {
        ReaderKeyBindings.action(for: KeyInput(keyCode: keyCode, charactersIgnoringModifiers: characters, modifiers: modifiers))
    }

    @Test func escapeCloses() {
        #expect(action(K.escape, "\u{1B}") == .close)
    }

    @Test func modifiedEscapeFallsThrough() {
        #expect(action(K.escape, "\u{1B}", .command) == nil)
        #expect(action(K.escape, "\u{1B}", .shift) == nil)
    }

    @Test func zoom() {
        #expect(action(K.equal, "=", .command) == .zoom(.bigger))
        #expect(action(K.equal, "+", [.command, .shift]) == .zoom(.bigger))
        #expect(action(K.minus, "-", .command) == .zoom(.smaller))
        #expect(action(K.zero, "0", .command) == .zoom(.reset))
    }

    @Test func copyAndSelectAll() {
        #expect(action(K.c, "c", .command) == .copy)
        #expect(action(K.a, "a", .command) == .selectAll)
    }

    @Test func copyAndSelectAllOnNonUSLayouts() {
        #expect(action(K.c, "с", .command) == .copy)          // Russian
        #expect(action(K.a, "ф", .command) == .selectAll)     // Russian
        #expect(action(0x22, "c", .command) == .copy)         // Dvorak "c" on ANSI "i"
        #expect(action(0x0C, "a", .command) == .selectAll)    // AZERTY "a" on ANSI "q"
        #expect(action(K.equal, "´", .command) == .zoom(.bigger)) // German
    }

    /// The card is read-only: editing shortcuts are left to AppKit (which ignores them).
    @Test func editingShortcutsFallThrough() {
        #expect(action(K.v, "v", .command) == nil)
        #expect(action(K.x, "x", .command) == nil)
        #expect(action(K.z, "z", .command) == nil)
        #expect(action(K.z, "z", [.command, .shift]) == nil)
    }

    @Test func plainKeysFallThrough() {
        #expect(action(K.returnKey, "\r") == nil)
        #expect(action(K.c, "c") == nil)
        #expect(action(0x7D, "\u{F701}") == nil) // ↓ scrolls
    }
}

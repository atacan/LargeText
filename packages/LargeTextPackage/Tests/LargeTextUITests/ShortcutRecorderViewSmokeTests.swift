import AppKit
import LargeTextCore
import Testing
@testable import LargeTextUI

/// Drives a real `ShortcutRecorderView` in an off-screen window with synthesized key events. Nothing is made
/// key or active, so the test process's focus is left alone.
@MainActor
@Suite("ShortcutRecorderView smoke", .enabled(if: !NSScreen.screens.isEmpty))
struct ShortcutRecorderViewSmokeTests {
    final class Calls {
        var begins = 0
        var records: [KeyCombo] = []
        var cancels = 0
    }

    /// Records ⎋ reaching the window, like `SettingsWindow`'s close-on-⎋.
    final class CancelWindow: NSWindow {
        var cancels = 0
        override func cancelOperation(_ sender: Any?) { cancels += 1 }
    }

    let calls = Calls()
    let window: CancelWindow
    let recorder: ShortcutRecorderView
    let other = NSTextField(string: "")

    init() {
        _ = NSApplication.shared
        window = CancelWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        recorder = ShortcutRecorderView(frame: NSRect(x: 10, y: 10, width: 132, height: 24))
        other.frame = NSRect(x: 160, y: 10, width: 100, height: 24)
        window.contentView?.addSubview(recorder)
        window.contentView?.addSubview(other)
        recorder.title = "Open Large Editor"
        recorder.combo = .default
        let calls = calls
        recorder.onBeginRecording = { calls.begins += 1 }
        recorder.onRecord = { calls.records.append($0) }
        recorder.onCancel = { calls.cancels += 1 }
    }

    private func key(
        _ keyCode: UInt16,
        _ characters: String,
        _ flags: NSEvent.ModifierFlags = [],
        type: NSEvent.EventType = .keyDown
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func startRecording() {
        window.makeFirstResponder(recorder)
        recorder.keyDown(with: key(ANSIKeyCode.space, " "))
    }

    @Test func idleShowsTheComboAndIsAnAccessibleButton() {
        #expect(recorder.displayedText == "⌃⌥⌘T")
        #expect(recorder.accessibilityRole() == .button)
        #expect(recorder.accessibilityLabel() == "Open Large Editor")
        #expect(recorder.accessibilityValue() as? String == "⌃⌥⌘T")
        #expect(recorder.isAccessibilityElement())

        recorder.combo = nil
        #expect(recorder.displayedText == "Off")
    }

    @Test func takingFocusDoesNotRecordButSpaceDoes() {
        window.makeFirstResponder(recorder)
        #expect(window.firstResponder === recorder)
        #expect(!recorder.isRecording)
        #expect(calls.begins == 0)

        recorder.keyDown(with: key(0x00, "a"))
        #expect(!recorder.isRecording)

        recorder.keyDown(with: key(ANSIKeyCode.space, " "))
        #expect(recorder.isRecording)
        #expect(calls.begins == 1)
        #expect(recorder.displayedText == "Type Shortcut")
    }

    @Test func accessibilityPressStartsRecording() {
        #expect(recorder.accessibilityPerformPress())
        #expect(recorder.isRecording)
        #expect(window.firstResponder === recorder)
        #expect(calls.begins == 1)
    }

    @Test func modifiersShowLiveAndAKeyRecordsTheCombo() {
        startRecording()

        recorder.flagsChanged(with: key(0x3B, "", [.control, .option], type: .flagsChanged))
        #expect(recorder.displayedText == "⌃⌥…")
        #expect(recorder.accessibilityValue() as? String == "⌃⌥…")

        recorder.keyDown(with: key(0x0E, "e", [.control, .option, .command]))
        #expect(calls.records == [KeyCombo(keyCode: 0x0E, modifiers: [.control, .option, .command])])
        #expect(!recorder.isRecording)
        #expect(calls.cancels == 0)
    }

    @Test func commandCombosArriveThroughKeyEquivalents() {
        startRecording()

        #expect(recorder.performKeyEquivalent(with: key(0x28, "k", [.command, .shift])))
        #expect(calls.records == [KeyCombo(keyCode: 0x28, modifiers: [.command, .shift])])
    }

    /// `performKeyEquivalent` reaches every view of the window, so only the recording first responder takes it.
    @Test func keyEquivalentsAreLeftAloneUnlessRecordingAndFocused() {
        #expect(!recorder.performKeyEquivalent(with: key(0x28, "k", .command)))

        startRecording()
        window.makeFirstResponder(other)
        recorder.isRecording = true    // as if the state still said so
        #expect(!recorder.performKeyEquivalent(with: key(0x28, "k", .command)))
        #expect(calls.records.isEmpty)
    }

    @Test func escapeCancelsAndModifierKeysAloneDoNothing() {
        startRecording()

        recorder.keyDown(with: key(0x38, "", .shift))
        #expect(recorder.isRecording)

        recorder.keyDown(with: key(ANSIKeyCode.escape, "\u{1B}"))
        #expect(calls.cancels == 1)
        #expect(!recorder.isRecording)
        #expect(calls.records.isEmpty)
        #expect(recorder.displayedText == "⌃⌥⌘T")
    }

    /// The window's ⎋-closes handler must not run while recording.
    @Test func cancelOperationIsSwallowedWhileRecording() {
        startRecording()

        recorder.cancelOperation(nil)

        #expect(calls.cancels == 1)
        #expect(!recorder.isRecording)
    }

    @Test func escapeWhileIdleReachesTheWindow() {
        window.makeFirstResponder(recorder)

        recorder.keyDown(with: key(ANSIKeyCode.escape, "\u{1B}"))
        #expect(window.cancels == 1)
        recorder.cancelOperation(nil)
        #expect(window.cancels == 2)
        #expect(calls.cancels == 0)
    }

    @Test func escapeWhileRecordingDoesNotReachTheWindow() {
        startRecording()
        recorder.cancelOperation(nil)
        #expect(window.cancels == 0)
        #expect(calls.cancels == 1)

        startRecording()
        recorder.keyDown(with: key(ANSIKeyCode.escape, "\u{1B}"))
        #expect(window.cancels == 0)
        #expect(calls.cancels == 2)
    }

    @Test func losingFocusWhileRecordingCancels() {
        startRecording()

        window.makeFirstResponder(other)

        #expect(calls.cancels == 1)
        #expect(!recorder.isRecording)

        window.makeFirstResponder(recorder)
        window.makeFirstResponder(other)
        #expect(calls.cancels == 1)
    }

    @Test func stateEndingTheRecordingResetsTheDisplay() {
        startRecording()
        recorder.flagsChanged(with: key(0x3B, "", .control, type: .flagsChanged))

        recorder.isRecording = false
        #expect(recorder.displayedText == "⌃⌥⌘T")

        recorder.isRecording = true
        #expect(recorder.displayedText == "Type Shortcut")
    }
}

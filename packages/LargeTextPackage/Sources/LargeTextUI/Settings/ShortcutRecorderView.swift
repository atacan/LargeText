import AppKit
import LargeTextCore

/// The shortcut field in Settings (Settings plan §3.8, §4). AppKit, because SwiftUI can't see ⌘ combos before
/// the menu does or modifier changes on their own.
///
/// A click, Space or Return (or VoiceOver's press) starts a recording; `onBeginRecording` lets the
/// coordinator suspend both global shortcuts. Taking focus with Tab doesn't, so opening the window never
/// pauses them. While recording:
/// - `keyDown` and `performKeyEquivalent` (where ⌘ combos arrive first, before the main menu) go through
///   `ShortcutKeyInterpreter`: a candidate goes to `onRecord`, ⎋ to `onCancel`;
/// - `flagsChanged` shows the modifiers held so far ("⌃⌥…");
/// - `cancelOperation` is swallowed, so ⎋ doesn't also close the window;
/// - losing first responder cancels.
///
/// `isRecording` is set from `SettingsState` by `ShortcutRecorderRepresentable`; the view only sets it itself
/// to start (so the very next key counts) and to stop when it sends a combo or a cancel.
@MainActor
package final class ShortcutRecorderView: NSView {
    package var combo: KeyCombo? {
        didSet { if combo != oldValue { refresh() } }
    }

    package var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            liveModifiers = []
            refresh()
        }
    }

    /// The row shows a problem: the border turns red.
    package var hasProblem = false {
        didSet { if hasProblem != oldValue { needsDisplay = true } }
    }

    /// The accessibility label: the shortcut's name.
    package var title = "" {
        didSet { setAccessibilityLabel(title) }
    }

    package var onBeginRecording: @MainActor () -> Void = {}
    package var onRecord: @MainActor (KeyCombo) -> Void = { _ in }
    package var onCancel: @MainActor () -> Void = {}

    /// What the field shows now; also its accessibility value.
    package var displayedText: String { label.stringValue }

    private var liveModifiers: Modifiers = [] {
        didSet { if liveModifiers != oldValue { refresh() } }
    }

    private let label = NSTextField(labelWithString: "")

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityRoleDescription(SettingsStrings.recorderRoleDescription)
        setAccessibilityHelp(SettingsStrings.recorderHelp)
        toolTip = SettingsStrings.recorderHelp
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout and drawing

    package override var intrinsicContentSize: NSSize {
        NSSize(width: 132, height: 24)
    }

    package override var isFlipped: Bool { true }

    package override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .controlBackgroundColor).setFill()
        path.fill()
        let border: NSColor = if hasProblem && !isRecording {
            .systemRed
        } else if isRecording {
            .controlAccentColor
        } else {
            .separatorColor
        }
        border.setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()
    }

    package override var focusRingMaskBounds: NSRect { bounds }

    package override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    // MARK: - Responder

    package override var acceptsFirstResponder: Bool { true }

    package override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    package override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isRecording {
            cancel()
        }
        return resigned
    }

    package override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !isRecording {
            beginRecording()
        }
    }

    package override func keyDown(with event: NSEvent) {
        guard isRecording else {
            let input = KeyInput(event: event)
            if Self.startsRecording(input) {
                beginRecording()
            } else if input.isEscape, input.modifiers.isEmpty {
                cancelOperation(self)
            } else {
                super.keyDown(with: event)
            }
            return
        }
        handle(KeyInput(event: event))
    }

    /// Sent to every view of the key window before the main menu, so it must check that this one is the
    /// recording first responder.
    package override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handle(KeyInput(event: event))
        return true
    }

    package override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        liveModifiers = Modifiers(eventFlags: event.modifierFlags)
    }

    /// ⎋ while recording only cancels the recording; otherwise it goes on up the responder chain to the
    /// window, which closes. (`NSResponder` itself doesn't implement `cancelOperation(_:)`, so no `super`.)
    package override func cancelOperation(_ sender: Any?) {
        if isRecording {
            cancel()
        } else {
            nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
        }
    }

    // MARK: - Accessibility

    package override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        if !isRecording {
            beginRecording()
        }
        return true
    }

    // MARK: - Recording

    /// Space, Return or Enter with no modifiers on a focused, idle recorder: like pressing a button.
    static func startsRecording(_ input: KeyInput) -> Bool {
        guard input.modifiers.isEmpty else { return false }
        return input.keyCode == ANSIKeyCode.space || input.keyCode == ANSIKeyCode.returnKey || input.keyCode == ANSIKeyCode.keypadEnter
    }

    /// What a key press does while recording; `keyDown` and `performKeyEquivalent` both end here.
    func handle(_ input: KeyInput) {
        switch ShortcutKeyInterpreter.interpret(input) {
        case .cancel:
            cancel()
        case .candidate(let combo):
            isRecording = false
            onRecord(combo)
        case .ignore:
            break
        }
    }

    private func beginRecording() {
        isRecording = true
        onBeginRecording()
    }

    private func cancel() {
        isRecording = false
        onCancel()
    }

    private func refresh() {
        let text: String
        if isRecording {
            text = SettingsStrings.recording(liveModifiers)
            label.textColor = liveModifiers.isEmpty ? .secondaryLabelColor : .labelColor
        } else {
            text = SettingsStrings.combo(combo)
            label.textColor = combo == nil ? .secondaryLabelColor : .labelColor
        }
        label.stringValue = text
        setAccessibilityValue(text)
        needsDisplay = true
    }
}

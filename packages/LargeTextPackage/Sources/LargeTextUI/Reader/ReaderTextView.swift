import AppKit
import LargeTextCore

/// The reader card's text: read-only, selectable, plain text. Intercepts keys per `ReaderKeyBindings`.
@MainActor
package final class ReaderTextView: NSTextView {
    /// Receives ⎋ and zoom. ⌘C and ⌘A are performed directly.
    package var onAction: ((ReaderAction) -> Void)?

    /// A TextKit 1 text view configured like the editor's, but read-only.
    package static func make() -> ReaderTextView {
        let view = ReaderTextView(usingTextLayoutManager: false)
        view.applyReaderConfiguration()
        return view
    }

    private func applyReaderConfiguration() {
        isEditable = false
        isSelectable = true
        isRichText = false
        importsGraphics = false
        allowsUndo = false
        usesFindBar = false
        usesFontPanel = false
        usesRuler = false
        usesInspectorBar = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        if #available(macOS 15.0, *) {
            writingToolsBehavior = .none
        }

        drawsBackground = false
        textColor = Theme.textColor
        selectedTextAttributes = [
            .backgroundColor: Theme.selectionColor,
            .foregroundColor: Theme.textColor,
        ]
        textContainerInset = Theme.textContainerInset

        // Scrollable, wrapping text view inside an NSScrollView.
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    /// Replaces the whole (plain) text, styled with `font` and `color`, and clears the selection.
    package func setText(_ text: String, font: NSFont, color: NSColor) {
        string = text
        self.font = font
        textColor = color
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    // MARK: - Key handling (§4.5)

    override package func keyDown(with event: NSEvent) {
        guard let action = ReaderKeyBindings.action(for: KeyInput(event: event)) else {
            super.keyDown(with: event)
            return
        }
        perform(action)
    }

    /// The package never installs `NSApp.mainMenu`, so ⌘-shortcuts must be handled here.
    override package func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit calls this on every view in the window; only the first responder may act.
        guard window?.firstResponder === self else { return false }
        guard let action = ReaderKeyBindings.action(for: KeyInput(event: event)) else {
            return super.performKeyEquivalent(with: event)
        }
        perform(action)
        return true
    }

    package func perform(_ action: ReaderAction) {
        switch action {
        case .copy: copy(nil)
        case .selectAll: selectAll(nil)
        case .close, .zoom: onAction?(action)
        }
    }
}

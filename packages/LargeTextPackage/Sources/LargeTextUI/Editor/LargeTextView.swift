import AppKit
import LargeTextCore

/// The overlay's text view. Owns the text being edited (§3.1); intercepts keys per §2.3.
@MainActor
package final class LargeTextView: NSTextView {
    /// Receives every non-`nil` `EditorAction`. The owner maps it to an intent or a local action.
    package var onAction: ((EditorAction) -> Void)?

    /// A TextKit 1 text view configured for the overlay: plain text, undo on, every "smart" feature off.
    package static func make() -> LargeTextView {
        let view = LargeTextView(usingTextLayoutManager: false)
        view.applyOverlayConfiguration()
        return view
    }

    private func applyOverlayConfiguration() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = false
        usesFontPanel = false
        usesRuler = false
        usesInspectorBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false
        if #available(macOS 15.0, *) {
            writingToolsBehavior = .none
        }
        if #available(macOS 15.4, *) {
            // Inline predictions would paint grey suggestion text at 64 pt.
            inlinePredictionType = .no
        }

        drawsBackground = false
        textColor = Theme.textColor
        insertionPointColor = Theme.insertionPointColor
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

    /// Applies `font` to the whole (plain) text and to typing.
    package func applyFont(_ newFont: NSFont) {
        font = newFont
        typingAttributes = [.font: newFont, .foregroundColor: Theme.textColor]
    }

    // MARK: - Key handling (§2.3)

    override package func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        guard let action = EditorKeyBindings.action(for: KeyInput(event: event)) else {
            super.keyDown(with: event)
            return
        }
        dispatch(action)
    }

    override package func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit calls this on every view in the window; only the first responder may act.
        guard window?.firstResponder === self else { return false }
        if hasMarkedText() { return super.performKeyEquivalent(with: event) }
        guard let action = EditorKeyBindings.action(for: KeyInput(event: event)) else {
            return super.performKeyEquivalent(with: event)
        }
        dispatch(action)
        return true
    }

    private func dispatch(_ action: EditorAction) {
        if let onAction {
            onAction(action)
        } else {
            performLocally(action)
        }
    }

    /// Fallback when nobody listens (e.g. previews): local actions only.
    private func performLocally(_ action: EditorAction) {
        switch action {
        case .newline: insertNewlineIgnoringFieldEditor(nil)
        case .standardEdit(let edit): perform(edit)
        case .commit, .cancel, .zoom, .openSettings: break
        }
    }

    // MARK: - Standard edits (direct calls, never the responder chain)

    package func perform(_ edit: StandardEdit) {
        switch edit {
        case .undo:
            breakUndoCoalescing()
            guard let undoManager, undoManager.canUndo else { return }
            undoManager.undo()
        case .redo:
            guard let undoManager, undoManager.canRedo else { return }
            undoManager.redo()
        case .cut: cut(nil)
        case .copy: copy(nil)
        case .paste: paste(nil)
        case .selectAll: selectAll(nil)
        }
    }
}

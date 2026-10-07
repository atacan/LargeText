import AppKit
import LargeTextCore
import os

/// The live `OverlayPresenting`: a reused, non-activating full-screen panel hosting `EditorViewController`.
///
/// - Never activates the app and never touches `NSApp.mainMenu`.
/// - Resign-key rule (§2.2): any resign-key not caused by `dismiss()` emits `.cancel(.lostFocus)` once.
/// - From the first line of `dismiss()` on, no intent is emitted.
@MainActor
package final class OverlayWindowController: OverlayPresenting {
    private let reduceMotion: @MainActor () -> Bool

    private var panel: OverlayPanel?
    private var editor: EditorViewController?

    private var sessionID: UUID?
    private var intents: (@MainActor (OverlayIntent) -> Void)?
    private var isDismissing = false
    private var didReportLostFocus = false
    /// Bumped by every `present`, so a slow fade-out never hides a newer presentation.
    private var generation = 0

    /// - Parameter reduceMotion: read at each fade; `true` makes fades instant.
    package init(
        reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.reduceMotion = reduceMotion
    }

    // MARK: - OverlayPresenting

    package func present(
        sessionID: UUID,
        initialText: String,
        chrome: OverlayChrome,
        intents: @escaping @MainActor (OverlayIntent) -> Void
    ) {
        let (panel, editor) = makePanelIfNeeded()
        generation += 1
        self.sessionID = sessionID
        self.intents = intents
        isDismissing = false
        didReportLostFocus = false

        if let screen = NSScreen.resolve(targetFrame: chrome.targetFrame) {
            // `screen.frame`, not `visibleFrame`: the backdrop also covers that screen's menu bar.
            panel.setFrame(screen.frame, display: false)
        }
        editor.render(chrome)
        editor.setInitialText(initialText)
        editor.view.layoutSubtreeIfNeeded()

        let animated = !reduceMotion()
        panel.alphaValue = animated ? 0 : 1
        panel.makeFirstResponder(editor.textView)
        panel.makeKeyAndOrderFront(nil)
        // The panel is reused across sessions: never let ⌘Z reach into the previous session.
        editor.textView.undoManager?.removeAllActions()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.fadeDuration
                panel.animator().alphaValue = 1
            }
        }
        Logger.ui.debug("Overlay presented (\(initialText.count) initial chars)")
    }

    package func update(_ chrome: OverlayChrome) {
        editor?.render(chrome)
    }

    package func dismiss() async -> String {
        // Stop emitting before anything else: our own orderOut causes a resign-key.
        isDismissing = true
        intents = nil
        sessionID = nil
        guard let panel, let editor else { return "" }

        let textView = editor.textView
        textView.inputContext?.discardMarkedText()
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        let text = textView.string

        if panel.isVisible {
            let dismissedGeneration = generation
            await fade(panel, to: 0)
            if dismissedGeneration == generation {
                panel.orderOut(nil)
            }
        }
        Logger.ui.debug("Overlay dismissed (\(text.count) chars)")
        return text
    }

    // MARK: - Private

    private func makePanelIfNeeded() -> (OverlayPanel, EditorViewController) {
        if let panel, let editor { return (panel, editor) }
        let panel = OverlayPanel()
        let editor = EditorViewController()
        editor.view.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = editor.view
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        editor.onIntent = { [weak self] kind in self?.emit(kind) }
        self.panel = panel
        self.editor = editor
        return (panel, editor)
    }

    private func panelDidResignKey() {
        guard !isDismissing, !didReportLostFocus, sessionID != nil else { return }
        didReportLostFocus = true
        Logger.ui.info("Overlay lost key status → cancel(.lostFocus)")
        emit(.cancel(.lostFocus))
    }

    private func emit(_ kind: OverlayIntent.Kind) {
        guard !isDismissing, let sessionID, let intents else { return }
        intents(OverlayIntent(sessionID: sessionID, kind: kind))
    }

    private func fade(_ panel: NSPanel, to alpha: CGFloat) async {
        guard !reduceMotion() else {
            panel.alphaValue = alpha
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Theme.fadeDuration
                panel.animator().alphaValue = alpha
            }, completionHandler: {
                continuation.resume()
            })
        }
    }
}

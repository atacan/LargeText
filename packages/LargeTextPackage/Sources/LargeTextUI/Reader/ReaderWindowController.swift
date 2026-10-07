import AppKit
import LargeTextCore
import os

/// The live `ReaderPresenting`: its own reused `OverlayPanel` hosting `ReaderViewController`, plus the
/// `HighlightPanel` around the source (§4.5–§4.7).
///
/// - **Following:** never key, click-through, no backdrop. The panel is **only the card frame**, so the
///   system-wide hit test never lands on our pid (R4). Shown with `orderFrontRegardless()`.
/// - **Pinned:** the panel grows to `screen.frame` with the card at the same screen position, the backdrop
///   fades in and the panel becomes key. Resign key emits `.close(.lostFocus)` once; a backdrop click or
///   ⎋ emits `.close(.userCancelled)`.
/// - From the first line of `dismiss()` on, no intent is emitted.
@MainActor
package final class ReaderWindowController: ReaderPresenting {
    private let reduceMotion: @MainActor () -> Bool
    private let screens: @MainActor () -> [ScreenDescriptor]
    private let mouseLocation: @MainActor () -> CGPoint

    private(set) var panel: OverlayPanel?
    private(set) var reader: ReaderViewController?
    private var highlight: HighlightPanel?

    private var sessionID: UUID?
    private var intents: (@MainActor (ReaderIntent) -> Void)?
    private var isDismissing = false
    private var didReportLostFocus = false
    /// Bumped by every `present`, so a slow fade-out never hides a newer presentation.
    private var generation = 0

    private var mode = ReaderChrome.Mode.following
    private var sourceFrame: CGRect?
    private var pointer = CGPoint.zero
    private var screen: ScreenDescriptor?
    /// The card's frame in AppKit global coordinates.
    private(set) var cardFrame: CGRect?
    /// The following card's frame at pin time (`nil` for a direct pin). Pinned relayouts, e.g. on zoom,
    /// anchor to it so the card never wanders.
    private var pinAnchor: CGRect?

    /// - Parameters:
    ///   - reduceMotion: read at each fade; `true` makes fades instant.
    ///   - screens: the displays, in `NSScreen.screens` order.
    ///   - mouseLocation: the pointer before the first `pointerMoved(_:)`, in AppKit global coordinates.
    package init(
        reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        screens: @escaping @MainActor () -> [ScreenDescriptor] = { NSScreen.screens.map(\.descriptor) },
        mouseLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.reduceMotion = reduceMotion
        self.screens = screens
        self.mouseLocation = mouseLocation
    }

    // MARK: - ReaderPresenting

    package func present(
        sessionID: UUID,
        content: ReaderContent,
        chrome: ReaderChrome,
        intents: @escaping @MainActor (ReaderIntent) -> Void
    ) {
        let (panel, reader, highlight) = makePanelsIfNeeded()
        generation += 1
        self.sessionID = sessionID
        self.intents = intents
        isDismissing = false
        didReportLostFocus = false
        mode = chrome.mode
        sourceFrame = chrome.sourceFrame
        pointer = mouseLocation()
        screen = nil
        cardFrame = nil
        pinAnchor = nil

        reader.render(content: content, chrome: chrome)
        let animated = !reduceMotion()
        panel.alphaValue = animated ? 0 : 1
        highlight.alphaValue = panel.alphaValue

        switch chrome.mode {
        case .following: showFollowing(panel, reader)
        case .pinned: showPinned(panel, reader, anchor: nil, animated: false)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.fadeDuration
                panel.animator().alphaValue = 1
                highlight.animator().alphaValue = 1
            }
        }
        Logger.ui.debug("Reader presented (\(String(describing: chrome.mode), privacy: .public))")
    }

    package func update(content: ReaderContent, chrome: ReaderChrome) {
        guard sessionID != nil, !isDismissing, let panel, let reader else { return }
        // The mode only changes through `present` and `pin`.
        var chrome = chrome
        chrome.mode = mode
        sourceFrame = chrome.sourceFrame
        reader.render(content: content, chrome: chrome)
        switch mode {
        case .following: layoutFollowing(panel, reader)
        case .pinned: layoutPinned(panel, reader)
        }
        showHighlight()
    }

    package func pointerMoved(_ sample: PointerSample) {
        guard mode == .following, sessionID != nil, !isDismissing, let panel, let reader else { return }
        pointer = sample.appKit
        layoutFollowing(panel, reader)
    }

    package func pin(content: ReaderContent, chrome: ReaderChrome) {
        guard sessionID != nil, !isDismissing, let panel, let reader else { return }
        guard mode == .following else {
            update(content: content, chrome: chrome)
            return
        }
        var chrome = chrome
        chrome.mode = .pinned
        mode = .pinned
        sourceFrame = chrome.sourceFrame
        reader.render(content: content, chrome: chrome)
        showPinned(panel, reader, anchor: cardFrame, animated: !reduceMotion())
        Logger.ui.debug("Reader pinned")
    }

    package func dismiss() async {
        // Stop emitting before anything else: our own orderOut causes a resign-key.
        isDismissing = true
        intents = nil
        sessionID = nil
        guard let panel, let highlight else { return }

        if panel.isVisible || highlight.isVisible {
            let dismissedGeneration = generation
            await fadeOut([panel, highlight])
            if dismissedGeneration == generation {
                panel.orderOut(nil)
                highlight.orderOut(nil)
            }
        }
        Logger.ui.debug("Reader dismissed")
    }

    // MARK: - Modes

    private func showFollowing(_ panel: OverlayPanel, _ reader: ReaderViewController) {
        panel.allowsKey = false
        panel.ignoresMouseEvents = true
        reader.setBackdropVisible(false, animated: false)
        layoutFollowing(panel, reader)
        // Never `makeKeyAndOrderFront`: the target app keeps keyboard focus and hover state.
        panel.orderFrontRegardless()
        showHighlight()
    }

    /// Following → pinned keeps the card where it is (`anchor`); a direct pin (`anchor: nil`) centres it.
    private func showPinned(
        _ panel: OverlayPanel,
        _ reader: ReaderViewController,
        anchor: CGRect?,
        animated: Bool
    ) {
        pinAnchor = anchor
        panel.allowsKey = true
        panel.ignoresMouseEvents = false
        layoutPinned(panel, reader)
        reader.setBackdropVisible(true, animated: animated)
        panel.makeFirstResponder(reader.textView)
        if panel.isVisible {
            panel.makeKey()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        showHighlight()
    }

    // MARK: - Layout

    private func layoutFollowing(_ panel: OverlayPanel, _ reader: ReaderViewController) {
        let placement = ReaderPlacement.following(
            pointer: pointer,
            sourceFrame: sourceFrame,
            previous: cardFrame,
            screens: screens()
        ) { screen in
            let visible = screen.visibleFrame
            return reader.preferredCardSize(
                width: (visible.width * Theme.cardWidthFraction).rounded(),
                maxHeight: (visible.height * Theme.followingMaxHeightFraction).rounded(.down)
            )
        }
        guard let placement else { return }
        screen = placement.screen
        cardFrame = placement.cardFrame
        // The panel is the card: nothing of ours sits under the pointer outside it.
        apply(panelFrame: placement.cardFrame, cardFrame: placement.cardFrame, panel, reader)
    }

    private func layoutPinned(_ panel: OverlayPanel, _ reader: ReaderViewController) {
        guard let screen = screen ?? ScreenResolver.resolve(
            targetFrame: sourceFrame,
            mouseLocation: pointer,
            screens: screens()
        ) else { return }
        let visible = screen.visibleFrame
        let size = reader.preferredCardSize(
            width: pinAnchor?.width ?? (visible.width * Theme.cardWidthFraction).rounded(),
            maxHeight: (visible.height * Theme.editorMaxHeightFraction).rounded(.down)
        )
        let frame = ReaderPlacement.pinned(in: visible, preferredSize: size, previous: pinAnchor)
        self.screen = screen
        cardFrame = frame
        // `screen.frame`, not `visibleFrame`: the backdrop also covers that screen's menu bar.
        apply(panelFrame: screen.frame, cardFrame: frame, panel, reader)
    }

    /// Both frames in AppKit global coordinates.
    private func apply(
        panelFrame: CGRect,
        cardFrame: CGRect,
        _ panel: OverlayPanel,
        _ reader: ReaderViewController
    ) {
        if panel.frame != panelFrame {
            panel.setFrame(panelFrame, display: false)
        }
        reader.setCardFrame(cardFrame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY))
        panel.displayIfNeeded()
    }

    /// Outlines the source; above the backdrop while pinned, under the card while following.
    private func showHighlight() {
        guard let panel, let highlight else { return }
        highlight.show(around: sourceFrame)
        guard highlight.isVisible, panel.isVisible else { return }
        highlight.order(mode == .pinned ? .above : .below, relativeTo: panel.windowNumber)
    }

    // MARK: - Private

    private func makePanelsIfNeeded() -> (OverlayPanel, ReaderViewController, HighlightPanel) {
        if let panel, let reader, let highlight { return (panel, reader, highlight) }
        let panel = OverlayPanel()
        let reader = ReaderViewController()
        reader.view.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = reader.view
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        reader.onIntent = { [weak self] kind in self?.emit(kind) }
        let highlight = HighlightPanel()
        self.panel = panel
        self.reader = reader
        self.highlight = highlight
        return (panel, reader, highlight)
    }

    private func panelDidResignKey() {
        guard mode == .pinned, !isDismissing, !didReportLostFocus, sessionID != nil else { return }
        didReportLostFocus = true
        Logger.ui.info("Reader lost key status → close(.lostFocus)")
        emit(.close(.lostFocus))
    }

    private func emit(_ kind: ReaderIntent.Kind) {
        guard !isDismissing, let sessionID, let intents else { return }
        intents(ReaderIntent(sessionID: sessionID, kind: kind))
    }

    private func fadeOut(_ windows: [NSWindow]) async {
        guard !reduceMotion() else {
            windows.forEach { $0.alphaValue = 0 }
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Theme.fadeDuration
                windows.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                continuation.resume()
            })
        }
    }
}

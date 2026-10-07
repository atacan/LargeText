import Foundation
import LargeTextCore

/// Records every presenter call. With `holdDismiss`, `dismiss()` suspends until `completeDismiss()`,
/// which lets a test act while the coordinator is closing.
@MainActor
package final class SpyReaderPresenter: ReaderPresenting {
    /// One `present`, `update` or `pin`.
    package struct Shown: Equatable, Sendable {
        package var content: ReaderContent
        package var chrome: ReaderChrome

        package init(content: ReaderContent, chrome: ReaderChrome) {
            self.content = content
            self.chrome = chrome
        }
    }

    package private(set) var presented: [Shown] = []
    package private(set) var updates: [Shown] = []
    package private(set) var pins: [Shown] = []
    package private(set) var pointerSamples: [PointerSample] = []
    package private(set) var dismissCount = 0
    package private(set) var lastSessionID: UUID?
    package private(set) var lastIntents: (@MainActor (ReaderIntent) -> Void)?
    /// The most recent `present`, `update` or `pin`.
    package private(set) var lastShown: Shown?

    package var holdDismiss = false
    package var isDismissHeld: Bool { pendingDismiss != nil }

    private let log: EventLog?
    private var pendingDismiss: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    package init(log: EventLog? = nil) {
        self.log = log
    }

    package func present(
        sessionID: UUID,
        content: ReaderContent,
        chrome: ReaderChrome,
        intents: @escaping @MainActor (ReaderIntent) -> Void
    ) {
        let shown = Shown(content: content, chrome: chrome)
        presented.append(shown)
        lastShown = shown
        lastSessionID = sessionID
        lastIntents = intents
        log?.append(.readerPresent(content, chrome.mode))
    }

    package func update(content: ReaderContent, chrome: ReaderChrome) {
        let shown = Shown(content: content, chrome: chrome)
        updates.append(shown)
        lastShown = shown
        log?.append(.readerUpdate(content))
    }

    /// Not logged to the `EventLog`: it fires on every tick.
    package func pointerMoved(_ sample: PointerSample) {
        pointerSamples.append(sample)
    }

    package func pin(content: ReaderContent, chrome: ReaderChrome) {
        let shown = Shown(content: content, chrome: chrome)
        pins.append(shown)
        lastShown = shown
        log?.append(.readerPin(content))
    }

    package func dismiss() async {
        dismissCount += 1
        log?.append(.readerDismiss)
        guard holdDismiss else { return }
        await withCheckedContinuation { continuation in
            pendingDismiss = continuation
            let waiters = heldWaiters
            heldWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    /// Suspends until a held `dismiss()` is pending.
    package func waitUntilDismissIsHeld() async {
        guard pendingDismiss == nil else { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    /// Completes a held `dismiss()`. Does nothing if none is pending.
    package func completeDismiss() {
        guard let pendingDismiss else { return }
        self.pendingDismiss = nil
        pendingDismiss.resume()
    }
}

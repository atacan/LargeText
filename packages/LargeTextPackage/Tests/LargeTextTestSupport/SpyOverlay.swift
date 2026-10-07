import Foundation
import LargeTextCore

/// Records present/update/dismiss. With `holdDismiss`, `dismiss()` suspends until `completeDismiss(returning:)`,
/// which lets a test act while the coordinator is `closing`.
@MainActor
package final class SpyOverlay: OverlayPresenting {
    package private(set) var presentCount = 0
    package private(set) var lastSessionID: UUID?
    package private(set) var lastInitialText: String?
    package private(set) var lastChrome: OverlayChrome?
    package private(set) var lastIntents: (@MainActor (OverlayIntent) -> Void)?
    package private(set) var updates: [OverlayChrome] = []
    package private(set) var dismissCount = 0

    /// Returned by `dismiss()` when it is not held.
    package var textToReturn = ""
    package var holdDismiss = false
    package var isDismissHeld: Bool { pendingDismiss != nil }

    private let log: EventLog?
    private var pendingDismiss: CheckedContinuation<String, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    package init(log: EventLog? = nil) {
        self.log = log
    }

    package func present(
        sessionID: UUID,
        initialText: String,
        chrome: OverlayChrome,
        intents: @escaping @MainActor (OverlayIntent) -> Void
    ) {
        presentCount += 1
        lastSessionID = sessionID
        lastInitialText = initialText
        lastChrome = chrome
        lastIntents = intents
        log?.append(.present(initialText: initialText))
    }

    package func update(_ chrome: OverlayChrome) {
        updates.append(chrome)
        lastChrome = chrome
        log?.append(.update(chrome))
    }

    package func dismiss() async -> String {
        dismissCount += 1
        log?.append(.dismiss)
        guard holdDismiss else { return textToReturn }
        return await withCheckedContinuation { continuation in
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
    package func completeDismiss(returning text: String) {
        guard let pendingDismiss else { return }
        self.pendingDismiss = nil
        pendingDismiss.resume(returning: text)
    }
}

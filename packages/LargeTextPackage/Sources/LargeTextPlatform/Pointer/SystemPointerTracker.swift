import AppKit
import LargeTextCore

/// The live pointer (§4.2, §5.2). Each sample reads `NSEvent.mouseLocation` once and derives `global` from
/// it, so the two coordinates always describe the same instant.
///
/// Ticking is a main-actor `Task` loop that sleeps 16 ms between samples and only runs while its token is
/// live. Polling also catches drags, which a `.mouseMoved` monitor misses, and the main queue is serviced in
/// every common run-loop mode (menu tracking included), so no `Timer` registration is needed.
@MainActor
package final class SystemPointerTracker: PointerTracking {
    static let tickInterval: Duration = .milliseconds(16)

    package init() {}

    package var current: PointerSample {
        AXGeometry.pointerSample(appKit: NSEvent.mouseLocation, primaryScreenFrame: AXGeometry.primaryScreenFrame())
    }

    package func startTicking(_ onTick: @escaping @MainActor (PointerSample) -> Void) -> any PointerTickingToken {
        let token = Token()
        // The loop holds the token weakly: it ends when the token is cancelled or released.
        token.task = Task { [weak self, weak token] in
            while true {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, let token, token.isLive else { return }
                onTick(self.current)
            }
        }
        return token
    }

    private final class Token: PointerTickingToken {
        var task: Task<Void, Never>?
        private(set) var isLive = true

        /// Both the loop and `cancel()` run on the main actor, so the loop sees `isLive == false` before any
        /// further tick once this returns.
        func cancel() {
            isLive = false
            task?.cancel()
            task = nil
        }
    }
}

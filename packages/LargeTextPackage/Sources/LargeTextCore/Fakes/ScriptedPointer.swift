import CoreGraphics
import Foundation

/// A pointer that only moves and ticks when told to. At most one ticking callback is active; starting a new
/// one replaces the previous one.
@MainActor
package final class ScriptedPointer: PointerTracking {
    package var current: PointerSample
    package var isTicking: Bool { ticking != nil }

    private var ticking: (id: Int, onTick: @MainActor (PointerSample) -> Void)?
    private var nextTickingID = 0

    package init(current: PointerSample = PointerSample(appKit: .zero, global: .zero)) {
        self.current = current
    }

    package func startTicking(_ onTick: @escaping @MainActor (PointerSample) -> Void) -> any PointerTickingToken {
        nextTickingID += 1
        let id = nextTickingID
        ticking = (id, onTick)
        return Token { [weak self] in
            guard self?.ticking?.id == id else { return }
            self?.ticking = nil
        }
    }

    /// Delivers `current` to the active callback, if any.
    package func tick() {
        ticking?.onTick(current)
    }

    /// Sets `current`, then ticks.
    package func move(to sample: PointerSample) {
        current = sample
        tick()
    }

    private final class Token: PointerTickingToken {
        private var onCancel: (@MainActor () -> Void)?

        init(onCancel: @escaping @MainActor () -> Void) {
            self.onCancel = onCancel
        }

        func cancel() {
            onCancel?()
            onCancel = nil
        }
    }
}

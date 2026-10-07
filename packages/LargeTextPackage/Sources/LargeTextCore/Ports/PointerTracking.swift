import Foundation

@MainActor
package protocol PointerTracking: AnyObject {
    /// A fresh sample on every read.
    var current: PointerSample { get }
    /// Calls `onTick` with a fresh sample about 60 times a second until the token is cancelled. Ticks only
    /// while a reader session follows the pointer; nothing runs otherwise.
    func startTicking(_ onTick: @escaping @MainActor (PointerSample) -> Void) -> any PointerTickingToken
}

@MainActor
package protocol PointerTickingToken: AnyObject {
    /// Idempotent. No tick is delivered after it returns.
    func cancel()
}

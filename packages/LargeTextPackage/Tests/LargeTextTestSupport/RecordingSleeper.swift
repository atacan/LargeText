import Foundation
import LargeTextCore

/// Records requested durations and returns immediately. Main-actor isolated (hence `Sendable`);
/// `sleep` hops to the main actor, so recording needs no lock.
@MainActor
package final class RecordingSleeper: Sleeper {
    package private(set) var durations: [Duration] = []
    /// Runs inside each sleep, e.g. to simulate another app writing to the pasteboard during the restore delay.
    package var onSleep: (@MainActor (Duration) -> Void)?
    /// Sleeps for this duration park until `releaseHeld()`; lets a test act while a tail task is waiting.
    package var heldDuration: Duration?

    private var held: [CheckedContinuation<Void, Never>] = []

    private let log: EventLog?

    package init(log: EventLog? = nil) {
        self.log = log
    }

    @MainActor
    package func sleep(for duration: Duration) async throws {
        durations.append(duration)
        log?.append(.sleep(duration))
        onSleep?(duration)
        if duration == heldDuration {
            await withCheckedContinuation { held.append($0) }
        }
    }

    /// Stops holding and resumes every parked sleep.
    package func releaseHeld() {
        heldDuration = nil
        let parked = held
        held = []
        parked.forEach { $0.resume() }
    }
}

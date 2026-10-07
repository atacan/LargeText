import Foundation
import LargeTextCore

/// Records requested durations and returns immediately. Main-actor isolated (hence `Sendable`);
/// `sleep` hops to the main actor, so recording needs no lock.
@MainActor
package final class RecordingSleeper: Sleeper {
    package private(set) var durations: [Duration] = []
    /// Runs inside each sleep, e.g. to simulate another app writing to the pasteboard during the restore delay.
    package var onSleep: (@MainActor (Duration) -> Void)?
    /// Sleeps for any of these durations park until `release(_:)` or until their task is cancelled (which
    /// throws `CancellationError`, like `Task.sleep`). Lets a test act while a task is waiting.
    package var heldDurations: Set<Duration> = []

    private var parked: [(id: UUID, duration: Duration, continuation: CheckedContinuation<Void, any Error>)] = []

    private let log: EventLog?

    package init(log: EventLog? = nil) {
        self.log = log
    }

    @MainActor
    package func sleep(for duration: Duration) async throws {
        durations.append(duration)
        log?.append(.sleep(duration))
        onSleep?(duration)
        guard heldDurations.contains(duration) else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                park(id: id, duration: duration, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in self.cancelParked(id: id) }
        }
    }

    /// Whether a sleep for `duration` is currently parked.
    package func isParked(_ duration: Duration) -> Bool {
        parked.contains { $0.duration == duration }
    }

    /// Stops holding `duration` and resumes every sleep parked on it.
    package func release(_ duration: Duration) {
        heldDurations.remove(duration)
        let released = parked.filter { $0.duration == duration }
        parked.removeAll { $0.duration == duration }
        released.forEach { $0.continuation.resume() }
    }

    /// Already cancelled → throws at once; otherwise `onCancel`'s hop to the main actor runs after this.
    private func park(id: UUID, duration: Duration, continuation: CheckedContinuation<Void, any Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            parked.append((id, duration, continuation))
        }
    }

    private func cancelParked(id: UUID) {
        guard let index = parked.firstIndex(where: { $0.id == id }) else { return }
        parked.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

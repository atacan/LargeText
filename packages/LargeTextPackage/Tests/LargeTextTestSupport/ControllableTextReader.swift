import Foundation
import LargeTextCore

/// Records every read and parks it until the test calls `complete(readIndex:with:)`, so read races are
/// deterministic without real delays. Main-actor isolated (hence `Sendable`), like `RecordingSleeper`.
@MainActor
package final class ControllableTextReader: TextReading {
    package struct Call: Equatable, Sendable {
        package var pointer: PointerSample
        package var granularity: ReadGranularity
        package var pid: Int32?
        package var policy: ReadPolicy
    }

    /// Every read so far, in call order; a read's index is its position here.
    package private(set) var calls: [Call] = []
    /// Indices of reads not yet completed, ascending.
    package var pendingReadIndices: [Int] { pending.keys.sorted() }

    private var pending: [Int: CheckedContinuation<ReadResult, Never>] = [:]
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    package init() {}

    @MainActor
    package func read(at pointer: PointerSample, granularity: ReadGranularity, pid: Int32?, policy: ReadPolicy) async -> ReadResult {
        let index = calls.count
        calls.append(Call(pointer: pointer, granularity: granularity, pid: pid, policy: policy))
        let ready = callWaiters.filter { $0.count <= calls.count }
        callWaiters.removeAll { $0.count <= calls.count }
        ready.forEach { $0.continuation.resume() }
        return await withCheckedContinuation { pending[index] = $0 }
    }

    /// Resumes read number `readIndex` with `result`. Does nothing if that read isn't pending.
    package func complete(readIndex: Int, with result: ReadResult) {
        pending.removeValue(forKey: readIndex)?.resume(returning: result)
    }

    /// Suspends until at least `count` reads have been made.
    package func waitForCalls(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { callWaiters.append((count, $0)) }
    }
}

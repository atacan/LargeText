import Foundation

/// Reads the text under the pointer (§4.3, §4.4).
///
/// Sendable and **not** `@MainActor`: the live reader is an actor on its own serial queue, so blocking AX
/// calls never run on the main thread. Only Sendable values cross this boundary.
package protocol TextReading: Sendable {
    /// `pid` scopes the hit test to that application instead of the system-wide one (e.g. a re-read of the
    /// frozen app on pin). `policy` is the session's snapshot. Protocol requirements can't have default
    /// arguments, hence the pid-less extension below.
    func read(at pointer: PointerSample, granularity: ReadGranularity, pid: Int32?, policy: ReadPolicy) async -> ReadResult
}

extension TextReading {
    /// System-wide hit test.
    package func read(at pointer: PointerSample, granularity: ReadGranularity, policy: ReadPolicy) async -> ReadResult {
        await read(at: pointer, granularity: granularity, pid: nil, policy: policy)
    }
}

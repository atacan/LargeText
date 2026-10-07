import LargeTextCore

/// Live `Sleeper`: a plain `Task.sleep(for:)`.
package struct TaskSleeper: Sleeper {
    package init() {}

    package func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

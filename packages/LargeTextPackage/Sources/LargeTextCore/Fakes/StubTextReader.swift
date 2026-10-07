import CoreGraphics
import Foundation

/// Answers by the pointer's x coordinate, with an optional real delay so races can be tried by hand.
/// Used by the `reader-stub` scenario.
package struct StubTextReader: TextReading {
    /// Pointers whose `global.x` lies in `xRange` get `result`.
    package struct Answer: Sendable {
        package var xRange: Range<CGFloat>
        package var result: ReadResult

        package init(xRange: Range<CGFloat>, result: ReadResult) {
            self.xRange = xRange
            self.result = result
        }
    }

    /// The first matching answer wins.
    package var answers: [Answer]
    /// Returned when no answer matches.
    package var fallback: ReadResult
    /// Waited before answering; `.zero` answers at once.
    package var delay: Duration

    package init(answers: [Answer] = [], fallback: ReadResult = .nothing, delay: Duration = .zero) {
        self.answers = answers
        self.fallback = fallback
        self.delay = delay
    }

    package func read(at pointer: PointerSample, granularity: ReadGranularity, pid: Int32?, policy: ReadPolicy) async -> ReadResult {
        if delay > .zero {
            // A cancelled read still answers; the caller drops stale results.
            try? await Task.sleep(for: delay)
        }
        return answers.first { $0.xRange.contains(pointer.global.x) }?.result ?? fallback
    }
}

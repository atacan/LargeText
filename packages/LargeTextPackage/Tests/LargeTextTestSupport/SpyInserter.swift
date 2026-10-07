import Foundation
import LargeTextCore

/// Records insert calls and returns a scripted outcome.
@MainActor
package final class SpyInserter: TextInserting {
    package var outcome: InsertionOutcome
    package private(set) var calls: [(text: String, mode: CommitMode)] = []
    package private(set) var lastTarget: FocusTarget?

    private let log: EventLog?

    package init(outcome: InsertionOutcome = .inserted(clipboardOverwritten: false), log: EventLog? = nil) {
        self.outcome = outcome
        self.log = log
    }

    package func insert(_ text: String, into target: FocusTarget, mode: CommitMode) async -> InsertionOutcome {
        calls.append((text, mode))
        lastTarget = target
        log?.append(.insert(text, mode))
        return outcome
    }
}

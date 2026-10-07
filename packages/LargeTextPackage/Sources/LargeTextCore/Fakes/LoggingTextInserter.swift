import Foundation
import os

/// Logs instead of inserting. Always reports a successful insert.
@MainActor
package final class LoggingTextInserter: TextInserting {
    package init() {}

    package func insert(_ text: String, into target: FocusTarget, mode: CommitMode) async -> InsertionOutcome {
        let app = target.application?.localizedName ?? "<none>"
        Logger.core.info("LoggingTextInserter: \(String(describing: mode)) into \(app): \(text, privacy: .private)")
        return .inserted(clipboardOverwritten: false)
    }
}

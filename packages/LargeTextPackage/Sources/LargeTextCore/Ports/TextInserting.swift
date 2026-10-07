import Foundation

@MainActor
package protocol TextInserting: AnyObject {
    func insert(_ text: String, into target: FocusTarget, mode: CommitMode) async -> InsertionOutcome
}

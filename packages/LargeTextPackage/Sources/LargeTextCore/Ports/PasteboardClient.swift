import Foundation

@MainActor
package protocol PasteboardClient: AnyObject {
    var changeCount: Int { get }
    func snapshot(maxBytes: Int) -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    /// Clears, sets `.currentHostOnly`, writes; `transient` adds the nspasteboard.org markers.
    /// Returns the new `changeCount`.
    @discardableResult
    func write(_ string: String, transient: Bool) -> Int
}

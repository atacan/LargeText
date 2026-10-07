import Foundation

/// Where a `ReadText` came from: the rung of the §3.3 ladder that produced it.
package enum ReadSource: Equatable, Sendable {
    /// Selected text under the pointer.
    case selection
    /// The sentence, line or paragraph at the pointer.
    case unit
    /// The whole (short) element text.
    case element
    /// Title, description, help or placeholder.
    case label
    /// Found by the bounded child/ancestor walk.
    case walk
    /// Recognised from pixels (phase 2).
    case ocr
}

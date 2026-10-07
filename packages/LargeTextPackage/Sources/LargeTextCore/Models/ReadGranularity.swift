import Foundation

/// The unit of text the reader asks for around the pointer. The raw value is the stored preference and
/// launch-argument spelling.
package enum ReadGranularity: String, CaseIterable, Hashable, Sendable {
    case sentence
    case line
    case paragraph
}

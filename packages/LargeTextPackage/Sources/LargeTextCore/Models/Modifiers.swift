import Foundation

/// Keyboard modifier keys, independent of AppKit/Carbon/CGEvent flag representations.
package struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue }

    package static let command = Modifiers(rawValue: 1 << 0)
    package static let option = Modifiers(rawValue: 1 << 1)
    package static let control = Modifiers(rawValue: 1 << 2)
    package static let shift = Modifiers(rawValue: 1 << 3)
}

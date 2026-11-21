import Foundation

/// One of the two global shortcuts.
package enum ShortcutSlot: CaseIterable, Hashable, Sendable {
    case editor
    case reader

    /// The slot this one is checked against (`ShortcutRules`, `.sameAsOther`).
    package var other: ShortcutSlot {
        switch self {
        case .editor: .reader
        case .reader: .editor
        }
    }

    /// What "Reset" restores, and what a missing preference reads as.
    package var defaultCombo: KeyCombo {
        switch self {
        case .editor: .default
        case .reader: .readerDefault
        }
    }
}

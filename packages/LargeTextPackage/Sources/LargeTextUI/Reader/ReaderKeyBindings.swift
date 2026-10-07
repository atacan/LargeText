import LargeTextCore

/// What a key press means on the pinned reader card.
package enum ReaderAction: Equatable, Sendable {
    case close
    case zoom(ZoomStep)
    case copy
    case selectAll
}

/// Pure key → action table for the pinned reader card (§4.5). The following card is never key, so it
/// never sees keys. `nil` means "let AppKit handle it" (arrows, Page Up / Down, …).
package enum ReaderKeyBindings {
    package static func action(for input: KeyInput) -> ReaderAction? {
        if input.isEscape { return input.modifiers.isEmpty ? .close : nil }
        switch CommandShortcutMatcher.match(input) {
        case .zoom(let step): return .zoom(step)
        case .edit(.copy): return .copy
        case .edit(.selectAll): return .selectAll
        case .edit, nil: return nil
        }
    }
}

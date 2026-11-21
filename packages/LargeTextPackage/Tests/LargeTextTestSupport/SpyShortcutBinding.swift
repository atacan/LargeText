import Foundation
import LargeTextCore

/// Records `apply` and `suspend` in order. Refuses the combos in `refusing`, as if another app held them,
/// and a reader equal to the editor, as `HotkeyBindings` does.
@MainActor
package final class SpyShortcutBinding: ShortcutBinding {
    package enum Call: Equatable, Sendable {
        case apply(editor: KeyCombo, reader: KeyCombo?)
        case suspend
    }

    package var refusing: Set<KeyCombo>
    package private(set) var calls: [Call] = []
    package private(set) var unavailable: [KeyCombo] = []
    package private(set) var unavailableSlots: Set<ShortcutSlot> = []
    /// Between `suspend()` and the next `apply`.
    package private(set) var isSuspended = false

    package init(refusing: Set<KeyCombo> = []) {
        self.refusing = refusing
    }

    /// Only the `apply` calls.
    package var applied: [Call] {
        calls.filter { $0 != .suspend }
    }

    @discardableResult
    package func apply(editor: KeyCombo, reader: KeyCombo?) -> [ShortcutSlot: HotkeyError] {
        calls.append(.apply(editor: editor, reader: reader))
        isSuspended = false
        var failures: [ShortcutSlot: HotkeyError] = [:]
        if refusing.contains(editor) {
            failures[.editor] = .unavailable(editor)
        }
        if let reader, refusing.contains(reader) || reader == editor {
            failures[.reader] = .unavailable(reader)
        }
        unavailableSlots = Set(failures.keys)
        unavailable = ShortcutSlot.allCases.compactMap { slot in
            guard case .unavailable(let combo) = failures[slot] else { return nil }
            return combo
        }
        return failures
    }

    package func suspend() {
        calls.append(.suspend)
        isSuspended = true
    }
}

import Foundation

/// How committed text reaches the target. The single source of truth for both the overlay hints
/// (at open) and `PasteboardTextInserter` (at commit).
package enum InsertionRoute: Equatable, Sendable {
    case paste
    case copyOnly(InsertionFallbackReason)

    /// | Condition                                   | Route                            |
    /// |---------------------------------------------|----------------------------------|
    /// | event posting not permitted                 | `.copyOnly(.permissionMissing)`  |
    /// | `target.application == nil`                 | `.copyOnly(.noEditableTarget)`   |
    /// | `elementKind == .notEditable`               | `.copyOnly(.noEditableTarget)`   |
    /// | otherwise (including unknown / `nil` kind)  | `.paste`                         |
    ///
    /// `.secureText` maps to `.paste`. The coordinator refuses secure targets before presenting, so this
    /// is never reached in practice; if it ever were, pasting through the transient pasteboard leaves
    /// less trace than a non-transient clipboard copy that clipboard managers would record.
    package static func decide(target: FocusTarget, permissions: Permissions) -> InsertionRoute {
        guard permissions.eventPosting == .granted else { return .copyOnly(.permissionMissing) }
        guard target.application != nil else { return .copyOnly(.noEditableTarget) }
        switch target.elementKind {
        case .notEditable:
            return .copyOnly(.noEditableTarget)
        case nil, .singleLineText, .multiLineText, .secureText:
            return .paste
        }
    }
}

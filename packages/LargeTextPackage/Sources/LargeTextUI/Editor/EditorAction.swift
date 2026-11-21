import LargeTextCore

/// What a key press means inside the overlay editor.
package enum EditorAction: Equatable, Sendable {
    case commit(CommitMode)
    case cancel
    case newline
    case zoom(ZoomStep)
    case standardEdit(StandardEdit)
    /// ⌘,: closes the editor (copying any text), then Settings opens.
    case openSettings
}

/// Edits performed by direct calls on the text view (never via the responder chain or `NSApp.mainMenu`).
package enum StandardEdit: Equatable, Sendable {
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
}

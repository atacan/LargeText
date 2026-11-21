import Foundation

package struct CoreDependencies {
    package var focus: any FocusCapturing
    /// For `TargetHints` (via `InsertionRoute`).
    package var permissions: any PermissionsProviding
    package var inserter: any TextInserting
    /// For ⌘, with text in the editor: the text is copied before Settings opens (`ClipboardWriter`).
    package var pasteboard: any PasteboardClient
    package var overlay: any OverlayPresenting
    package var notices: any NoticePresenting
    package var preferences: any PreferencesStore

    package init(
        focus: any FocusCapturing,
        permissions: any PermissionsProviding,
        inserter: any TextInserting,
        pasteboard: any PasteboardClient,
        overlay: any OverlayPresenting,
        notices: any NoticePresenting,
        preferences: any PreferencesStore
    ) {
        self.focus = focus
        self.permissions = permissions
        self.inserter = inserter
        self.pasteboard = pasteboard
        self.overlay = overlay
        self.notices = notices
        self.preferences = preferences
    }
}

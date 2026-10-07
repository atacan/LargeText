import AppKit

/// The overlay window: non-activating (set at creation), borderless, can become key (unless `allowsKey` is
/// off) but never main, above full-screen apps on every Space (§2.2). Used by the editor and the reader.
@MainActor
package final class OverlayPanel: NSPanel {
    /// Called after every resign-key. `OverlayWindowController` decides whether it means `.lostFocus`.
    package var onResignKey: (() -> Void)?
    /// Backs `canBecomeKey`. The editor leaves it on; the reader turns it off while following (§4.5).
    package var allowsKey = true

    package convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    }

    override package init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        // `.nonactivatingPanel` only takes full effect when passed at creation time.
        super.init(
            contentRect: contentRect,
            styleMask: style.union([.nonactivatingPanel, .borderless]),
            backing: backingStoreType,
            defer: flag
        )
        level = Self.overlayLevel
        collectionBehavior = Self.overlayCollectionBehavior
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = false
    }

    /// Shared with the HUD so both behave identically over full-screen Spaces.
    package static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
    ]

    /// Shared with the HUD.
    package static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    override package var canBecomeKey: Bool { allowsKey }
    override package var canBecomeMain: Bool { false }

    override package func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

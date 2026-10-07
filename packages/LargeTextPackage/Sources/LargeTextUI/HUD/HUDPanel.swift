import AppKit

/// Non-key, click-through notice panel with the overlay's level and Spaces behaviour (§2.2).
@MainActor
package final class HUDPanel: NSPanel {
    package convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    }

    override package init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style.union([.nonactivatingPanel, .borderless]),
            backing: backingStoreType,
            defer: flag
        )
        level = OverlayPanel.overlayLevel
        collectionBehavior = OverlayPanel.overlayCollectionBehavior
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        isMovable = false
        animationBehavior = .none
    }

    override package var canBecomeKey: Bool { false }
    override package var canBecomeMain: Bool { false }
}

import AppKit

/// Full-screen dimmed backdrop. A click on it (outside the card) calls `onClick`.
@MainActor
final class BackdropView: NSView {
    var onClick: (() -> Void)?

    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.backdropColor.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

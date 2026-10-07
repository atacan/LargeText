import AppKit

/// Borderless, click-through, never-key panel drawing a rounded outline around the text being read (§4.7).
/// Same level and Spaces behaviour as the reader card. Owned by `ReaderWindowController`.
///
/// This is the single-panel variant. It sits under the pointer by design; if spike R4 shows that the
/// system-wide hit test does not skip click-through windows, it becomes four thin edge panels instead.
@MainActor
final class HighlightPanel: NSPanel {
    convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    }

    override init(
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
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        isMovable = false
        animationBehavior = .none
        contentView = OutlineView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Outlines `sourceFrame` (AppKit global coordinates), or hides the panel when there is none.
    /// Ordered front without becoming key.
    func show(around sourceFrame: CGRect?) {
        guard let sourceFrame, !sourceFrame.isNull, !sourceFrame.isInfinite, !sourceFrame.isEmpty else {
            orderOut(nil)
            return
        }
        let outset = Theme.highlightPadding + Theme.highlightLineWidth
        let frame = sourceFrame.standardized.insetBy(dx: -outset, dy: -outset)
        if self.frame != frame {
            setFrame(frame, display: true)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }
}

/// The outline itself, drawn inside the panel's bounds.
@MainActor
private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let lineWidth = Theme.highlightLineWidth
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            xRadius: Theme.highlightCornerRadius,
            yRadius: Theme.highlightCornerRadius
        )
        path.lineWidth = lineWidth
        Theme.hintColor.setStroke()
        path.stroke()
    }
}

import AppKit

/// All overlay / HUD colors and metrics in one place (v1, deliberately simple; tuned after hands-on).
/// Colors are computed properties so the enum stays free of non-`Sendable` stored statics.
package enum Theme {
    // MARK: Overlay

    package static var backdropColor: NSColor { NSColor.black.withAlphaComponent(0.55) }
    package static let cardWidthFraction: CGFloat = 0.8
    package static let cardCornerRadius: CGFloat = 24
    package static let cardPadding: CGFloat = 32
    package static let cardSpacing: CGFloat = 20
    package static let editorMaxHeightFraction: CGFloat = 0.6
    package static let headerScale: CGFloat = 0.4
    package static let footerScale: CGFloat = 0.3
    package static let iconScale: CGFloat = 1.3
    package static let textContainerInset = NSSize(width: 4, height: 6)

    package static var textColor: NSColor { .white }
    package static var insertionPointColor: NSColor { .white }
    package static var selectionColor: NSColor { NSColor.systemBlue.withAlphaComponent(0.65) }
    package static var headerColor: NSColor { NSColor.white.withAlphaComponent(0.85) }
    package static var hintColor: NSColor { NSColor.systemYellow }
    package static var footerColor: NSColor { NSColor.white.withAlphaComponent(0.6) }

    package static func editorFont(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .regular) }
    package static func headerFont(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
    package static func footerFont(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .medium) }

    // MARK: Motion

    /// At most 120 ms (§3.8); zero when Reduce Motion is on.
    package static let fadeDuration: TimeInterval = 0.12

    // MARK: HUD

    package static let hudTitleSize: CGFloat = 44
    package static let hudSubtitleSize: CGFloat = 24
    package static let hudPadding: CGFloat = 36
    package static let hudCornerRadius: CGFloat = 24
    package static let hudMaxWidthFraction: CGFloat = 0.8
    package static let hudDisplayDuration: Duration = .milliseconds(2500)
    package static var hudSubtitleColor: NSColor { NSColor.white.withAlphaComponent(0.75) }

    /// A stretchable rounded-rect mask for `NSVisualEffectView.maskImage`.
    @MainActor
    package static func roundedMask(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

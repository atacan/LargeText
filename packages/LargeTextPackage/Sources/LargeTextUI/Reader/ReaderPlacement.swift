import CoreGraphics

/// Where the reader card goes (§4.6). Pure; every frame is in AppKit global coordinates.
///
/// - **Following:** the card sits at the top or bottom of the visible frame, in the half away from the
///   pointer, avoiding the source frame where possible. It changes halves only when the pointer enters the
///   card frame plus `Theme.readerHysteresisMargin`, never just because the pointer crossed the middle.
///   Evaluated on every pointer tick, not only when a new result arrives.
/// - **Pinned:** the card keeps its origin and anchor edge (top edge in the top half, bottom edge in the
///   bottom half) and grows to the pinned cap. A direct pin (`previous: nil`) centres it, like the editor.
package enum ReaderPlacement {
    package struct Placement: Equatable, Sendable {
        package var screen: ScreenDescriptor
        package var cardFrame: CGRect

        package init(screen: ScreenDescriptor, cardFrame: CGRect) {
            self.screen = screen
            self.cardFrame = cardFrame
        }
    }

    /// The vertical half of the visible frame the card sits in.
    enum Half: Equatable {
        case top
        case bottom

        var other: Half { self == .top ? .bottom : .top }
    }

    // MARK: - Following

    /// Resolves the pointer's screen, then places the card on it. A previous frame on another display is
    /// ignored, so moving to another display places the card fresh. `nil` only when `screens` is empty.
    ///
    /// - Parameter preferredSize: the card's size on a screen (its width depends on the screen); the
    ///   height is capped here.
    package static func following(
        pointer: CGPoint,
        sourceFrame: CGRect?,
        previous: CGRect?,
        screens: [ScreenDescriptor],
        preferredSize: (ScreenDescriptor) -> CGSize
    ) -> Placement? {
        guard let screen = ScreenResolver.resolve(targetFrame: nil, mouseLocation: pointer, screens: screens)
        else { return nil }
        let frame = following(
            in: screen.visibleFrame,
            pointer: pointer,
            sourceFrame: sourceFrame,
            preferredSize: preferredSize(screen),
            previous: previous
        )
        return Placement(screen: screen, cardFrame: frame)
    }

    /// Places the following card inside `visibleFrame`.
    package static func following(
        in visibleFrame: CGRect,
        pointer: CGPoint,
        sourceFrame: CGRect?,
        preferredSize: CGSize,
        previous: CGRect?
    ) -> CGRect {
        let size = cappedSize(preferredSize, in: visibleFrame, maxHeightFraction: Theme.followingMaxHeightFraction)
        let frame = { (half: Half) in followingFrame(half, size: size, in: visibleFrame) }

        if let previous, visibleFrame.contains(CGPoint(x: previous.midX, y: previous.midY)) {
            // Hysteresis: stay in the current half until the pointer comes near the card.
            let half = self.half(of: previous, in: visibleFrame)
            let kept = frame(half)
            guard isNear(pointer, kept) else { return kept }
            let flipped = frame(half.other)
            // On a screen too small for either half to clear the pointer, stay put rather than flip-flop.
            return isNear(pointer, flipped) ? kept : flipped
        }

        let pointerHalf: Half = pointer.y >= visibleFrame.midY ? .top : .bottom
        let preferred = [pointerHalf.other, pointerHalf].map(frame)
        let clear = preferred.first { candidate in
            !isNear(pointer, candidate) && !(sourceFrame.map { $0.intersects(candidate) } ?? false)
        }
        return clear ?? preferred[0]
    }

    // MARK: - Pinned

    /// Places the pinned card inside `visibleFrame`.
    ///
    /// - Parameter previous: the following card's frame at pin time, or `nil` for a direct pin (centred).
    package static func pinned(
        in visibleFrame: CGRect,
        preferredSize: CGSize,
        previous: CGRect?
    ) -> CGRect {
        let size = cappedSize(preferredSize, in: visibleFrame, maxHeightFraction: Theme.editorMaxHeightFraction)
        guard let previous else {
            return CGRect(
                x: (visibleFrame.midX - size.width / 2).rounded(),
                y: (visibleFrame.midY - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            )
        }
        let width = min(previous.width, visibleFrame.width)
        let y = switch half(of: previous, in: visibleFrame) {
        case .top: previous.maxY - size.height
        case .bottom: previous.minY
        }
        return CGRect(
            x: clamp(previous.minX, visibleFrame.minX, visibleFrame.maxX - width),
            y: clamp(y, visibleFrame.minY, visibleFrame.maxY - size.height),
            width: width,
            height: size.height
        )
    }

    // MARK: - Private

    static func half(of frame: CGRect, in visibleFrame: CGRect) -> Half {
        frame.midY >= visibleFrame.midY ? .top : .bottom
    }

    private static func cappedSize(_ size: CGSize, in visibleFrame: CGRect, maxHeightFraction: CGFloat) -> CGSize {
        CGSize(
            width: min(size.width, visibleFrame.width).rounded(),
            height: min(size.height, (visibleFrame.height * maxHeightFraction).rounded(.down)).rounded()
        )
    }

    private static func followingFrame(_ half: Half, size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let inset = Theme.readerScreenInset
        let y = switch half {
        case .top: visibleFrame.maxY - inset - size.height
        case .bottom: visibleFrame.minY + inset
        }
        return CGRect(x: (visibleFrame.midX - size.width / 2).rounded(), y: y, width: size.width, height: size.height)
    }

    /// Inside the card frame grown by the hysteresis margin.
    private static func isNear(_ pointer: CGPoint, _ frame: CGRect) -> Bool {
        let margin = Theme.readerHysteresisMargin
        return frame.insetBy(dx: -margin, dy: -margin).contains(pointer)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}

import CoreGraphics
import Testing
@testable import LargeTextUI

@Suite("ReaderPlacement")
struct ReaderPlacementTests {
    /// 1440×900 with a 25 pt menu bar: midY 437.5; following cap 393 pt, pinned cap 525 pt.
    private let primary = ScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let secondary = ScreenDescriptor(
        id: 2,
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    )
    private var visible: CGRect { primary.visibleFrame }
    private let size = CGSize(width: 1152, height: 200)
    /// Where a 1152×200 card sits in each half of `primary`.
    private let topFrame = CGRect(x: 144, y: 651, width: 1152, height: 200)
    private let bottomFrame = CGRect(x: 144, y: 24, width: 1152, height: 200)

    private func following(
        pointer: CGPoint,
        source: CGRect? = nil,
        size: CGSize? = nil,
        previous: CGRect? = nil,
        in visibleFrame: CGRect? = nil
    ) -> CGRect {
        ReaderPlacement.following(
            in: visibleFrame ?? visible,
            pointer: pointer,
            sourceFrame: source,
            preferredSize: size ?? self.size,
            previous: previous
        )
    }

    // MARK: Following — first placement

    @Test func cardGoesToTheHalfAwayFromThePointer() {
        #expect(following(pointer: CGPoint(x: 700, y: 200)) == topFrame)
        #expect(following(pointer: CGPoint(x: 700, y: 700)) == bottomFrame)
    }

    @Test func heightIsCappedAtTheFollowingFraction() {
        let frame = following(pointer: CGPoint(x: 700, y: 200), size: CGSize(width: 1152, height: 2000))
        #expect(frame.height == 393)
        #expect(frame.maxY == visible.maxY - Theme.readerScreenInset)
    }

    @Test func widthNeverExceedsTheScreen() {
        let frame = following(pointer: CGPoint(x: 700, y: 200), size: CGSize(width: 5000, height: 200))
        #expect(frame.width == visible.width)
        #expect(visible.contains(frame))
    }

    /// A source taller than the screen's middle overlaps both halves: the card still avoids the pointer.
    @Test func tallSourceStillUsesTheOppositeHalf() {
        let source = CGRect(x: 100, y: 50, width: 600, height: 800)
        #expect(following(pointer: CGPoint(x: 300, y: 300), source: source) == topFrame)
    }

    /// Pointer just below the middle, at the bottom of a source that fills the top half: the bottom slot
    /// is clear of both, so the card avoids the source.
    @Test func cardAvoidsTheSourceWhereItCan() {
        let small = CGSize(width: 1152, height: 100)
        let source = CGRect(x: 100, y: 400, width: 800, height: 450)
        let frame = following(pointer: CGPoint(x: 700, y: 420), source: source, size: small)
        #expect(frame == CGRect(x: 144, y: 24, width: 1152, height: 100))
        #expect(!frame.intersects(source))
    }

    // MARK: Following — hysteresis

    @Test func crossingTheMiddleDoesNotFlip() {
        // The card is at the top; the pointer moves up past the middle but stays clear of the card.
        let pointer = CGPoint(x: 700, y: 600)
        #expect(following(pointer: pointer, previous: topFrame) == topFrame)
    }

    @Test func enteringTheCardMarginFlips() {
        let margin = Theme.readerHysteresisMargin
        let justOutside = CGPoint(x: 700, y: topFrame.minY - margin - 1)
        let justInside = CGPoint(x: 700, y: topFrame.minY - margin + 1)
        #expect(following(pointer: justOutside, previous: topFrame) == topFrame)
        #expect(following(pointer: justInside, previous: topFrame) == bottomFrame)
    }

    /// Duplicate read results are dropped, so the pointer alone (same size, same source) must move the card.
    @Test func hysteresisWithNoNewResult() {
        var frame = following(pointer: CGPoint(x: 700, y: 200))
        #expect(frame == topFrame)
        // Same content and size every tick; only the pointer moves, up onto the card.
        for y in stride(from: 220.0, through: 700.0, by: 40) {
            frame = following(pointer: CGPoint(x: 700, y: y), previous: frame)
        }
        #expect(frame == bottomFrame)
        // And back down: the card stays at the bottom until the pointer reaches it again.
        frame = following(pointer: CGPoint(x: 700, y: 300), previous: frame)
        #expect(frame == bottomFrame)
        frame = following(pointer: CGPoint(x: 700, y: 230), previous: frame)
        #expect(frame == topFrame)
    }

    @Test func keptCardFollowsANewHeightWithItsAnchorEdge() {
        let taller = CGSize(width: 1152, height: 300)
        let top = following(pointer: CGPoint(x: 700, y: 200), size: taller, previous: topFrame)
        #expect(top.maxY == topFrame.maxY)
        #expect(top.height == 300)
        let bottom = following(pointer: CGPoint(x: 700, y: 700), size: taller, previous: bottomFrame)
        #expect(bottom.minY == bottomFrame.minY)
    }

    @Test func smallScreenNeverFlipFlops() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        let pointer = CGPoint(x: 400, y: 250)
        let huge = CGSize(width: 640, height: 1000)
        let first = following(pointer: pointer, size: huge, in: small)
        #expect(small.contains(first))
        #expect(first.height == 225)
        let second = following(pointer: pointer, size: huge, previous: first, in: small)
        let third = following(pointer: pointer, size: huge, previous: second, in: small)
        #expect(second == first)
        #expect(third == first)
    }

    // MARK: Following — displays

    @Test func screenIsResolvedFromThePointer() throws {
        let placement = try #require(ReaderPlacement.following(
            pointer: CGPoint(x: 2000, y: 900),
            sourceFrame: nil,
            previous: nil,
            screens: [primary, secondary]
        ) { screen in
            CGSize(width: screen.visibleFrame.width * Theme.cardWidthFraction, height: 200)
        })
        #expect(placement.screen == secondary)
        #expect(placement.cardFrame == CGRect(x: 1632, y: 24, width: 1536, height: 200))
    }

    @Test func movingToAnotherDisplayPlacesTheCardFresh() throws {
        // The card sits at the top of the primary screen; the pointer moves to the bottom of the secondary.
        let placement = try #require(ReaderPlacement.following(
            pointer: CGPoint(x: 2000, y: 100),
            sourceFrame: nil,
            previous: topFrame,
            screens: [primary, secondary]
        ) { _ in size })
        #expect(placement.screen == secondary)
        #expect(placement.cardFrame.minY == secondary.visibleFrame.maxY - Theme.readerScreenInset - 200)
        #expect(secondary.visibleFrame.contains(placement.cardFrame))
    }

    @Test func noScreensMeansNoPlacement() {
        let placement = ReaderPlacement.following(
            pointer: .zero,
            sourceFrame: nil,
            previous: nil,
            screens: []
        ) { _ in size }
        #expect(placement == nil)
    }

    // MARK: Pinned

    @Test func pinFromTheTopHalfKeepsTheTopEdgeAndGrows() {
        let frame = ReaderPlacement.pinned(in: visible, preferredSize: CGSize(width: 1152, height: 400), previous: topFrame)
        #expect(frame == CGRect(x: 144, y: 451, width: 1152, height: 400))
    }

    @Test func pinFromTheBottomHalfKeepsTheBottomEdgeAndGrows() {
        let frame = ReaderPlacement.pinned(in: visible, preferredSize: CGSize(width: 1152, height: 400), previous: bottomFrame)
        #expect(frame == CGRect(x: 144, y: 24, width: 1152, height: 400))
    }

    @Test func pinGrowsOnlyToThePinnedCap() {
        let tall = CGSize(width: 1152, height: 5000)
        let top = ReaderPlacement.pinned(in: visible, preferredSize: tall, previous: topFrame)
        #expect(top.height == 525)
        #expect(top.maxY == topFrame.maxY)
        let bottom = ReaderPlacement.pinned(in: visible, preferredSize: tall, previous: bottomFrame)
        #expect(bottom.height == 525)
        #expect(bottom.minY == bottomFrame.minY)
    }

    @Test func pinKeepsTheFollowingCardsOriginAndWidth() {
        let frame = ReaderPlacement.pinned(in: visible, preferredSize: CGSize(width: 900, height: 200), previous: topFrame)
        #expect(frame == topFrame)
    }

    @Test func directPinCentres() {
        let frame = ReaderPlacement.pinned(in: visible, preferredSize: CGSize(width: 1152, height: 300), previous: nil)
        #expect(frame.size == CGSize(width: 1152, height: 300))
        #expect(frame.midX == visible.midX)
        #expect(abs(frame.midY - visible.midY) <= 0.5)
    }

    @Test func directPinIsCappedToo() {
        let frame = ReaderPlacement.pinned(in: visible, preferredSize: CGSize(width: 1152, height: 5000), previous: nil)
        #expect(frame.height == 525)
        #expect(visible.contains(frame))
    }
}

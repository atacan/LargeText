import CoreGraphics
import LargeTextCore
import Testing
@testable import LargeTextPlatform

@Suite struct AXGeometryTests {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func elementOnPrimaryScreenIsFlipped() {
        let rect = AXGeometry.appKitRect(
            axPosition: CGPoint(x: 100, y: 50),
            axSize: CGSize(width: 300, height: 20),
            primaryScreenFrame: primary
        )
        #expect(rect == CGRect(x: 100, y: 830, width: 300, height: 20))
    }

    @Test func elementAtTopLeftOfPrimaryTouchesTopEdge() {
        let rect = AXGeometry.appKitRect(axPosition: .zero, axSize: CGSize(width: 10, height: 10), primaryScreenFrame: primary)
        #expect(rect.maxY == primary.maxY)
        #expect(rect.minX == 0)
    }

    /// Secondary display above and to the left of the primary: AppKit frame (-1920, 900, 1920, 1080).
    /// In AX coordinates its top-left is (-1920, -1080).
    @Test func elementOnSecondaryScreenWithNegativeOrigin() {
        let secondary = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        let rect = AXGeometry.appKitRect(
            axPosition: CGPoint(x: -1820, y: -980),
            axSize: CGSize(width: 200, height: 30),
            primaryScreenFrame: primary
        )
        #expect(rect == CGRect(x: -1820, y: 1850, width: 200, height: 30))
        #expect(secondary.contains(rect))
    }

    /// Secondary display below the primary: AppKit frame (0, -1080, 1920, 1080); AX y starts at 900.
    @Test func elementOnSecondaryScreenBelowPrimary() {
        let secondary = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let rect = AXGeometry.appKitRect(
            axPosition: CGPoint(x: 50, y: 1000),
            axSize: CGSize(width: 100, height: 30),
            primaryScreenFrame: primary
        )
        #expect(rect == CGRect(x: 50, y: -130, width: 100, height: 30))
        #expect(secondary.contains(rect))
    }

    /// The flip uses the primary frame's maxY / minX rather than assuming height-only math.
    @Test func primaryFrameWithNonZeroOriginIsRespected() {
        let oddPrimary = CGRect(x: 10, y: 20, width: 1000, height: 800)
        let rect = AXGeometry.appKitRect(
            axPosition: CGPoint(x: 0, y: 0),
            axSize: CGSize(width: 100, height: 40),
            primaryScreenFrame: oddPrimary
        )
        #expect(rect == CGRect(x: 10, y: 780, width: 100, height: 40))
    }

    // MARK: - Global ↔ AppKit for several displays

    /// Taller display left of the primary, reaching below its bottom: AppKit frame (-1920, -100, 1920, 1200).
    @Test func pointOnTallerDisplayLeftOfPrimary() {
        let left = CGRect(x: -1920, y: -100, width: 1920, height: 1200)
        let appKit = CGPoint(x: -1000, y: 1000)
        #expect(left.contains(appKit))

        let global = AXGeometry.globalPoint(appKitPoint: appKit, primaryScreenFrame: primary)

        #expect(global == CGPoint(x: -1000, y: -100))
        #expect(AXGeometry.appKitPoint(globalPoint: global, primaryScreenFrame: primary) == appKit)
    }

    /// Larger display above the primary: AppKit frame (0, 900, 2560, 1440), so its global y is negative.
    @Test func pointOnDisplayAbovePrimary() {
        let appKit = CGPoint(x: 100, y: 2000)

        let global = AXGeometry.globalPoint(appKitPoint: appKit, primaryScreenFrame: primary)

        #expect(global == CGPoint(x: 100, y: -1100))
        #expect(AXGeometry.appKitPoint(globalPoint: global, primaryScreenFrame: primary) == appKit)
    }

    @Test func globalRectOnDisplayLeftOfPrimaryConvertsToAppKit() {
        let globalRect = CGRect(x: -1500, y: 850, width: 400, height: 20)

        let appKit = AXGeometry.appKitRect(globalRect: globalRect, primaryScreenFrame: primary)

        #expect(appKit == CGRect(x: -1500, y: 30, width: 400, height: 20))
        #expect(AXGeometry.globalRect(appKitRect: appKit, primaryScreenFrame: primary) == globalRect)
    }

    @Test func rectRoundTripsOnDisplayAbovePrimary() {
        let appKit = CGRect(x: 200, y: 1800, width: 300, height: 40)

        let global = AXGeometry.globalRect(appKitRect: appKit, primaryScreenFrame: primary)

        #expect(global == CGRect(x: 200, y: -940, width: 300, height: 40))
        #expect(AXGeometry.appKitRect(globalRect: global, primaryScreenFrame: primary) == appKit)
    }

    // MARK: - PointerSample

    @Test func pointerSampleDerivesGlobalWithPrimaryFlip() {
        let sample = AXGeometry.pointerSample(appKit: CGPoint(x: 100, y: 800), primaryScreenFrame: primary)

        #expect(sample == PointerSample(appKit: CGPoint(x: 100, y: 800), global: CGPoint(x: 100, y: 100)))
    }

    @Test func pointerSampleAtPrimaryCorners() {
        let bottomLeft = AXGeometry.pointerSample(appKit: .zero, primaryScreenFrame: primary)
        let topLeft = AXGeometry.pointerSample(appKit: CGPoint(x: 0, y: 900), primaryScreenFrame: primary)

        #expect(bottomLeft.global == CGPoint(x: 0, y: 900))
        #expect(topLeft.global == .zero)
    }

    @Test func pointerSampleOnSecondaryDisplayBelowPrimary() {
        let sample = AXGeometry.pointerSample(appKit: CGPoint(x: 50, y: -500), primaryScreenFrame: primary)

        #expect(sample.global == CGPoint(x: 50, y: 1400))
    }
}

import CoreGraphics
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
}

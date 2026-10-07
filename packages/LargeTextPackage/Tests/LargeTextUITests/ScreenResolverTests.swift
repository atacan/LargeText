import CoreGraphics
import Testing
@testable import LargeTextUI

@Suite("ScreenResolver")
struct ScreenResolverTests {
    /// Primary 1440×900 at the origin; secondary 1920×1080 to its right; a third one above the primary.
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
    private let above = ScreenDescriptor(
        id: 3,
        frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 900, width: 1440, height: 875)
    )
    private var screens: [ScreenDescriptor] { [primary, secondary, above] }

    @Test func targetOnSecondaryScreenWinsOverMouse() {
        let result = ScreenResolver.resolve(
            targetFrame: CGRect(x: 2000, y: 500, width: 400, height: 30),
            mouseLocation: CGPoint(x: 100, y: 100),
            screens: screens
        )
        #expect(result == secondary)
    }

    @Test func nilTargetUsesMouseScreen() {
        let result = ScreenResolver.resolve(
            targetFrame: nil,
            mouseLocation: CGPoint(x: 700, y: 1200),
            screens: screens
        )
        #expect(result == above)
    }

    @Test func targetOffAllScreensUsesMouseScreen() {
        let result = ScreenResolver.resolve(
            targetFrame: CGRect(x: -5000, y: -5000, width: 100, height: 100),
            mouseLocation: CGPoint(x: 3000, y: 10),
            screens: screens
        )
        #expect(result == secondary)
    }

    @Test func nothingMatchesFallsBackToPrimary() {
        let result = ScreenResolver.resolve(
            targetFrame: CGRect(x: -5000, y: -5000, width: 100, height: 100),
            mouseLocation: CGPoint(x: -9000, y: -9000),
            screens: screens
        )
        #expect(result == primary)
    }

    @Test func frameStraddlingTwoScreensPicksLargerOverlap() {
        // 100 pt on the primary, 300 pt on the secondary.
        let mostlySecondary = CGRect(x: 1340, y: 400, width: 400, height: 40)
        #expect(ScreenResolver.resolve(targetFrame: mostlySecondary, mouseLocation: .zero, screens: screens) == secondary)

        // 300 pt on the primary, 100 pt on the secondary.
        let mostlyPrimary = CGRect(x: 1140, y: 400, width: 400, height: 40)
        #expect(ScreenResolver.resolve(targetFrame: mostlyPrimary, mouseLocation: CGPoint(x: 3000, y: 10), screens: screens) == primary)
    }

    @Test func zeroSizeTargetUsesItsPoint() {
        let caret = CGRect(x: 2000, y: 300, width: 0, height: 20)
        #expect(ScreenResolver.resolve(targetFrame: caret, mouseLocation: .zero, screens: screens) == secondary)
    }

    @Test func mouseOnTopEdgeStillCounts() {
        let result = ScreenResolver.resolve(
            targetFrame: nil,
            mouseLocation: CGPoint(x: 3360, y: 1080),
            screens: screens
        )
        #expect(result == secondary)
    }

    @Test func noScreensReturnsNil() {
        #expect(ScreenResolver.resolve(targetFrame: nil, mouseLocation: .zero, screens: []) == nil)
    }
}

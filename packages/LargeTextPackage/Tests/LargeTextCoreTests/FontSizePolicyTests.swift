import Testing
@testable import LargeTextCore

struct FontSizePolicyTests {
    @Test func defaultIs64() {
        #expect(FontSizePolicy.default == FontSize(points: 64))
    }

    @Test func biggerAndSmallerStepBy8() {
        #expect(FontSizePolicy.apply(.bigger, to: FontSize(points: 64)) == FontSize(points: 72))
        #expect(FontSizePolicy.apply(.smaller, to: FontSize(points: 64)) == FontSize(points: 56))
    }

    @Test func resetReturnsDefault() {
        #expect(FontSizePolicy.apply(.reset, to: FontSize(points: 128)) == FontSizePolicy.default)
    }

    @Test func clampsToRange() {
        #expect(FontSizePolicy.apply(.bigger, to: FontSize(points: 200)) == FontSize(points: 200))
        #expect(FontSizePolicy.apply(.bigger, to: FontSize(points: 196)) == FontSize(points: 200))
        #expect(FontSizePolicy.apply(.smaller, to: FontSize(points: 24)) == FontSize(points: 24))
        #expect(FontSizePolicy.apply(.smaller, to: FontSize(points: 28)) == FontSize(points: 24))
    }

    @Test(arguments: [
        (10.0, 24.0), (24.0, 24.0), (100.0, 100.0), (200.0, 200.0), (500.0, 200.0),
        (Double.nan, 64.0), (Double.infinity, 64.0),
    ])
    func clamp(points: Double, expected: Double) {
        #expect(FontSizePolicy.clamp(FontSize(points: points)) == FontSize(points: expected))
    }
}
